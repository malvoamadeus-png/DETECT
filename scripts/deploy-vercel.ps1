param(
  [string]$ProjectDir = "frontend",
  [switch]$SkipSmoke,
  [string]$SmokeBaseUrl = ""
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command vercel -ErrorAction SilentlyContinue)) {
  throw "Vercel CLI is required. Install with: npm i -g vercel"
}

$root = Split-Path -Parent $PSScriptRoot
$frontend = Join-Path $root $ProjectDir

if (-not (Test-Path -LiteralPath (Join-Path $frontend "package.json"))) {
  throw "Project directory does not look like a Next app: $frontend"
}

Push-Location $frontend
try {
  Write-Host "Pulling Vercel production env for $frontend"
  vercel pull --yes --environment=production
  if ($LASTEXITCODE -ne 0) {
    throw "vercel pull failed"
  }

  Write-Host "Building Vercel output"
  vercel build --prod
  if ($LASTEXITCODE -ne 0) {
    throw "vercel build failed"
  }

  Write-Host "Deploying prebuilt output to production"
  $deployOutput = vercel deploy --prebuilt --prod
  if ($LASTEXITCODE -ne 0) {
    throw "vercel deploy failed"
  }
  $deployUrl = ($deployOutput | Select-Object -Last 1).Trim()
  Write-Host "vercel_url=$deployUrl"
} finally {
  Pop-Location
}

if (-not $SkipSmoke) {
  $target = if ($SmokeBaseUrl) { $SmokeBaseUrl } else { $deployUrl }
  if (-not $target) {
    throw "Missing smoke test URL. Pass -SmokeBaseUrl or inspect Vercel deploy output."
  }
  & (Join-Path $root "scripts/smoke-vercel.ps1") -BaseUrl $target
}
