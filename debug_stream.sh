#!/bin/bash
# Debug script to check JSON stream quality

echo "Starting stream capture (5 seconds)..."
sudo ./kim_temp_bin stream > stream_debug.log &
PID=$!
sleep 5
sudo kill $PID

echo "--- RAW OUTPUT START ---"
head -n 5 stream_debug.log
echo "--- RAW OUTPUT END ---"

echo ""
echo "--- JQ PARSE TEST ---"
# Try to parse the first valid line
grep "^{" stream_debug.log | head -1 | jq .
if [ $? -eq 0 ]; then
    echo "✅ JQ Parse Success"
else
    echo "❌ JQ Parse Failed"
fi
