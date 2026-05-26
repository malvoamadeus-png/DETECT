#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${DETECT_APP_DIR:-/opt/DETECT}"
SERVICE_NAME="${DETECT_SERVICE_NAME:-detect-worker}"
MIN_DASHBOARD_ROWS="${DETECT_HEALTH_MIN_DASHBOARD_ROWS:-0}"

cd "$APP_DIR"

if [ ! -x ".venv/bin/python" ]; then
  echo "Missing virtualenv at $APP_DIR/.venv" >&2
  exit 1
fi

. .venv/bin/activate

echo "== service =="
service_state="$(systemctl is-active "${SERVICE_NAME}.service")"
echo "service_active=${service_state}"
if [ "$service_state" != "active" ]; then
  echo "Service is not active: ${SERVICE_NAME}.service" >&2
  exit 1
fi

echo "== dashboard rows =="
dashboard_json="$(python backend/src/main.py dashboard --limit 500)"
dashboard_rows="$(printf '%s' "$dashboard_json" | python -c 'import json, sys; print(len(json.load(sys.stdin)))')"
echo "dashboard_rows=${dashboard_rows}"
if [ "$dashboard_rows" -lt "$MIN_DASHBOARD_ROWS" ]; then
  echo "Dashboard rows ${dashboard_rows} below required minimum ${MIN_DASHBOARD_ROWS}" >&2
  exit 1
fi
printf '%s' "$dashboard_json" | python -c 'import json, sys; text=json.dumps(json.load(sys.stdin), indent=2, ensure_ascii=False); print("\n".join(text.splitlines()[:80]))'

echo "== recent logs =="
journalctl -u "${SERVICE_NAME}.service" -n 40 --no-pager
