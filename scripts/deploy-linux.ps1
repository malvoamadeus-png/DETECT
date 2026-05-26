param(
  [Parameter(Mandatory = $true)]
  [string]$HostName,

  [string]$AppDir = "/opt/DETECT",
  [string]$RepoUrl = "git@github.com:malvoamadeus-png/DETECT.git",
  [string]$ServiceName = "detect-worker",
  [string]$EnvPath = ".env",
  [switch]$UploadEnv,
  [switch]$SkipBootstrap,
  [switch]$SkipRestart,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Invoke-Remote {
  param([string]$Command)
  ssh $HostName $Command
  if ($LASTEXITCODE -ne 0) {
    throw "Remote command failed: $Command"
  }
}

function Get-RemoteBootstrapScript {
  @"
set -euo pipefail
if [ ! -d '$AppDir' ]; then
  sudo mkdir -p '$AppDir'
fi
sudo chown "`$(id -u):`$(id -g)" '$AppDir'
"@
}

function Get-RemoteDependencyBootstrapScript {
  @"
set -euo pipefail
if command -v git >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
  echo "Remote dependencies already installed."
elif command -v apt-get >/dev/null 2>&1; then
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
"@
}

if ($DryRun -and $UploadEnv) {
  throw "-DryRun cannot be combined with -UploadEnv."
}

if (-not $DryRun -and -not (Get-Command ssh -ErrorAction SilentlyContinue)) {
  throw "ssh is required in PATH."
}

if ($UploadEnv) {
  if (-not (Get-Command scp -ErrorAction SilentlyContinue)) {
    throw "scp is required in PATH when -UploadEnv is used."
  }
  if (-not (Test-Path -LiteralPath $EnvPath)) {
    throw "Env file not found: $EnvPath"
  }
  Write-Host "Uploading env file to ${HostName}:$AppDir/.env"
  $bootstrap = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-RemoteBootstrapScript)))
  Invoke-Remote "echo '$bootstrap' | base64 -d | bash"
  scp $EnvPath "${HostName}:$AppDir/.env"
  if ($LASTEXITCODE -ne 0) {
    throw "scp failed while uploading env file."
  }
}

$remoteScript = (Get-RemoteBootstrapScript)

if (-not $SkipBootstrap) {
  $remoteScript += "`n" + (Get-RemoteDependencyBootstrapScript)
}

$remoteScript += @"

if [ ! -d '$AppDir/.git' ]; then
  mkdir -p "`$(dirname '$AppDir')"
  git clone '$RepoUrl' '$AppDir'
fi
cd '$AppDir'
git fetch origin main
git checkout main
git pull --ff-only origin main
export DETECT_APP_DIR='$AppDir'
export DETECT_REPO_URL='$RepoUrl'
export DETECT_SERVICE_NAME='$ServiceName'
"@

if (-not $SkipBootstrap) {
  $remoteScript += @"

bash scripts/linux/bootstrap-server.sh
"@
}

$remoteScript += @"

bash scripts/linux/install-worker.sh
"@

if (-not $SkipRestart) {
  $remoteScript += @"

sudo systemctl restart '$ServiceName.service'
bash scripts/linux/healthcheck-worker.sh
"@
}

Write-Host "Deploying DETECT worker to ${HostName}:$AppDir"
$encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remoteScript))
if ($DryRun) {
  Write-Host "dry_run=ok"
  Write-Output $remoteScript
  exit 0
}
Invoke-Remote "echo '$encoded' | base64 -d | bash"
