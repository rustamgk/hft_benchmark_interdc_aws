#!/bin/bash
# Phase 2: Baseline latency measurement

RESULTS_DIR="${1:-.}"
ITERATIONS=${2:-100}

# Optional pinning: RESOLVE_HOST (default api.binance.com) and RESOLVE_IP
TARGET_HOST=${RESOLVE_HOST:-api.binance.com}
TARGET_URL="https://$TARGET_HOST/api/v3/time"

echo "Measuring latency ($ITERATIONS requests) to $TARGET_HOST ${RESOLVE_IP:+(pinned to $RESOLVE_IP)}..."

LATENCY_FILE="$RESULTS_DIR/latencies.txt"
BREAKDOWN_FILE="$RESULTS_DIR/latencies_breakdown.csv"
: > "$LATENCY_FILE"
[ "${BREAKDOWN:-0}" = "1" ] && echo "time_namelookup,time_connect,time_appconnect,time_starttransfer,time_total" > "$BREAKDOWN_FILE"

for i in $(seq 1 $ITERATIONS); do
    CURL_ARGS=( -s -o /dev/null )
    [ -n "${RESOLVE_IP:-}" ] && CURL_ARGS+=( --resolve "$TARGET_HOST:443:$RESOLVE_IP" )
    [ "${TLS13:-0}" = "1" ] && CURL_ARGS+=( --tlsv1.3 )

    if [ "${BREAKDOWN:-0}" = "1" ]; then
        LINE=$(curl "${CURL_ARGS[@]}" -w "%{time_namelookup},%{time_connect},%{time_appconnect},%{time_starttransfer},%{time_total}\n" "$TARGET_URL")
        echo "$LINE" >> "$BREAKDOWN_FILE"
        TIME=$(echo "$LINE" | awk -F, '{print $5}')
    else
        TIME=$(curl "${CURL_ARGS[@]}" -w "%{time_total}" "$TARGET_URL")
    fi
    echo "$TIME" >> "$LATENCY_FILE"
    [ $((i % 10)) -eq 0 ] && echo "  Completed: $i/$ITERATIONS"
done

echo "Latency measurements saved to: $LATENCY_FILE"
python3 "$(dirname "$0")/analyze_latency.py" "$LATENCY_FILE" > "$RESULTS_DIR/latency_stats.json"
echo "Statistics:"
cat "$RESULTS_DIR/latency_stats.json" | python3 -m json.tool
