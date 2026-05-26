#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${DETECT_APP_DIR:-/opt/DETECT}"
SERVICE_NAME="${DETECT_SERVICE_NAME:-detect-worker}"
ENV_FILE="${DETECT_ENV_FILE:-$APP_DIR/.env}"

status=0

check_command() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    echo "$name=ok"
  else
    echo "$name=missing" >&2
    status=1
  fi
}

check_env_key() {
  local key="$1"
  if grep -Eq "^[[:space:]]*${key}=" "$ENV_FILE"; then
    echo "${key}=set"
  else
    echo "${key}=missing" >&2
    status=1
  fi
}

echo "== tools =="
check_command git
check_command python3
check_command systemctl

echo "== app =="
if [ -d "$APP_DIR/.git" ]; then
  echo "app_repo=ok $APP_DIR"
else
  echo "app_repo=missing $APP_DIR" >&2
  status=1
fi

if [ -f "$ENV_FILE" ]; then
  echo "env_file=ok $ENV_FILE"
  check_env_key OPENAI_API_KEY
  check_env_key OPENAI_BASE_URL
  check_env_key SUPABASE_DB_URL
else
  echo "env_file=missing $ENV_FILE" >&2
  status=1
fi

if [ -x "$APP_DIR/.venv/bin/python" ]; then
  echo "venv=ok $APP_DIR/.venv"
else
  echo "venv=missing $APP_DIR/.venv"
fi

echo "== service =="
if systemctl list-unit-files --no-legend "${SERVICE_NAME}.service" 2>/dev/null | grep -q "^${SERVICE_NAME}\.service"; then
  echo "service_unit=ok ${SERVICE_NAME}.service"
  systemctl is-enabled "${SERVICE_NAME}.service" || true
  systemctl is-active "${SERVICE_NAME}.service" || true
else
  echo "service_unit=missing ${SERVICE_NAME}.service"
fi

exit "$status"
