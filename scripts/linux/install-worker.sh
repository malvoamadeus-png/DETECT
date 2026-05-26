#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${DETECT_APP_DIR:-/opt/DETECT}"
REPO_URL="${DETECT_REPO_URL:-https://github.com/malvoamadeus-png/DETECT.git}"
SERVICE_NAME="${DETECT_SERVICE_NAME:-detect-worker}"

if ! command -v git >/dev/null 2>&1; then
  echo "git is required" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required" >&2
  exit 1
fi

if [ ! -d "$APP_DIR/.git" ]; then
  mkdir -p "$(dirname "$APP_DIR")"
  git clone "$REPO_URL" "$APP_DIR"
fi

cd "$APP_DIR"
git fetch origin main
git checkout main
git pull --ff-only origin main

python3 -m venv .venv
. .venv/bin/activate
python -m pip install --upgrade pip
pip install -r backend/requirements.txt

if [ ! -f "$APP_DIR/.env" ]; then
  echo "Missing $APP_DIR/.env. Create it from .env.example before starting $SERVICE_NAME." >&2
  exit 1
fi

python backend/src/main.py check-env
python backend/src/main.py migrate
python backend/src/main.py dashboard --limit 1 >/dev/null

tmp_service="$(mktemp)"
cat >"$tmp_service" <<SERVICE
[Unit]
Description=DETECT Bankr recipient intelligence worker
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${APP_DIR}
EnvironmentFile=${APP_DIR}/.env
Environment=PYTHONUNBUFFERED=1
ExecStart=${APP_DIR}/.venv/bin/python -u ${APP_DIR}/backend/src/main.py run-worker
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICE

sudo install -m 0644 "$tmp_service" "/etc/systemd/system/${SERVICE_NAME}.service"
rm -f "$tmp_service"
sudo systemctl daemon-reload
sudo systemctl enable "${SERVICE_NAME}.service"

echo "Installed $SERVICE_NAME. Start or restart it with:"
echo "  sudo systemctl restart ${SERVICE_NAME}.service"
echo "  sudo systemctl status ${SERVICE_NAME}.service"
