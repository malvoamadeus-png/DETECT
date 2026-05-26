#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="${DETECT_SERVICE_NAME:-detect-worker}"

sudo systemctl restart "${SERVICE_NAME}.service"
sudo systemctl status "${SERVICE_NAME}.service" --no-pager
