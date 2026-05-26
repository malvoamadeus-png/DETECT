param(
  [string]$EnvPath = "frontend/.env.production.local",
  [switch]$AllowPlaceholders
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$resolvedPath = if ([System.IO.Path]::IsPathRooted($EnvPath)) { $EnvPath } else { Join-Path $root $EnvPath }

function Read-EnvFile {
  param([string]$Path)
  $values = @{}
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Env file not found: $Path"
  }
  foreach ($line in Get-Content -LiteralPath $Path) {
    $trimmed = $line.Trim()
    if (-not $trimmed -or $trimmed.StartsWith("#")) {
      continue
    }
    $parts = $trimmed.Split("=", 2)
    if ($parts.Count -ne 2) {
      continue
    }
    $name = $parts[0].Trim().TrimStart([char]0xFEFF)
    $value = $parts[1].Trim().Trim('"').Trim("'")
    $values[$name] = $value
  }
  return $values
}

$envValues = Read-EnvFile -Path $resolvedPath
$dbUrl = $envValues["SUPABASE_DB_URL"]
$databaseUrl = $envValues["DATABASE_URL"]

Write-Host "vercel_env_file=ok $EnvPath"
if (-not $dbUrl -and -not $databaseUrl) {
  if ($AllowPlaceholders) {
    Write-Host "server_database_url=placeholder_allowed"
    exit 0
  }
  throw "Missing SUPABASE_DB_URL or DATABASE_URL for Vercel server routes."
}

$chosen = if ($dbUrl) { "SUPABASE_DB_URL" } else { "DATABASE_URL" }
Write-Host "server_database_url=ok source=$chosen"

$publicUrl = $envValues["NEXT_PUBLIC_SUPABASE_URL"]
$publicKey = $envValues["NEXT_PUBLIC_SUPABASE_ANON_KEY"]
if (($publicUrl -and -not $publicKey) -or ($publicKey -and -not $publicUrl)) {
  throw "NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY must be set together or omitted together."
}

if ($publicUrl -and $publicKey) {
  Write-Host "public_supabase_fallback=ok"
} else {
  Write-Host "public_supabase_fallback=skipped optional"
}
