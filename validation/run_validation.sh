#!/bin/bash

# Main validation orchestrator
# Copies validation scripts to Singapore instance, runs validation there,
# and copies results back to local machine

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results/$(date +%Y%m%d-%H%M%S)"
TERRAFORM_DIR="$SCRIPT_DIR/../terraform"

# Function to extract values from terraform.tfstate
get_terraform_value() {
  local key=$1
  if [ -f "$TERRAFORM_DIR/terraform.tfstate" ]; then
    jq -r ".outputs.$key.value // empty" "$TERRAFORM_DIR/terraform.tfstate" 2>/dev/null || echo ""
  fi
  return 0
}

# Configuration - try multiple sources
if [ -z "$SINGAPORE_IP" ]; then
  # Try terraform output first (public IP)
  SINGAPORE_IP=$(cd "$TERRAFORM_DIR" 2>/dev/null && terraform output -raw singapore_instance_public_ip 2>/dev/null || echo "")
  
  # If that fails, try terraform.tfstate directly
  if [ -z "$SINGAPORE_IP" ]; then
    SINGAPORE_IP=$(get_terraform_value "singapore_instance_public_ip")
  fi
fi

# Always try to get private IP as well (for bastion access)
SINGAPORE_PRIVATE_IP=${SINGAPORE_PRIVATE_IP:-$(cd "$TERRAFORM_DIR" 2>/dev/null && terraform output -raw singapore_instance_private_ip 2>/dev/null || get_terraform_value "singapore_instance_private_ip")}

## Expected egress IP: prefer WireGuard NAT EIP (bastion) and fallback to NAT GW
EXPECTED_EGRESS=""
# Try bastion egress EIP first (Option A)
EXPECTED_EGRESS=$(cd "$TERRAFORM_DIR" 2>/dev/null && terraform output -raw tokyo_bastion_egress_ip 2>/dev/null || echo "")
if [ -z "$EXPECTED_EGRESS" ]; then
  EXPECTED_EGRESS=$(get_terraform_value "tokyo_bastion_egress_ip")
fi
# Fallback to NAT Gateway EIP (Option B)
if [ -z "$EXPECTED_EGRESS" ]; then
  EXPECTED_EGRESS=$(cd "$TERRAFORM_DIR" 2>/dev/null && terraform output -raw tokyo_nat_elastic_ip 2>/dev/null || echo "")
  if [ -z "$EXPECTED_EGRESS" ]; then
    EXPECTED_EGRESS=$(get_terraform_value "tokyo_nat_elastic_ip")
  fi
fi

# Try to get Tokyo bastion public/private IPs
if [ -z "$TOKYO_BASTION_PUBLIC" ]; then
  TOKYO_BASTION_PUBLIC=$(cd "$TERRAFORM_DIR" 2>/dev/null && terraform output -raw tokyo_bastion_public_ip 2>/dev/null || echo "")
fi
if [ -z "$TOKYO_BASTION_PRIVATE" ]; then
  TOKYO_BASTION_PRIVATE=$(cd "$TERRAFORM_DIR" 2>/dev/null && terraform output -raw tokyo_bastion_private_ip 2>/dev/null || echo "")
fi

# Fetch bastion EIP explicitly (preferred SSH jump host for Option A)
TOKYO_BASTION_EGRESS=$(cd "$TERRAFORM_DIR" 2>/dev/null && terraform output -raw tokyo_bastion_egress_ip 2>/dev/null || echo "")

SSH_KEY="${SSH_KEY:-$HOME/.ssh/hft-benchmark.pem}"
REMOTE_VALIDATION_DIR="/tmp/hft-validation-$(date +%s)"

# Build SSH/ SCP targets (prefer bastion jump to private IP if available)
SSH_USER=${SSH_USER:-ubuntu}
# Choose bastion SSH host: prefer EIP if present, else instance public IP
BASTION_SSH_HOST="$TOKYO_BASTION_PUBLIC"
if [ -n "$TOKYO_BASTION_EGRESS" ]; then
  BASTION_SSH_HOST="$TOKYO_BASTION_EGRESS"
