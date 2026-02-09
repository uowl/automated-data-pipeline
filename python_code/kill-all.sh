#!/usr/bin/env bash
# Kill all pipeline services: API (3000), Web GUI / Vite (5173), Scraper (3080).
# Usage: ./kill-all.sh   (from AutomatedDataPipeline folder or anywhere)

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Stopping Automated Data Pipeline services ==="

kill_port() {
  local port=$1
  local name=$2
  local pid
  pid=$(lsof -ti ":$port" 2>/dev/null || true)
  if [ -n "$pid" ]; then
    echo "Stopping $name (port $port, PID $pid)..."
    kill $pid 2>/dev/null || true
    sleep 1
    kill -9 $pid 2>/dev/null || true
  elif command -v fuser >/dev/null 2>&1; then
    if fuser "$port/tcp" >/dev/null 2>&1; then
      echo "Stopping $name (port $port) with fuser..."
      fuser -k "$port/tcp" 2>/dev/null || true
    else
      echo "No process on port $port ($name)."
    fi
  else
    echo "No process on port $port ($name)."
  fi
}

kill_port 3000 "API"
kill_port 5173 "Web GUI (Vite)"
kill_port 3080 "Scraper"

echo ""
echo "Done. All pipeline services stopped."
