#!/bin/bash
# Phase 4: Geolocation verification

RESULTS_DIR="${1:-.}"

echo "Verifying geolocation..."

GEO_FILE="$RESULTS_DIR/geolocation.json"

# Get geolocation from ipinfo.io
curl -s ipinfo.io > "$GEO_FILE"

echo "Geolocation info:"
cat "$GEO_FILE" | jq '.'

echo ""
CITY=$(jq -r '.city' "$GEO_FILE")
COUNTRY=$(jq -r '.country' "$GEO_FILE")

echo "Results:"
echo "  City: $CITY"
echo "  Country: $COUNTRY"

if [ "$COUNTRY" = "JP" ] && [ "$CITY" = "Tokyo" ]; then
    echo "✓ Egress IP is from Tokyo!"
else
    echo "⚠ Warning: Expected Tokyo, got $CITY, $COUNTRY"
fi
