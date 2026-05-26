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
  $readyScript = Get-Content -Raw -LiteralPath (Join-Path $root "scripts/check-deploy-ready.ps1")
  $requiredReadinessFragments = @(
    "function Test-GitHubOriginMain",
    "source=api",
    "https://api.github.com/repos/`$Repo/branches/main"
  )
  foreach ($fragment in $requiredReadinessFragments) {
    if ($readyScript -notlike "*$fragment*") {
      throw "check-deploy-ready.ps1 is missing GitHub origin fallback fragment: $fragment"
    }
  }
  Write-Host "readiness_github_origin_fallback=ok"

  $workflow = Get-Content -Raw -LiteralPath (Join-Path $root ".github/workflows/ci.yml")
  $requiredWorkflowFragments = @(
    'git fetch --depth 1 origin "${GITHUB_REF}"',
    "git checkout --force --detach FETCH_HEAD",
    "Frontend API error checks",
    "Frontend server DB checks"
  )
  foreach ($fragment in $requiredWorkflowFragments) {
    if ($workflow -notlike "*$fragment*") {
      throw "CI workflow is missing required manual checkout fragment: $fragment"
    }
  }
  if ($workflow -like "*actions/checkout@v4*") {
    throw "CI workflow should not use actions/checkout@v4 after manual checkout hardening."
  }
  if ($workflow -like "*GITHUB_HEAD_REF*") {
    throw "CI workflow should fetch GITHUB_REF so pull_request merge refs and fork PRs work."
  }
  Write-Host "workflow_manual_checkout=ok"

  $triggerScript = Get-Content -Raw -LiteralPath (Join-Path $root "scripts/trigger-ci.ps1")
  $requiredTriggerFragments = @(
    "function Get-OptionalGitHubToken",
    "ci_status=rate_limited",
    "set GITHUB_TOKEN or GH_TOKEN",
    "if (-not `$repoPayload)"
  )
  foreach ($fragment in $requiredTriggerFragments) {
    if ($triggerScript -notlike "*$fragment*") {
      throw "trigger-ci.ps1 is missing status/rate-limit handling fragment: $fragment"
    }
  }
  Write-Host "trigger_ci_rate_limit_handling=ok"

  Write-Host "== Bash syntax =="
  bash -n scripts/linux/bootstrap-server.sh scripts/linux/install-worker.sh scripts/linux/healthcheck-worker.sh scripts/linux/restart-worker.sh scripts/linux/logs-worker.sh scripts/linux/preflight-worker.sh
  if ($LASTEXITCODE -ne 0) {
    throw "bash syntax check failed"
  }
  Write-Host "bash_scripts=ok"

  Write-Host "== Linux preflight env fallback =="
  $preflightTemp = Join-Path $root ".tmp/preflight-env"
  New-Item -ItemType Directory -Force -Path $preflightTemp | Out-Null
  $preflightEnv = Join-Path $preflightTemp ".env"
  @"
OPENAI_API_KEY=x
OPENAI_BASE_URL=https://example.test/v1
DATABASE_URL=postgres://user.projref@host.example/db
"@ | Set-Content -LiteralPath $preflightEnv -Encoding utf8
  $bashRoot = (bash -lc "pwd").Trim()
  $preflight = bash -c "DETECT_APP_DIR='$bashRoot' DETECT_ENV_FILE='$bashRoot/.tmp/preflight-env/.env' DETECT_SERVICE_NAME='detect-worker' scripts/linux/preflight-worker.sh" 2>&1
  $preflightText = ($preflight -join "`n")
  if ($LASTEXITCODE -ne 0 -or $preflightText -notlike "*database_url=ok*") {
    Write-Host $preflightText
    throw "Linux preflight DATABASE_URL fallback check failed"
  }
  Write-Host "linux_preflight_database_url_fallback=ok"

  Write-Host "== Remote deploy dry-run =="
  $deployDryRun = powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "scripts/deploy-linux.ps1") -HostName "dry-run@example" -DryRun 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "deploy-linux dry-run failed"
  }
  $deployScript = ($deployDryRun -join "`n")
  $requiredDeployFragments = @(
    "git clone",
    "git pull --ff-only origin main",
    "python3 -m venv --help",
    "python3 -m pip --version",
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

  Write-Host "== Remote deploy upload-env dry-run =="
  $uploadEnvDryRun = powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "scripts/deploy-linux.ps1") -HostName "dry-run@example" -UploadEnv -DryRun 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "deploy-linux upload-env dry-run failed"
  }
  $uploadEnvScript = ($uploadEnvDryRun -join "`n")
  $requiredUploadFragments = @(
    "upload_env=dry_run temp=/tmp/detect-env-dry-run",
    "git clone",
    "install -m 600 '/tmp/detect-env-dry-run' '/opt/DETECT/.env'",
    "rm -f '/tmp/detect-env-dry-run'",
    "bash scripts/linux/install-worker.sh"
  )
  foreach ($fragment in $requiredUploadFragments) {
    if ($uploadEnvScript -notlike "*$fragment*") {
      throw "deploy-linux upload-env dry-run is missing: $fragment"
    }
  }
  if ($uploadEnvScript -match "scp\s+.*\.env") {
    throw "deploy-linux upload-env dry-run should not run scp."
  }
  Write-Host "deploy_linux_upload_env_dry_run=ok"

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

      Write-Host "== Frontend API error checks =="
      npm.cmd run check:api-errors
      if ($LASTEXITCODE -ne 0) {
        throw "frontend API error checks failed"
      }

      Write-Host "== Frontend server DB checks =="
      npm.cmd run check:server-db
      if ($LASTEXITCODE -ne 0) {
        throw "frontend server DB checks failed"
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
