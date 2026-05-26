param(
  [string]$Repo = "malvoamadeus-png/DETECT",
  [string]$Ref = "main",
  [string]$Workflow = "ci.yml",
  [switch]$StatusOnly,
  [switch]$Wait,
  [int]$TimeoutSeconds = 600
)

$ErrorActionPreference = "Stop"

function Get-OptionalGitHubToken {
  $token = $env:GITHUB_TOKEN
  if (-not $token) {
    $token = $env:GH_TOKEN
  }
  return $token
}

function Get-GitHubToken {
  $token = Get-OptionalGitHubToken
  if (-not $token) {
    throw "Missing GITHUB_TOKEN or GH_TOKEN. Create a GitHub token with Actions write access, set it in the environment, then rerun."
  }
  return $token
}

function Invoke-GitHub {
  param(
    [string]$Method,
    [string]$Uri,
    [object]$Body = $null
  )
  $headers = @{
    "Accept"               = "application/vnd.github+json"
    "Authorization"        = "Bearer $(Get-GitHubToken)"
    "X-GitHub-Api-Version" = "2022-11-28"
    "User-Agent"           = "DETECT-ci-trigger"
  }
  if ($null -eq $Body) {
    return Invoke-RestMethod -Method $Method -Headers $headers -Uri $Uri -TimeoutSec 30
  }
  return Invoke-RestMethod -Method $Method -Headers $headers -Uri $Uri -Body ($Body | ConvertTo-Json -Depth 10) -ContentType "application/json" -TimeoutSec 30
}

function Invoke-GitHubPublic {
  param([string]$Uri)
  $headers = @{
    "Accept"     = "application/vnd.github+json"
    "User-Agent" = "DETECT-ci-status"
  }
  $token = Get-OptionalGitHubToken
  if ($token) {
    $headers["Authorization"] = "Bearer $token"
    $headers["X-GitHub-Api-Version"] = "2022-11-28"
  }
  try {
    return Invoke-RestMethod -Method "GET" -Headers $headers -Uri $Uri -TimeoutSec 30
  } catch {
    $response = $_.Exception.Response
    $statusCode = if ($response) { [int]$response.StatusCode } else { 0 }
    if ($statusCode -eq 403) {
      Write-Host "ci_status=rate_limited uri=$Uri set GITHUB_TOKEN or GH_TOKEN for higher GitHub API limits"
      return $null
    }
    throw
  }
}

function Show-CIStatus {
  $repoUri = "https://api.github.com/repos/$Repo"
  $workflowUri = "https://api.github.com/repos/$Repo/actions/workflows/$Workflow"
  $branchUri = "https://api.github.com/repos/$Repo/branches/$Ref"
  $runsUri = "https://api.github.com/repos/$Repo/actions/workflows/$Workflow/runs?branch=$Ref&per_page=10"

  $repoPayload = Invoke-GitHubPublic -Uri $repoUri
  if (-not $repoPayload) {
    return
  }
  $workflowPayload = Invoke-GitHubPublic -Uri $workflowUri
  if (-not $workflowPayload) {
    return
  }
  $branchPayload = Invoke-GitHubPublic -Uri $branchUri
  if (-not $branchPayload) {
    return
  }
  $runsPayload = Invoke-GitHubPublic -Uri $runsUri
  if (-not $runsPayload) {
    return
  }
  $headSha = [string]$branchPayload.commit.sha
  $matchingRun = @($runsPayload.workflow_runs | Where-Object { $_.head_sha -eq $headSha } | Select-Object -First 1)

  Write-Host "repo=$($repoPayload.full_name) default_branch=$($repoPayload.default_branch) disabled=$($repoPayload.disabled)"
  Write-Host "workflow=$($workflowPayload.name) state=$($workflowPayload.state) path=$($workflowPayload.path)"
  Write-Host "branch=$Ref head=$headSha"
  if ($matchingRun) {
    Write-Host "head_run=found status=$($matchingRun.status) conclusion=$($matchingRun.conclusion) url=$($matchingRun.html_url)"
  } else {
    Write-Host "head_run=missing no run found for $headSha"
  }
}

if ($StatusOnly) {
  Show-CIStatus
  exit 0
}

$dispatchUri = "https://api.github.com/repos/$Repo/actions/workflows/$Workflow/dispatches"
Invoke-GitHub -Method "POST" -Uri $dispatchUri -Body @{ ref = $Ref }
Write-Host "ci_dispatch=ok repo=$Repo workflow=$Workflow ref=$Ref"

if (-not $Wait) {
  exit 0
}

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$runsUri = "https://api.github.com/repos/$Repo/actions/workflows/$Workflow/runs?branch=$Ref&event=workflow_dispatch&per_page=5"
do {
  Start-Sleep -Seconds 10
  $runs = Invoke-GitHub -Method "GET" -Uri $runsUri
  $run = @($runs.workflow_runs | Sort-Object created_at -Descending | Select-Object -First 1)
  if ($run) {
    Write-Host "ci_run status=$($run.status) conclusion=$($run.conclusion) url=$($run.html_url)"
    if ($run.status -eq "completed") {
      if ($run.conclusion -ne "success") {
        throw "CI completed with conclusion=$($run.conclusion)"
      }
      exit 0
    }
  } else {
    Write-Host "ci_run=waiting"
  }
} while ((Get-Date) -lt $deadline)

throw "Timed out waiting for CI workflow_dispatch run."
