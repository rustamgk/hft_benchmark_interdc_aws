#!/bin/bash
# Phase 2b: Latency with connection reuse (keepalive)

RESULTS_DIR="${1:-.}"
ITERATIONS=${2:-100}

TARGET_HOST=${RESOLVE_HOST:-api.binance.com}
TARGET_URL="https://$TARGET_HOST/api/v3/time"

echo "Measuring keepalive latency ($ITERATIONS requests, excluding first cold-start) to $TARGET_HOST ${RESOLVE_IP:+(pinned to $RESOLVE_IP)}..."

LAT_FILE="$RESULTS_DIR/latencies_keepalive.txt"
CSV_FILE="$RESULTS_DIR/latencies_keepalive_breakdown.csv"
: > "$LAT_FILE"
echo "time_namelookup,time_connect,time_appconnect,time_starttransfer,time_total" > "$CSV_FILE"

# Build a single curl command with repeated requests using --next to allow connection reuse within one process.
CURL_BASE=(curl -sS --http1.1 -o /dev/null -w '%{time_namelookup},%{time_connect},%{time_appconnect},%{time_starttransfer},%{time_total}\n')
[ -n "${RESOLVE_IP:-}" ] && CURL_BASE+=( --resolve "$TARGET_HOST:443:$RESOLVE_IP" )
[ "${TLS13:-0}" = "1" ] && CURL_BASE+=( --tlsv1.3 )

CMD=("${CURL_BASE[@]}" "$TARGET_URL")
for i in $(seq 2 $ITERATIONS); do
  CMD+=( --next )
  # Repeat resolve for safety across segments
  [ -n "${RESOLVE_IP:-}" ] && CMD+=( --resolve "$TARGET_HOST:443:$RESOLVE_IP" )
  CMD+=( -sS --http1.1 -o /dev/null -w '%{time_namelookup},%{time_connect},%{time_appconnect},%{time_starttransfer},%{time_total}\n' )
  [ "${TLS13:-0}" = "1" ] && CMD+=( --tlsv1.3 )
  CMD+=( "$TARGET_URL" )
done

# Execute and capture per-request lines
OUTPUT=$("${CMD[@]}")
echo "$OUTPUT" >> "$CSV_FILE"

# Extract total times into latencies_keepalive.txt
# Skip the first request (cold start/connection establishment)
echo "$OUTPUT" | awk -F, 'NR > 1 {print $5}' >> "$LAT_FILE"

echo "Latency (keepalive) saved to: $LAT_FILE"
python3 "$(dirname "$0")/analyze_latency.py" "$LAT_FILE" > "$RESULTS_DIR/latency_stats_keepalive.json"
echo "Keepalive statistics:"
cat "$RESULTS_DIR/latency_stats_keepalive.json" | python3 -m json.tool
