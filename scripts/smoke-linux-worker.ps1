param(
  [Parameter(Mandatory = $true)]
  [string]$HostName,

  [string]$AppDir = "/opt/DETECT",
  [string]$ServiceName = "detect-worker",
  [int]$MinimumRows = 1,
  [int]$TimeoutSeconds = 180,
  [int]$IntervalSeconds = 15
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
  throw "ssh is required in PATH."
}

$remoteScript = @"
set -euo pipefail
cd '$AppDir'
export DETECT_APP_DIR='$AppDir'
export DETECT_SERVICE_NAME='$ServiceName'
export DETECT_HEALTH_MIN_DASHBOARD_ROWS='$MinimumRows'
bash scripts/linux/preflight-worker.sh
deadline=`$((`$(date +%s) + $TimeoutSeconds))
attempt=1
while true; do
  echo "worker_smoke_attempt=`$attempt"
  if bash scripts/linux/healthcheck-worker.sh; then
    exit 0
  fi
  if [ "`$(date +%s)" -ge "`$deadline" ]; then
    echo "Worker smoke test timed out after $TimeoutSeconds seconds." >&2
    exit 1
  fi
  attempt=`$((attempt + 1))
  sleep '$IntervalSeconds'
done
"@

Write-Host "Checking DETECT worker on ${HostName}:$AppDir minimum_rows=$MinimumRows timeout_seconds=$TimeoutSeconds"
$encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remoteScript))
ssh -o BatchMode=yes -o ConnectTimeout=15 $HostName "echo '$encoded' | base64 -d | bash"
if ($LASTEXITCODE -ne 0) {
  throw "Linux worker smoke test failed for $HostName"
}
