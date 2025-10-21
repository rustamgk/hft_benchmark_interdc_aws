#!/bin/bash

# Baseline validation orchestrator (direct from Singapore baseline host)
# Connects directly to a Singapore instance with a public IP and runs the same phases.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results/$(date +%Y%m%d-%H%M%S)-baseline"
TERRAFORM_DIR="$SCRIPT_DIR/../terraform"

# Sensible defaults for fair, low-variance measurements (allow env override)
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

# Resolve target: Singapore baseline public IP
SINGAPORE_BASELINE_IP=${SINGAPORE_BASELINE_IP:-$(cd "$TERRAFORM_DIR" 2>/dev/null && terraform output -raw singapore_baseline_public_ip 2>/dev/null || get_terraform_value "singapore_baseline_public_ip")}
if [ -z "$SINGAPORE_BASELINE_IP" ]; then
  echo "Error: Could not resolve singapore_baseline_public_ip from Terraform. Set SINGAPORE_BASELINE_IP env var or run terraform apply." >&2
  exit 1
fi

SSH_USER=${SSH_USER:-ubuntu}
SSH_KEY="${SSH_KEY:-$HOME/.ssh/hft-benchmark.pem}"
SSH_TARGET="$SSH_USER@$SINGAPORE_BASELINE_IP"

if [ ! -f "$SSH_KEY" ]; then
  echo "Error: SSH key not found at $SSH_KEY" >&2
  exit 1
fi

mkdir -p "$RESULTS_DIR"

echo "========================================="
echo "Starting Baseline Validation Suite"
echo "========================================="
echo "Singapore baseline target: $SSH_TARGET"
echo "Expected Egress IP (Baseline): $SINGAPORE_BASELINE_IP"
echo "SSH Key: $SSH_KEY"
echo "Local results directory: $RESULTS_DIR"
echo ""

# Step 0: Wait for SSH and prepare remote dir
REMOTE_VALIDATION_DIR="/tmp/hft-validation-$(date +%s)-baseline"
echo "[0/6] Waiting for SSH on Singapore baseline..."
for i in $(seq 1 60); do
  if ssh -i "$SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$SSH_TARGET" "echo ok" >/dev/null 2>&1; then
    break
  fi
  echo "  [$i/60] SSH not ready yet; retrying..."
  sleep 5
done

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_TARGET" \
  "mkdir -p $REMOTE_VALIDATION_DIR" >/dev/null 2>&1 || true

# Step 1: Copy validation scripts
echo "[1/6] Copying validation scripts to Singapore baseline..."
scp -i "$SSH_KEY" -r -o StrictHostKeyChecking=no -o ConnectTimeout=15 \
  "$SCRIPT_DIR"/{01-preflight.sh,02-baseline-latency.sh,02b-latency-keepalive.sh,03-path-verification.sh,04-geolocation.sh,06-generate-report.sh,analyze_latency.py} \
  "$SSH_TARGET:$REMOTE_VALIDATION_DIR/"
echo "✓ Scripts copied successfully"
echo ""

# Step 2-6: Run validation on baseline
echo "[2/6] Running preflight checks on Singapore baseline..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_TARGET" \
  "bash $REMOTE_VALIDATION_DIR/01-preflight.sh" 2>&1 | tee "$RESULTS_DIR/01-preflight.log"
echo "✓ Preflight checks complete"
echo ""

echo "[3/6] Measuring baseline latency from Singapore (direct egress)..."
BASE_CMD="bash $REMOTE_VALIDATION_DIR/02-baseline-latency.sh $REMOTE_VALIDATION_DIR"
if [ "${TLS13}" = "1" ]; then BASE_CMD="TLS13=1 $BASE_CMD"; fi
if [ "${BREAKDOWN}" = "1" ]; then BASE_CMD="BREAKDOWN=1 $BASE_CMD"; fi
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_TARGET" "$BASE_CMD" 2>&1 | tee "$RESULTS_DIR/02-latency.log"
echo "✓ Latency measurement complete"
echo ""

# Optional keepalive latency phase
if [ "${KEEPALIVE}" = "1" ]; then
  echo "[3.5/6] Measuring baseline latency with connection reuse (keepalive)..."
  KEEP_CMD="bash $REMOTE_VALIDATION_DIR/02b-latency-keepalive.sh $REMOTE_VALIDATION_DIR"
  if [ "${TLS13}" = "1" ]; then KEEP_CMD="TLS13=1 $KEEP_CMD"; fi
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_TARGET" "$KEEP_CMD" 2>&1 | tee "$RESULTS_DIR/02b-latency-keepalive.log"
  echo "✓ Keepalive latency measurement complete"
  echo ""
fi

echo "[4/6] Verifying network path from Singapore baseline..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_TARGET" \
  "bash $REMOTE_VALIDATION_DIR/03-path-verification.sh" 2>&1 | tee "$RESULTS_DIR/03-path.log"
echo "✓ Path verification complete"
echo ""

echo "[5/6] Verifying geolocation from Singapore baseline..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_TARGET" \
  "bash $REMOTE_VALIDATION_DIR/04-geolocation.sh $REMOTE_VALIDATION_DIR" 2>&1 | tee "$RESULTS_DIR/04-geolocation.log"
echo "✓ Geolocation verification complete"
echo ""

echo "[6/6] Generating report on Singapore baseline..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_TARGET" \
  "bash $REMOTE_VALIDATION_DIR/06-generate-report.sh $REMOTE_VALIDATION_DIR" 2>&1 | tee "$RESULTS_DIR/06-report.log"
echo "✓ Report generation complete"
echo ""

# Pull results
echo "[7/6] Copying results back to local machine..."
scp -i "$SSH_KEY" -r -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
  "$SSH_TARGET:$REMOTE_VALIDATION_DIR/"{latencies.txt,latency_stats.json,latencies_keepalive.txt,latency_stats_keepalive.json,latencies_breakdown.csv,latencies_keepalive_breakdown.csv,geolocation.json,VALIDATION_REPORT.md,*.log} \
  "$RESULTS_DIR/" 2>/dev/null || true
echo "✓ Results copied successfully"
echo ""

# Clean up
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_TARGET" \
  "rm -rf $REMOTE_VALIDATION_DIR" 2>/dev/null || true

echo "========================================="
echo "Baseline Validation Complete!"
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
