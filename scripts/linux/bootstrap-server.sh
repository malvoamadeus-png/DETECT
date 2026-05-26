#!/usr/bin/env bash
set -euo pipefail

if command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y git python3 python3-venv python3-pip ca-certificates
elif command -v dnf >/dev/null 2>&1; then
  sudo dnf install -y git python3 python3-pip ca-certificates
elif command -v yum >/dev/null 2>&1; then
  sudo yum install -y git python3 python3-pip ca-certificates
else
  echo "Unsupported Linux package manager. Install git, python3, python3-venv, and python3-pip manually." >&2
  exit 1
fi

git --version
python3 --version
