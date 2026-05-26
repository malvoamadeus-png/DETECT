$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$migrationDir = Join-Path $root "supabase/migrations"

if (-not (Test-Path -LiteralPath $migrationDir)) {
  throw "Migration directory not found: $migrationDir"
}

$sql = (Get-ChildItem -LiteralPath $migrationDir -Filter "*.sql" -File | Sort-Object Name | ForEach-Object {
    Get-Content -LiteralPath $_.FullName -Raw
  }) -join "`n"

$requiredFragments = @(
  "CREATE TABLE IF NOT EXISTS detect_launches",
  "CREATE TABLE IF NOT EXISTS detect_accounts",
  "CREATE TABLE IF NOT EXISTS detect_x_posts",
  "CREATE TABLE IF NOT EXISTS detect_github_repos",
  "CREATE TABLE IF NOT EXISTS detect_account_assessments",
  "CREATE OR REPLACE VIEW detect_dashboard",
  "GRANT SELECT ON detect_dashboard TO anon, authenticated",
  "NOTIFY pgrst, 'reload schema'",
  "tweet_id text NOT NULL UNIQUE",
  "x_posts_target int NOT NULL DEFAULT 50",
  "github_repos_json",
  "recent_posts_json"
)

foreach ($fragment in $requiredFragments) {
  if ($sql -notlike "*$fragment*") {
    throw "Migration check failed. Missing: $fragment"
  }
}

Write-Host "migrations=ok files=$((Get-ChildItem -LiteralPath $migrationDir -Filter '*.sql' -File).Count)"
