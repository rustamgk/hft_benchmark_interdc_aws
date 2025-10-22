#!/bin/bash

# Tokyo validation orchestrator
# Runs the validation phases directly from the Tokyo bastion host (public IP/EIP)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results/$(date +%Y%m%d-%H%M%S)-tokyo"
TERRAFORM_DIR="$SCRIPT_DIR/../terraform"

# Sensible defaults for fair, low-variance measurements (allow env override)
PIN_TOKYO_POP=${PIN_TOKYO_POP:-1}
KEEPALIVE=${KEEPALIVE:-1}
TLS13=${TLS13:-1}
BREAKDOWN=${BREAKDOWN:-1}

get_terraform_value() {
  local key=$1
  if [ -f "$TERRAFORM_DIR/terraform.tfstate" ]; then
    jq -r ".outputs.$key.value // empty" "$TERRAFORM_DIR/terraform.tfstate" 2>/dev/null || echo ""
  fi
  return 0
}

# Resolve Tokyo bastion public IP (or EIP)
TOKYO_BASTION_PUBLIC=${TOKYO_BASTION_PUBLIC:-$(cd "$TERRAFORM_DIR" 2>/dev/null && terraform output -raw tokyo_bastion_public_ip 2>/dev/null || get_terraform_value "tokyo_bastion_public_ip")}
TOKYO_BASTION_EGRESS=${TOKYO_BASTION_EGRESS:-$(cd "$TERRAFORM_DIR" 2>/dev/null && terraform output -raw tokyo_bastion_egress_ip 2>/dev/null || get_terraform_value "tokyo_bastion_egress_ip")}

SSH_USER=${SSH_USER:-ubuntu}
SSH_KEY="${SSH_KEY:-$HOME/.ssh/hft-benchmark.pem}"
SSH_HOST="${TOKYO_BASTION_EGRESS:-$TOKYO_BASTION_PUBLIC}"
SSH_TARGET="$SSH_USER@$SSH_HOST"

if [ -z "$SSH_HOST" ]; then
  echo "Error: Could not resolve Tokyo bastion IP from Terraform. Set TOKYO_BASTION_PUBLIC or run terraform apply." >&2
  exit 1
fi
if [ ! -f "$SSH_KEY" ]; then
  echo "Error: SSH key not found at $SSH_KEY" >&2
  exit 1
fi

mkdir -p "$RESULTS_DIR"

echo "========================================="
echo "Starting Tokyo Validation Suite"
echo "========================================="
echo "Tokyo bastion target: $SSH_TARGET"
echo "Expected Egress IP (Tokyo): ${TOKYO_BASTION_EGRESS:-$TOKYO_BASTION_PUBLIC}"
echo "SSH Key: $SSH_KEY"
echo "Local results directory: $RESULTS_DIR"
echo ""

REMOTE_VALIDATION_DIR="/tmp/hft-validation-$(date +%s)-tokyo"

echo "[0/6] Waiting for SSH on Tokyo bastion..."
for i in $(seq 1 60); do
  if ssh -i "$SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$SSH_TARGET" "echo ok" >/dev/null 2>&1; then
    break
  fi
  echo "  [$i/60] SSH not ready yet; retrying..."
  sleep 5
done

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_TARGET" \
  "mkdir -p $REMOTE_VALIDATION_DIR" >/dev/null 2>&1 || true

echo "[1/6] Copying validation scripts to Tokyo bastion..."
scp -i "$SSH_KEY" -r -o StrictHostKeyChecking=no -o ConnectTimeout=15 \
  "$SCRIPT_DIR"/{01-preflight.sh,02a-overlay-rtt.sh,02-baseline-latency.sh,02b-latency-keepalive.sh,03-path-verification.sh,04-geolocation.sh,06-generate-report.sh,analyze_latency.py} \
  "$SSH_TARGET:$REMOTE_VALIDATION_DIR/"
echo "✓ Scripts copied successfully"
echo ""

echo "[2/6] Running preflight checks on Tokyo bastion..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_TARGET" \
  "bash $REMOTE_VALIDATION_DIR/01-preflight.sh" 2>&1 | tee "$RESULTS_DIR/01-preflight.log"
echo "✓ Preflight checks complete"
echo ""

# Optional: measure overlay RTT from Tokyo -> Singapore tunnel IP
echo "[2.5/6] Measuring overlay RTT (Tokyo -> Singapore tun IP)..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_TARGET" \
  "bash $REMOTE_VALIDATION_DIR/02a-overlay-rtt.sh 192.168.250.2 $REMOTE_VALIDATION_DIR" 2>&1 | tee "$RESULTS_DIR/02a-overlay-rtt.log"
