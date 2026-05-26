param(
  [string]$VercelBaseUrl = "",
  [string]$SshHost = "",
  [string]$GitHubRepo = "malvoamadeus-png/DETECT",
  [switch]$Strict,
  [switch]$SkipGitHubActionsCheck,
  [switch]$SkipVercelCliCheck
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$script:failedChecks = @()

function Write-Check {
  param(
    [string]$Name,
    [bool]$Ok,
    [string]$Detail = ""
  )
  $status = if ($Ok) { "ok" } else { "missing" }
  if (-not $Ok) {
    $script:failedChecks += $Name
  }
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

function Test-GitHubOriginMain {
  param(
    [string]$Repo,
    [string]$ExpectedSha
  )
  $remoteHead = ""
  try {
    $remoteHead = (git ls-remote --heads origin main 2>$null)
  } catch {
    $remoteHead = ""
  }
  if ($LASTEXITCODE -eq 0 -and $remoteHead) {
    Write-Check "github_origin_main" $true "source=git"
    return
  }
  try {
    $headers = @{ "User-Agent" = "DETECT-readiness" }
    $uri = "https://api.github.com/repos/$Repo/branches/main"
    $branch = Invoke-RestMethod -Headers $headers -Uri $uri -TimeoutSec 30
    $remoteSha = [string]$branch.commit.sha
    Write-Check "github_origin_main" ($remoteSha -eq $ExpectedSha) "source=api remote=$($remoteSha.Substring(0, 7)) expected=$($ExpectedSha.Substring(0, 7))"
  } catch {
    Write-Check "github_origin_main" $false "git and api failed: $($_.Exception.Message)"
  }
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
    $fallback = Test-GitHubActionsViaStatusScript -Repo $Repo -ExpectedSha $ExpectedSha -PrimaryError $_.Exception.Message
    if (-not $fallback) {
      Write-Check "github_actions" $false "api failed and fallback unavailable: $($_.Exception.Message)"
    }
  }
}

function Test-GitHubActionsViaStatusScript {
  param(
    [string]$Repo,
    [string]$ExpectedSha,
    [string]$PrimaryError
  )
  $scriptPath = Join-Path $root "scripts/trigger-ci.ps1"
  if (-not (Test-Path -LiteralPath $scriptPath)) {
    return $false
  }
  try {
    $output = powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Repo $Repo -StatusOnly 2>&1
    if ($LASTEXITCODE -ne 0) {
      return $false
    }
    $text = ($output -join "`n")
    if ($text -match "head_run=found status=([^\s]+) conclusion=([^\s]+) url=([^\r\n]+)") {
      $status = $matches[1]
      $conclusion = $matches[2]
      $url = $matches[3].Trim()
      $shaLine = [regex]::Match($text, "branch=.* head=([0-9a-f]{40})")
      if ($shaLine.Success -and $shaLine.Groups[1].Value -ne $ExpectedSha) {
        Write-Check "github_actions" $false "fallback head mismatch expected=$ExpectedSha actual=$($shaLine.Groups[1].Value) primary_error=$PrimaryError"
        return $true
      }
      $ok = $status -eq "completed" -and $conclusion -eq "success"
      Write-Check "github_actions" $ok "source=trigger-ci status=$status conclusion=$conclusion url=$url primary_error=$PrimaryError"
      return $true
    }
    if ($text -match "head_run=missing") {
      Write-Check "github_actions" $false "source=trigger-ci no run found for $ExpectedSha primary_error=$PrimaryError"
      return $true
    }
    if ($text -match "ci_status=rate_limited") {
      Write-Check "github_actions" $false "source=trigger-ci rate_limited primary_error=$PrimaryError"
      return $true
    }
    return $false
  } catch {
    return $false
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
  $originSha = (git rev-parse origin/main).Trim()
  $headSha = (git rev-parse HEAD).Trim()
  Test-GitHubOriginMain -Repo $GitHubRepo -ExpectedSha $headSha
  Write-Check "head_matches_origin_main" ($headSha -eq $originSha) "head=$($headSha.Substring(0, 7)) origin=$($originSha.Substring(0, 7))"
  Test-WorkflowFile -Path (Join-Path $root ".github/workflows/ci.yml")
  if ($SkipGitHubActionsCheck) {
    Write-Host "github_actions=skipped by flag"
  } else {
    Test-GitHubActions -Repo $GitHubRepo -ExpectedSha $originSha
  }

  Write-Host "== local tools =="
  Write-Check "ssh" (Test-Command "ssh")
  Write-Check "scp" (Test-Command "scp")
  if ($SkipVercelCliCheck) {
    Write-Host "vercel_cli=skipped by flag"
  } else {
    Write-Check "vercel_cli" (Test-Command "vercel") "required for scripts/deploy-vercel.ps1"
  }

  Write-Host "== vercel =="
  if ($SkipVercelCliCheck) {
    Write-Host "vercel_link=skipped by flag"
  } else {
    $vercelLink = Test-Path -LiteralPath (Join-Path $root "frontend/.vercel/project.json")
    Write-Check "vercel_link" $vercelLink "frontend/.vercel/project.json"
  }
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
    "scripts/smoke-linux-worker.ps1",
    "scripts/smoke-vercel.ps1",
    "scripts/sync-vercel-env.ps1",
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

  if ($Strict -and $script:failedChecks.Count) {
    throw "Readiness strict mode failed checks: $($script:failedChecks -join ', ')"
  }
} finally {
  Pop-Location
}