fi

if [ -n "$BASTION_SSH_HOST" ] && [ -n "$SINGAPORE_PRIVATE_IP" ]; then
  SSH_TARGET="$SSH_USER@$SINGAPORE_PRIVATE_IP"
  SSH_JUMP_OPT="-J $SSH_USER@$BASTION_SSH_HOST"
  SCP_JUMP_OPT="-o ProxyJump=$SSH_USER@$BASTION_SSH_HOST"
else
  SSH_TARGET="$SSH_USER@$SINGAPORE_IP"
  SSH_JUMP_OPT=""
  SCP_JUMP_OPT=""
fi

# Validate required inputs
if [ -z "$SSH_TARGET" ]; then
  echo "Error: SINGAPORE_IP not set and could not be retrieved from terraform state."
  echo "Try one of the following:"
  echo "  1. Set environment variable: export SINGAPORE_IP=<ip>"
  echo "  2. Run from terraform directory: cd terraform && terraform apply"
  echo "  3. Check terraform.tfstate file exists at: $TERRAFORM_DIR/terraform.tfstate"
  exit 1
fi

if [ ! -f "$SSH_KEY" ]; then
  echo "Error: SSH key not found at $SSH_KEY"
  exit 1
fi

mkdir -p "$RESULTS_DIR"

echo "========================================="
echo "Starting 5-Phase Validation Suite"
echo "========================================="
echo "Singapore SSH target: $SSH_TARGET"
if [ -n "$SSH_JUMP_OPT" ]; then echo "Using bastion jump via: $BASTION_SSH_HOST"; fi
echo "Expected Egress IP (Tokyo): $EXPECTED_EGRESS"
if [ -n "$TOKYO_BASTION_EGRESS" ]; then
  echo "Tokyo Bastion (egress/EIP): $TOKYO_BASTION_EGRESS"
fi
if [ -n "$TOKYO_BASTION_PUBLIC" ]; then
  echo "Tokyo Bastion (instance public): $TOKYO_BASTION_PUBLIC"
fi
if [ -n "$TOKYO_BASTION_PRIVATE" ]; then
  echo "Tokyo Bastion (private): $TOKYO_BASTION_PRIVATE"
fi

# If a bastion is available, set proxy to force egress via Tokyo
# Remote proxy env (disabled by default; enable by exporting USE_BASTION_HTTP_PROXY=1)
REMOTE_PROXY_ENV=""
if [ "${USE_BASTION_HTTP_PROXY:-0}" = "1" ] && [ -n "$TOKYO_BASTION_PRIVATE" ]; then
  REMOTE_PROXY_ENV="https_proxy=http://$TOKYO_BASTION_PRIVATE:3128 http_proxy=http://$TOKYO_BASTION_PRIVATE:3128 no_proxy=169.254.169.254,169.254.0.0/16,10.0.0.0/8,10.1.0.0/16,amazonaws.com"
  echo "Remote will use proxy: http://$TOKYO_BASTION_PRIVATE:3128"
fi
echo "SSH Key: $SSH_KEY"
echo "Remote validation directory: $REMOTE_VALIDATION_DIR"
echo "Local results directory: $RESULTS_DIR"
echo ""

# Step 0: Wait for SSH over bastion to be reachable and create remote dir
echo "[0/6] Waiting for SSH on Singapore via bastion..."
for i in $(seq 1 60); do
  if ssh -i "$SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 $SSH_JUMP_OPT "$SSH_TARGET" "echo ok" >/dev/null 2>&1; then
    break
  fi
  echo "  [$i/60] SSH not ready yet; retrying..."
  # Every 3 attempts, run quick connectivity diagnostics from the bastion to the Singapore private IP
  if [ $((i % 3)) -eq 0 ] && [ -n "$BASTION_SSH_HOST" ]; then
    echo "  - Running quick diagnostics from bastion to $SINGAPORE_PRIVATE_IP"
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 "${SSH_USER}@${BASTION_SSH_HOST}" \
      "set -x; ip route get $SINGAPORE_PRIVATE_IP || true; ping -c1 -W1 $SINGAPORE_PRIVATE_IP || true; nc -z -w2 $SINGAPORE_PRIVATE_IP 22 >/dev/null 2>&1 && echo 'port 22 open' || echo 'port 22 closed'" \
      >/dev/null 2>&1 || true
  fi
  sleep 5