echo "✓ Overlay RTT measurement complete"
echo ""

echo "[3/6] Measuring latency from Tokyo (direct egress)..."

# Optionally resolve/pin to a Tokyo POP (should already be Tokyo, but this removes variance)
TOKYO_CF_IP=""
if [ "$PIN_TOKYO_POP" = "1" ]; then
  TOKYO_CF_IP=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$SSH_TARGET" \
    "dig +short api.binance.com | tail -n1" 2>/dev/null || echo "")
  if [ -n "$TOKYO_CF_IP" ]; then
    echo "Using Tokyo POP IP: $TOKYO_CF_IP"
  else
    echo "Warning: Could not resolve Tokyo POP IP; proceeding without pinning."
  fi
fi

BASE_CMD="bash $REMOTE_VALIDATION_DIR/02-baseline-latency.sh $REMOTE_VALIDATION_DIR"
if [ -n "$TOKYO_CF_IP" ]; then
  BASE_CMD="RESOLVE_HOST=api.binance.com RESOLVE_IP=$TOKYO_CF_IP $BASE_CMD"
fi
if [ "$TLS13" = "1" ]; then BASE_CMD="TLS13=1 $BASE_CMD"; fi
if [ "$BREAKDOWN" = "1" ]; then BASE_CMD="BREAKDOWN=1 $BASE_CMD"; fi

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_TARGET" "$BASE_CMD" 2>&1 | tee "$RESULTS_DIR/02-latency.log"
echo "✓ Latency measurement complete"
echo ""

if [ "$KEEPALIVE" = "1" ]; then
  echo "[3.5/6] Measuring latency with connection reuse (keepalive)..."
  KEEP_CMD="bash $REMOTE_VALIDATION_DIR/02b-latency-keepalive.sh $REMOTE_VALIDATION_DIR"
  if [ -n "$TOKYO_CF_IP" ]; then
    KEEP_CMD="RESOLVE_HOST=api.binance.com RESOLVE_IP=$TOKYO_CF_IP $KEEP_CMD"
  fi
  if [ "$TLS13" = "1" ]; then KEEP_CMD="TLS13=1 $KEEP_CMD"; fi
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_TARGET" "$KEEP_CMD" 2>&1 | tee "$RESULTS_DIR/02b-latency-keepalive.log"
  echo "✓ Keepalive latency measurement complete"
  echo ""
fi

echo "[4/6] Verifying network path from Tokyo..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_TARGET" \
  "bash $REMOTE_VALIDATION_DIR/03-path-verification.sh" 2>&1 | tee "$RESULTS_DIR/03-path.log"
echo "✓ Path verification complete"
echo ""

echo "[5/6] Verifying geolocation from Tokyo..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_TARGET" \
  "bash $REMOTE_VALIDATION_DIR/04-geolocation.sh $REMOTE_VALIDATION_DIR" 2>&1 | tee "$RESULTS_DIR/04-geolocation.log"
echo "✓ Geolocation verification complete"
echo ""

echo "[6/6] Generating report on Tokyo..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_TARGET" \
  "bash $REMOTE_VALIDATION_DIR/06-generate-report.sh $REMOTE_VALIDATION_DIR" 2>&1 | tee "$RESULTS_DIR/06-report.log"
echo "✓ Report generation complete"
echo ""

echo "[7/6] Copying results back to local machine..."
scp -i "$SSH_KEY" -r -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
  "$SSH_TARGET:$REMOTE_VALIDATION_DIR/"{latencies.txt,latency_stats.json,latencies_keepalive.txt,latency_stats_keepalive.json,latencies_breakdown.csv,latencies_keepalive_breakdown.csv,overlay_rtt.txt,geolocation.json,VALIDATION_REPORT.md,*.log} \
  "$RESULTS_DIR/" 2>/dev/null || true
echo "✓ Results copied successfully"
echo ""

# Clean up
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_TARGET" \
  "rm -rf $REMOTE_VALIDATION_DIR" 2>/dev/null || true

echo "========================================="
echo "Tokyo Validation Complete!"
echo "========================================="
echo "Results saved to: $RESULTS_DIR"
echo "Report: $RESULTS_DIR/VALIDATION_REPORT.md"
echo ""

if [ -f "$RESULTS_DIR/VALIDATION_REPORT.md" ]; then
  echo "Report Content:"
  echo "========================================="
  cat "$RESULTS_DIR/VALIDATION_REPORT.md"
else
  echo "Warning: VALIDATION_REPORT.md not found in local results"
fi
