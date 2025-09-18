#!/usr/bin/env sh
set -eu

BIN_DIR=$(dirname "$0")/..
BIN_DIR=$(cd "$BIN_DIR" && pwd)

PORT=${PORT:-8080}
export PORT
DB_PATH=${DB_PATH:-scan_demo.sqlite}
export SCAN_DEMO_DB=${SCAN_DEMO_DB:-$DB_PATH}

# Start backend
"$BIN_DIR/scan_demo" >/tmp/scan_demo.log 2>&1 &
SERVER_PID=$!
echo "Server started pid=$SERVER_PID on port $PORT"

# Wait a bit for server
sleep 1

# Run QML UI with qmlscene
if command -v qmlscene >/dev/null 2>&1; then
    qmlscene "$BIN_DIR/ui/main.qml"
else
    echo "qmlscene not found. Please install Qt5 qmlscene or run UI manually."
    wait $SERVER_PID || true
fi

kill $SERVER_PID 2>/dev/null || true
