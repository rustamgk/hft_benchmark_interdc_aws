#!/bin/bash
# Phase 2: Baseline latency measurement

RESULTS_DIR="${1:-.}"
ITERATIONS=${2:-100}

echo "Measuring latency ($ITERATIONS requests)..."

LATENCY_FILE="$RESULTS_DIR/latencies.txt"
> "$LATENCY_FILE"

for i in $(seq 1 $ITERATIONS); do
    TIME=$(curl -s -w "%{time_total}" -o /dev/null https://api.binance.com/api/v3/time)
    echo "$TIME" >> "$LATENCY_FILE"
    [ $((i % 10)) -eq 0 ] && echo "  Completed: $i/$ITERATIONS"
done

echo "Latency measurements saved to: $LATENCY_FILE"
python3 "$(dirname "$0")/analyze_latency.py" "$LATENCY_FILE" > "$RESULTS_DIR/latency_stats.json"
echo "Statistics:"
cat "$RESULTS_DIR/latency_stats.json" | python3 -m json.tool
