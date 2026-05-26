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
  bash -n scripts/linux/bootstrap-server.sh scripts/linux/install-worker.sh scripts/linux/healthcheck-worker.sh scripts/linux/restart-worker.sh scripts/linux/logs-worker.sh scripts/linux/preflight-worker.sh
  if ($LASTEXITCODE -ne 0) {
    throw "bash syntax check failed"
  }
  Write-Host "bash_scripts=ok"

  Write-Host "== Remote deploy dry-run =="
  $deployDryRun = powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "scripts/deploy-linux.ps1") -HostName "dry-run@example" -DryRun 2>&1
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

  Write-Host "== Vercel env template =="
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "scripts/check-vercel-env.ps1") -EnvPath "frontend/.env.production.example" -AllowPlaceholders
  if ($LASTEXITCODE -ne 0) {
    throw "Vercel env template check failed"
  }
  if (-not (Test-Path -LiteralPath (Join-Path $root ".env.example"))) {
    throw "Missing root .env.example used by Linux worker deployment docs."
  }
  $envExample = Get-Content -Raw -LiteralPath (Join-Path $root ".env.example")
  $requiredEnvKeys = @(
    "OPENAI_API_KEY",
    "OPENAI_BASE_URL",
    "OPENAI_MODEL",
    "SUPABASE_DB_URL",
    "DETECT_POLL_SECONDS",
    "DETECT_TARGET_TWEETS",
    "DETECT_MAX_X_PAGES"
  )
  foreach ($key in $requiredEnvKeys) {
    if ($envExample -notmatch "(?m)^\s*$key=") {
      throw ".env.example is missing $key"
    }
  }
  Write-Host "root_env_example=ok .env.example"

  Write-Host "== Supabase migrations =="
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "scripts/check-migrations.ps1")
  if ($LASTEXITCODE -ne 0) {
    throw "Supabase migration check failed"
  }

  Write-Host "== Secret scan =="
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "scripts/check-secrets.ps1")
  if ($LASTEXITCODE -ne 0) {
    throw "Secret scan failed"
  }

  Write-Host "== Python compile =="
  python -m compileall backend
  if ($LASTEXITCODE -ne 0) {
    throw "python compile failed"
  }

  Write-Host "== Backend tests =="
  python -m pytest backend/tests
  if ($LASTEXITCODE -ne 0) {
    throw "backend tests failed"
  }

  if (-not $SkipEnvCheck) {
    Write-Host "== Backend env =="
    python backend/src/main.py check-env
    if ($LASTEXITCODE -ne 0) {
      throw "backend env check failed"
    }
  }

  if (-not $SkipFrontendBuild) {
    Write-Host "== Frontend lint =="
    Push-Location frontend
    try {
      npm.cmd run lint
      if ($LASTEXITCODE -ne 0) {
        throw "frontend lint failed"
      }

      Write-Host "== Frontend typecheck =="
      npm.cmd run typecheck
      if ($LASTEXITCODE -ne 0) {
        throw "frontend typecheck failed"
      }

      Write-Host "== Frontend API limit checks =="
      npm.cmd run check:limits
      if ($LASTEXITCODE -ne 0) {
        throw "frontend API limit checks failed"
      }

      Write-Host "== Frontend build =="
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
