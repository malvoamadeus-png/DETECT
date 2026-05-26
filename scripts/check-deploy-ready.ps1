param(
  [string]$VercelBaseUrl = "",
  [string]$SshHost = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

function Write-Check {
  param(
    [string]$Name,
    [bool]$Ok,
    [string]$Detail = ""
  )
  $status = if ($Ok) { "ok" } else { "missing" }
  if ($Detail) {
    Write-Host "$Name=$status $Detail"
  } else {
    Write-Host "$Name=$status"
  }
}

function Test-Command {
  param([string]$Name)
  return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

Push-Location $root
try {
  Write-Host "== repository =="
  $status = git status --short
  Write-Check "git_clean" (-not $status) ($(if ($status) { "working tree has changes or ignored-only status hidden" } else { "" }))
  $remoteHead = git ls-remote --heads origin main
  Write-Check "github_origin_main" ([bool]$remoteHead)

  Write-Host "== local tools =="
  Write-Check "ssh" (Test-Command "ssh")
  Write-Check "scp" (Test-Command "scp")
  Write-Check "vercel_cli" (Test-Command "vercel") "required for scripts/deploy-vercel.ps1"

  Write-Host "== vercel =="
  $vercelLink = Test-Path -LiteralPath (Join-Path $root "frontend/.vercel/project.json")
  Write-Check "vercel_link" $vercelLink "frontend/.vercel/project.json"
  if ($VercelBaseUrl) {
    & (Join-Path $root "scripts/smoke-vercel.ps1") -BaseUrl $VercelBaseUrl
  } else {
    Write-Host "vercel_smoke=skipped pass -VercelBaseUrl to test deployed app"
  }

  Write-Host "== backend env =="
  python backend/src/main.py check-env

  Write-Host "== script syntax =="
  $scripts = @(
    "scripts/check-deploy-ready.ps1",
    "scripts/deploy-linux.ps1",
    "scripts/deploy-vercel.ps1",
    "scripts/run-frontend.ps1",
    "scripts/run-once.ps1",
    "scripts/run-worker.ps1",
    "scripts/smoke-vercel.ps1"
  )
  foreach ($script in $scripts) {
    $tokens = $null
    $parseErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $script), [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors -and $parseErrors.Count) {
      throw "$script has syntax errors"
    }
    Write-Host "$script=ok"
  }

  if ($SshHost) {
    Write-Host "== ssh target =="
    ssh -o BatchMode=yes -o ConnectTimeout=10 $SshHost "echo ssh_target=ok"
    if ($LASTEXITCODE -ne 0) {
      throw "SSH target check failed for $SshHost"
    }
  } else {
    Write-Host "ssh_target=skipped pass -SshHost user@host to test worker target"
  }
} finally {
  Pop-Location
}
