#!/usr/bin/env bash
# Start only the API and Web GUI (use this if run-all.sh failed or you already have the DB).
# From AutomatedDataPipeline folder: ./start-web.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Starting API and Web GUI ==="

# Install if needed
if [ ! -d "api/node_modules" ]; then
  echo "Installing API dependencies..."
  (cd api && npm install)
fi
if [ ! -d "web/node_modules" ]; then
  echo "Installing Web dependencies..."
  (cd web && npm install)
fi

echo ""
echo "Starting API on http://localhost:3000 ..."
(cd api && npm start) &
API_PID=$!
sleep 2

echo "Starting Web GUI on http://localhost:5173 ..."
(cd web && npm run dev) &
WEB_PID=$!
sleep 3

echo ""
echo "Web GUI:  http://localhost:5173"
echo "API:      http://localhost:3000"
echo ""
echo "Press Ctrl+C to stop."

cleanup() {
  kill $API_PID $WEB_PID 2>/dev/null || true
  exit 0
}
trap cleanup SIGINT SIGTERM
wait
