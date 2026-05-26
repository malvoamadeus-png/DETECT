param(
  [switch]$SkipFrontendBuild,
  [switch]$SkipEnvCheck
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

Push-Location $root
try {
  Write-Host "== PowerShell syntax =="
  $psScripts = Get-ChildItem -Path scripts -Filter *.ps1 -File
  foreach ($script in $psScripts) {
    $tokens = $null
    $parseErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors -and $parseErrors.Count) {
      throw "$($script.FullName) has syntax errors"
    }
    Write-Host "$($script.Name)=ok"
  }

  Write-Host "== Bash syntax =="
  bash -n scripts/linux/bootstrap-server.sh scripts/linux/install-worker.sh scripts/linux/healthcheck-worker.sh scripts/linux/restart-worker.sh scripts/linux/logs-worker.sh
  if ($LASTEXITCODE -ne 0) {
    throw "bash syntax check failed"
  }
  Write-Host "bash_scripts=ok"

  Write-Host "== Remote deploy dry-run =="
  $deployDryRun = & (Join-Path $root "scripts/deploy-linux.ps1") -HostName "dry-run@example" -DryRun 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "deploy-linux dry-run failed"
  }
  $deployScript = ($deployDryRun -join "`n")
  $requiredDeployFragments = @(
    "git clone",
    "git pull --ff-only origin main",
    "bash scripts/linux/install-worker.sh",
    "bash scripts/linux/healthcheck-worker.sh"
  )
  foreach ($fragment in $requiredDeployFragments) {
    if ($deployScript -notlike "*$fragment*") {
      throw "deploy-linux dry-run is missing: $fragment"
    }
  }
  if ($deployScript -match "(?m)^\s*exit\s+0\s*$") {
    throw "deploy-linux dry-run contains an unconditional exit 0 that can stop deployment early"
  }
  Write-Host "deploy_linux_dry_run=ok"

  Write-Host "== Python compile =="
  python -m compileall backend
  if ($LASTEXITCODE -ne 0) {
    throw "python compile failed"
  }

  if (-not $SkipEnvCheck) {
    Write-Host "== Backend env =="
    python backend/src/main.py check-env
    if ($LASTEXITCODE -ne 0) {
      throw "backend env check failed"
    }
  }

  if (-not $SkipFrontendBuild) {
    Write-Host "== Frontend build =="
    Push-Location frontend
    try {
      npm.cmd run build
      if ($LASTEXITCODE -ne 0) {
        throw "frontend build failed"
      }
    } finally {
      Pop-Location
    }
  }
} finally {
  Pop-Location
}
