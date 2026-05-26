param(
  [string]$ProjectDir = "frontend",
  [string]$EnvPath = ".env",
  [ValidateSet("production", "preview", "development")]
  [string]$Environment = "production",
  [string[]]$Keys = @("SUPABASE_DB_URL"),
  [switch]$IncludePublicFallback,
  [switch]$AllowPlaceholders,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$projectPath = if ([System.IO.Path]::IsPathRooted($ProjectDir)) { $ProjectDir } else { Join-Path $root $ProjectDir }
$resolvedEnvPath = if ([System.IO.Path]::IsPathRooted($EnvPath)) { $EnvPath } else { Join-Path $root $EnvPath }

function Read-EnvFile {
  param([string]$Path)
  $values = @{}
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Env file not found: $Path"
  }
  foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
    $trimmed = $line.Trim()
    if (-not $trimmed -or $trimmed.StartsWith("#")) {
      continue
    }
    $parts = $trimmed.Split("=", 2)
    if ($parts.Count -ne 2) {
      continue
    }
    $name = $parts[0].Trim().TrimStart([char]0xFEFF)
    $value = $parts[1].Trim()
    if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
      $value = $value.Substring(1, $value.Length - 2)
    }
    $values[$name] = $value
  }
  return $values
}

if (-not (Test-Path -LiteralPath (Join-Path $projectPath "package.json"))) {
  throw "Project directory does not look like a frontend project: $projectPath"
}

if (-not $DryRun -and -not (Get-Command vercel -ErrorAction SilentlyContinue)) {
  throw "Vercel CLI is required. Install with: npm i -g vercel"
}

$envValues = Read-EnvFile -Path $resolvedEnvPath
$plannedKeys = [System.Collections.Generic.List[string]]::new()
foreach ($key in $Keys) {
  if (-not [string]::IsNullOrWhiteSpace($key) -and -not $plannedKeys.Contains($key)) {
    $plannedKeys.Add($key)
  }
}

if ($IncludePublicFallback) {
  foreach ($key in @("NEXT_PUBLIC_SUPABASE_URL", "NEXT_PUBLIC_SUPABASE_ANON_KEY")) {
    if (-not $plannedKeys.Contains($key)) {
      $plannedKeys.Add($key)
    }
  }
}

if (-not $plannedKeys.Count) {
  throw "No Vercel env keys requested."
}

$entries = @()
foreach ($key in $plannedKeys) {
  $value = ""
  if ($envValues.ContainsKey($key)) {
    $value = [string]$envValues[$key]
  }
  if (-not [string]::IsNullOrWhiteSpace($value)) {
    $entries += [pscustomobject]@{ Key = $key; Value = $value }
  }
}

if (-not $entries.Count) {
  if ($AllowPlaceholders) {
    Write-Host "vercel_env_source=ok $EnvPath"
    Write-Host "vercel_environment=$Environment"
    Write-Host "vercel_env_plan=placeholder_allowed"
    exit 0
  }
  throw "None of the requested Vercel env keys are set in $EnvPath."
}

$hasServerDatabaseUrl = @($entries | Where-Object { $_.Key -eq "SUPABASE_DB_URL" -or $_.Key -eq "DATABASE_URL" }).Count -gt 0
if (-not $hasServerDatabaseUrl) {
  throw "Vercel server routes need SUPABASE_DB_URL or DATABASE_URL."
}

Write-Host "vercel_env_source=ok $EnvPath"
Write-Host "vercel_environment=$Environment"

if ($DryRun) {
  foreach ($entry in $entries) {
    Write-Host "vercel_env_plan key=$($entry.Key) action=upsert"
  }
  exit 0
}

Push-Location $projectPath
try {
  foreach ($entry in $entries) {
    Write-Host "vercel_env_upsert key=$($entry.Key) environment=$Environment"
    $null = vercel env rm $entry.Key $Environment --yes 2>$null
    $entry.Value | vercel env add $entry.Key $Environment
    if ($LASTEXITCODE -ne 0) {
      throw "Failed to add Vercel env key: $($entry.Key)"
    }
  }
} finally {
  Pop-Location
}

Write-Host "vercel_env_sync=ok keys=$($entries.Count)"
