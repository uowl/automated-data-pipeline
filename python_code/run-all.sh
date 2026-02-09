#!/usr/bin/env bash
# Run all pipeline components: install, init DB, start API + Web GUI (+ optional Scraper). Does not run a pipeline; trigger via Web GUI or CLI.
# Usage: ./run-all.sh   (from AutomatedDataPipeline folder)

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Automated Data Pipeline — run-all ==="

echo ""
echo "1. Installing dependencies (orchestrator, api, web, scraper)..."
cd orchestrator && npm install && cd ..
cd api        && npm install && cd ..
cd web        && npm install && cd ..
cd scraper    && npm install && cd ..

echo ""
echo "2. Initializing database..."
cd orchestrator && npm run init-db && cd ..

echo ""
echo "3. Starting API (port 3000) in background..."
(cd "$SCRIPT_DIR/api" && npm start) &
API_PID=$!
sleep 2

echo ""
echo "4. Starting Web GUI (port 5173) in background..."
(cd "$SCRIPT_DIR/web" && npm run dev) &
WEB_PID=$!
sleep 2

echo ""
echo "5. (Optional) Starting Scraper (port 3080) in background..."
(cd "$SCRIPT_DIR/scraper" && npm start) &
SCRAPER_PID=$!
sleep 1

echo ""
echo "=== Services started ==="
echo "  Web GUI:  http://localhost:5173"
echo "  API:      http://localhost:3000"
echo "  Scraper:  http://localhost:3080"
echo ""
echo "Press Ctrl+C to stop all services."
echo ""

cleanup() {
  echo ""
  echo "Stopping services..."
  kill $API_PID $WEB_PID $SCRAPER_PID 2>/dev/null || true
  exit 0
}
trap cleanup SIGINT SIGTERM

wait
