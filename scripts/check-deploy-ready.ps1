param(
  [string]$VercelBaseUrl = "",
  [string]$SshHost = "",
  [string]$GitHubRepo = "malvoamadeus-png/DETECT"
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

function Test-GitHubActions {
  param(
    [string]$Repo,
    [string]$ExpectedSha
  )
  try {
    $headers = @{ "User-Agent" = "DETECT-readiness" }
    $uri = "https://api.github.com/repos/$Repo/actions/runs?per_page=5"
    $runs = Invoke-RestMethod -Headers $headers -Uri $uri -TimeoutSec 30
    $run = @($runs.workflow_runs | Where-Object { $_.head_sha -eq $ExpectedSha } | Select-Object -First 1)
    if (-not $run) {
      Write-Check "github_actions" $false "no run found for $ExpectedSha"
      return
    }
    $ok = $run.status -eq "completed" -and $run.conclusion -eq "success"
    Write-Check "github_actions" $ok "status=$($run.status) conclusion=$($run.conclusion) url=$($run.html_url)"
  } catch {
    Write-Host "github_actions=skipped $($_.Exception.Message)"
  }
}

function Test-WorkflowFile {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    Write-Check "github_workflow_file" $false $Path
    return
  }
  $content = Get-Content -LiteralPath $Path -Raw
  $requiredFragments = @(
    "push:",
    "pull_request:",
    "workflow_dispatch:",
    "npm run build",
    "python -m pytest backend/tests",
    "Validate Linux deploy dry-run"
  )
  foreach ($fragment in $requiredFragments) {
    if ($content -notlike "*$fragment*") {
      Write-Check "github_workflow_file" $false "missing '$fragment'"
      return
    }
  }
  Write-Check "github_workflow_file" $true $Path
}

Push-Location $root
try {
  Write-Host "== repository =="
  $status = git status --short
  Write-Check "git_clean" (-not $status) ($(if ($status) { "working tree has changes or ignored-only status hidden" } else { "" }))
  $remoteHead = git ls-remote --heads origin main
  Write-Check "github_origin_main" ([bool]$remoteHead)
  $originSha = (git rev-parse origin/main).Trim()
  $headSha = (git rev-parse HEAD).Trim()
  Write-Check "head_matches_origin_main" ($headSha -eq $originSha) "head=$($headSha.Substring(0, 7)) origin=$($originSha.Substring(0, 7))"
  Test-WorkflowFile -Path (Join-Path $root ".github/workflows/ci.yml")
  Test-GitHubActions -Repo $GitHubRepo -ExpectedSha $originSha

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
    "scripts/check-migrations.ps1",
    "scripts/check-secrets.ps1",
    "scripts/check-vercel-env.ps1",
    "scripts/deploy-full.ps1",
    "scripts/deploy-linux.ps1",
    "scripts/deploy-vercel.ps1",
    "scripts/run-frontend.ps1",
    "scripts/run-once.ps1",
    "scripts/run-worker.ps1",
    "scripts/smoke-vercel.ps1",
    "scripts/trigger-ci.ps1"
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
