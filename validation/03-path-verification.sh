#!/bin/bash
# Phase 3: Path verification

echo "Getting network path (mtr or traceroute)..."

# Try mtr first
if command -v mtr &> /dev/null; then
    echo "Using mtr:"
    mtr -c 5 -r api.binance.com
else
    echo "Using traceroute:"
    traceroute -m 15 api.binance.com || true
fi

echo ""
echo "Network path verification complete"
