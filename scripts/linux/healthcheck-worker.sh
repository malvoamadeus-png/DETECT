#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${DETECT_APP_DIR:-/opt/DETECT}"
SERVICE_NAME="${DETECT_SERVICE_NAME:-detect-worker}"

cd "$APP_DIR"

if [ ! -x ".venv/bin/python" ]; then
  echo "Missing virtualenv at $APP_DIR/.venv" >&2
  exit 1
fi

. .venv/bin/activate

echo "== service =="
systemctl is-active "${SERVICE_NAME}.service"

echo "== dashboard rows =="
python backend/src/main.py dashboard --limit 1

echo "== recent logs =="
journalctl -u "${SERVICE_NAME}.service" -n 40 --no-pager
