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
