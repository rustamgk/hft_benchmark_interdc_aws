#!/bin/bash
# Phase 2a: Overlay RTT measurement (Singapore -> Tokyo tunnel endpoint)

TARGET_IP="${1:-192.168.250.1}"
RESULTS_DIR="${2:-.}"
COUNT=${3:-10}

echo "Measuring overlay RTT to $TARGET_IP ($COUNT pings)..."

OUT_FILE="$RESULTS_DIR/overlay_rtt.txt"
PING_LOG="$RESULTS_DIR/overlay_ping.log"

ping -c "$COUNT" -W 2 "$TARGET_IP" | tee "$PING_LOG"

# Extract min/avg/max/mdev line if present
STATS_LINE=$(grep -E 'min/avg/max/(mdev|stddev)' "$PING_LOG" | tail -n1 || true)
if [ -n "$STATS_LINE" ]; then
  # Format: rtt min/avg/max/mdev = 0.561/0.746/1.639/0.309 ms
  echo "$STATS_LINE" > "$OUT_FILE"
  echo "Overlay RTT stats saved to: $OUT_FILE"
else
  echo "No RTT stats line found; see $PING_LOG for details" > "$OUT_FILE"
fi

echo "Overlay RTT phase complete"
