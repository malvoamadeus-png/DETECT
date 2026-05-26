param(
  [Parameter(Mandatory = $true)]
  [string]$BaseUrl,

  [int]$MinimumRows = 1
)

$ErrorActionPreference = "Stop"

function Normalize-BaseUrl {
  param([string]$Value)
  $trimmed = $Value.Trim().TrimEnd("/")
  if ($trimmed -notmatch "^https?://") {
    return "https://$trimmed"
  }
  return $trimmed
}

function Invoke-Json {
  param([string]$Url)
  try {
    return Invoke-RestMethod -Uri $Url -TimeoutSec 30
  } catch {
    throw "Request failed for $Url`: $($_.Exception.Message)"
  }
}

$base = Normalize-BaseUrl $BaseUrl
Write-Host "Checking $base"

$homeResponse = Invoke-WebRequest -UseBasicParsing -Uri $base -TimeoutSec 30
if ($homeResponse.StatusCode -lt 200 -or $homeResponse.StatusCode -ge 400) {
  throw "Home page returned HTTP $($homeResponse.StatusCode)"
}
Write-Host "home=ok status=$($homeResponse.StatusCode)"

$health = Invoke-Json "$base/api/health"
if (-not $health.ok) {
  throw "Health check failed: $($health | ConvertTo-Json -Compress)"
}
if ([int]$health.dashboard_rows -lt $MinimumRows) {
  throw "Health check has too few rows: $($health.dashboard_rows), expected at least $MinimumRows"
}
Write-Host "health=ok dashboard_rows=$($health.dashboard_rows)"

$dashboard = Invoke-Json "$base/api/dashboard?limit=1"
if (-not $dashboard -or $dashboard.Count -lt 1) {
  throw "Dashboard API returned no rows"
}
Write-Host "dashboard=ok first_token=$($dashboard[0].token_symbol) first_account=$($dashboard[0].username)"
