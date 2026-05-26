#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="${DETECT_SERVICE_NAME:-detect-worker}"
LINES="${DETECT_LOG_LINES:-120}"

journalctl -u "${SERVICE_NAME}.service" -n "$LINES" -f
