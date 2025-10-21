#!/bin/bash
# Phase 1: Preflight checks

set -euo pipefail

echo "Checking connectivity and prerequisites..."

# Ensure baseline packages when missing
MISSING=()
for tool in curl jq python3; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        MISSING+=("$tool")
    fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
    echo "Installing missing tools: ${MISSING[*]}" 
    # Map tools to apt packages
    PKGS=()
    for t in "${MISSING[@]}"; do
        case "$t" in
            curl) PKGS+=(curl) ;;
            jq) PKGS+=(jq) ;;
            python3) PKGS+=(python3) ;;
        esac
    done
    # Also try to install mtr-tiny and traceroute for path verification
    PKGS+=(mtr-tiny traceroute)
    export DEBIAN_FRONTEND=noninteractive
    sudo apt-get update -y >/dev/null 2>&1 || sudo apt-get update -y
    sudo apt-get install -y "${PKGS[@]}"
fi

# Re-check required tools
for tool in curl jq python3; do
    echo -n "Tool '$tool': "
    if command -v "$tool" &> /dev/null; then
        echo "✓"
    else
        echo "✗"
        exit 1
    fi
done

# Check DNS
echo -n "DNS resolution (api.binance.com): "
if dig +short api.binance.com @8.8.8.8 > /dev/null 2>&1; then
    echo "✓"
else
    echo "✗ (WARNING)"
fi

# Check internet connectivity
echo -n "Internet connectivity (curl): "
if curl -s --max-time 5 https://api.binance.com/api/v3/ping > /dev/null 2>&1; then
    echo "✓"
else
    echo "✗"
    exit 1
fi

echo "Preflight checks passed!"