done

# Ensure the remote directory exists
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no $SSH_JUMP_OPT "$SSH_TARGET" \
  "mkdir -p $REMOTE_VALIDATION_DIR" >/dev/null 2>&1 || true

# Step 1: Copy validation scripts to Singapore
echo "[1/6] Copying validation scripts to Singapore instance..."
scp -i "$SSH_KEY" -r -o StrictHostKeyChecking=no -o ConnectTimeout=15 $SCP_JUMP_OPT \
  "$SCRIPT_DIR"/{01-preflight.sh,02-baseline-latency.sh,03-path-verification.sh,04-geolocation.sh,06-generate-report.sh,analyze_latency.py} \
  "$SSH_TARGET:$REMOTE_VALIDATION_DIR/"
echo "✓ Scripts copied successfully"
echo ""

# Step 2-6: Run validation on Singapore instance
echo "[2/6] Running preflight checks on Singapore..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no $SSH_JUMP_OPT "$SSH_TARGET" \
  "$REMOTE_PROXY_ENV bash $REMOTE_VALIDATION_DIR/01-preflight.sh" 2>&1 | tee "$RESULTS_DIR/01-preflight.log"
echo "✓ Preflight checks complete"
echo ""

echo "[3/6] Measuring baseline latency from Singapore..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no $SSH_JUMP_OPT "$SSH_TARGET" \
  "$REMOTE_PROXY_ENV bash $REMOTE_VALIDATION_DIR/02-baseline-latency.sh $REMOTE_VALIDATION_DIR" 2>&1 | tee "$RESULTS_DIR/02-latency.log"
echo "✓ Latency measurement complete"
echo ""

echo "[4/6] Verifying network path from Singapore..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no $SSH_JUMP_OPT "$SSH_TARGET" \
  "$REMOTE_PROXY_ENV bash $REMOTE_VALIDATION_DIR/03-path-verification.sh" 2>&1 | tee "$RESULTS_DIR/03-path.log"
echo "✓ Path verification complete"
echo ""

echo "[5/6] Verifying geolocation from Singapore..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no $SSH_JUMP_OPT "$SSH_TARGET" \
  "$REMOTE_PROXY_ENV bash $REMOTE_VALIDATION_DIR/04-geolocation.sh $REMOTE_VALIDATION_DIR" 2>&1 | tee "$RESULTS_DIR/04-geolocation.log"
echo "✓ Geolocation verification complete"
echo ""

echo "[6/6] Generating report on Singapore..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no $SSH_JUMP_OPT "$SSH_TARGET" \
  "$REMOTE_PROXY_ENV bash $REMOTE_VALIDATION_DIR/06-generate-report.sh $REMOTE_VALIDATION_DIR" 2>&1 | tee "$RESULTS_DIR/06-report.log"
echo "✓ Report generation complete"
echo ""

# Step 7: Copy results back to local machine
echo "[7/6] Copying results back to local machine..."
scp -i "$SSH_KEY" -r -o StrictHostKeyChecking=no -o ConnectTimeout=10 $SCP_JUMP_OPT \
  "$SSH_TARGET:$REMOTE_VALIDATION_DIR/"{latencies.txt,latency_stats.json,geolocation.json,VALIDATION_REPORT.md,*.log} \
  "$RESULTS_DIR/" 2>/dev/null || true
echo "✓ Results copied successfully"
echo ""

# Clean up remote directory
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no $SSH_JUMP_OPT "$SSH_TARGET" \
  "rm -rf $REMOTE_VALIDATION_DIR" 2>/dev/null || true

echo "========================================="
echo "Validation Complete!"
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
