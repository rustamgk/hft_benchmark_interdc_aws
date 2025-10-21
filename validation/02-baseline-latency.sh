#!/bin/bash
# Phase 2: Baseline latency measurement

RESULTS_DIR="${1:-.}"
ITERATIONS=${2:-100}

# Optional pinning: RESOLVE_HOST (default api.binance.com) and RESOLVE_IP
TARGET_HOST=${RESOLVE_HOST:-api.binance.com}
TARGET_URL="https://$TARGET_HOST/api/v3/time"

echo "Measuring latency ($ITERATIONS requests) to $TARGET_HOST ${RESOLVE_IP:+(pinned to $RESOLVE_IP)}..."

LATENCY_FILE="$RESULTS_DIR/latencies.txt"
: > "$LATENCY_FILE"

for i in $(seq 1 $ITERATIONS); do
    if [ -n "${RESOLVE_IP:-}" ]; then
        TIME=$(curl -s --resolve "$TARGET_HOST:443:$RESOLVE_IP" -w "%{time_total}" -o /dev/null "$TARGET_URL")
    else
        TIME=$(curl -s -w "%{time_total}" -o /dev/null "$TARGET_URL")
    fi
    echo "$TIME" >> "$LATENCY_FILE"
    [ $((i % 10)) -eq 0 ] && echo "  Completed: $i/$ITERATIONS"
done

echo "Latency measurements saved to: $LATENCY_FILE"
python3 "$(dirname "$0")/analyze_latency.py" "$LATENCY_FILE" > "$RESULTS_DIR/latency_stats.json"
echo "Statistics:"
cat "$RESULTS_DIR/latency_stats.json" | python3 -m json.tool
