param(
  [string]$SshHost = "",
  [string]$AppDir = "/opt/DETECT",
  [string]$VercelBaseUrl = "",
  [string]$VercelEnvPath = "frontend/.env.production.local",
  [string]$VercelEnvSourcePath = ".env",
  [string]$WorkerEnvPath = ".env",
  [int]$WorkerMinimumRows = 1,
  [switch]$UploadWorkerEnv,
  [switch]$SyncVercelEnv,
  [switch]$DeployVercel,
  [switch]$SkipLocalPreflight,
  [switch]$SkipReadiness,
  [switch]$SkipGitHubActionsCheck,
  [switch]$SkipVercelCliCheck,
  [switch]$SkipWorkerDeploy,
  [switch]$SkipVercelEnvCheck,
  [switch]$SkipVercelSmoke,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

function Invoke-Step {
  param(
    [string]$Name,
    [scriptblock]$Action
  )
  Write-Host "== $Name =="
  & $Action
}

Push-Location $root
try {
  if (-not $SkipLocalPreflight) {
    Invoke-Step "local preflight" {
      powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "scripts/verify-local.ps1")
      if ($LASTEXITCODE -ne 0) {
        throw "Local preflight failed."
      }
    }
  }

  if (-not $SkipReadiness) {
    Invoke-Step "deployment readiness" {
      $args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $root "scripts/check-deploy-ready.ps1"), "-Strict")
      if ($SkipGitHubActionsCheck) {
        $args += "-SkipGitHubActionsCheck"
      }
      if ($SkipVercelCliCheck) {
        $args += "-SkipVercelCliCheck"
      }
      if ($VercelBaseUrl) {
        $args += @("-VercelBaseUrl", $VercelBaseUrl)
      }
      if ($SshHost) {
        $args += @("-SshHost", $SshHost)
      }
      powershell.exe @args
      if ($LASTEXITCODE -ne 0) {
        throw "Deployment readiness check failed."
      }
    }
  }

  if ($VercelBaseUrl -and -not $SkipVercelEnvCheck) {
    Invoke-Step "Vercel env file" {
      powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "scripts/check-vercel-env.ps1") -EnvPath $VercelEnvPath
      if ($LASTEXITCODE -ne 0) {
        throw "Vercel env check failed."
      }
    }
  } elseif ($VercelBaseUrl) {
    Write-Host "vercel_env_file=skipped assuming Vercel Dashboard env is configured"
  }

  if ($SyncVercelEnv) {
    Invoke-Step "Vercel env sync" {
      $args = @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        (Join-Path $root "scripts/sync-vercel-env.ps1"),
        "-EnvPath",
        $VercelEnvSourcePath
      )
      if ($DryRun) {
        $args += "-DryRun"
      }
      powershell.exe @args
      if ($LASTEXITCODE -ne 0) {
        throw "Vercel env sync failed."
      }
    }
  }

  if ($DeployVercel) {
    Invoke-Step "Vercel deploy" {
      if ($DryRun) {
        Write-Host "vercel_deploy=dry_run"
        return
      }
      $args = @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        (Join-Path $root "scripts/deploy-vercel.ps1")
      )
      if ($SkipVercelSmoke) {
        $args += "-SkipSmoke"
      } elseif ($VercelBaseUrl) {
        $args += @("-SmokeBaseUrl", $VercelBaseUrl)
      }
      powershell.exe @args
      if ($LASTEXITCODE -ne 0) {
        throw "Vercel deploy failed."
      }
    }
  }

  if ($SshHost -and -not $SkipWorkerDeploy) {
    Invoke-Step "Linux worker deploy" {
      $args = @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        (Join-Path $root "scripts/deploy-linux.ps1"),
        "-HostName",
        $SshHost,
        "-AppDir",
        $AppDir
      )
      if ($UploadWorkerEnv) {
        $args += @("-UploadEnv", "-EnvPath", $WorkerEnvPath)
      }
      if ($DryRun) {
        $args += "-DryRun"
      }
      powershell.exe @args
      if ($LASTEXITCODE -ne 0) {
        throw "Linux worker deploy failed."
      }
    }
  } elseif (-not $SshHost) {
    Write-Host "worker_deploy=skipped pass -SshHost user@host to deploy worker"
  }

  if ($VercelBaseUrl -and -not $SkipVercelSmoke -and -not $DeployVercel) {
    Invoke-Step "Vercel smoke test" {
      powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "scripts/smoke-vercel.ps1") -BaseUrl $VercelBaseUrl
      if ($LASTEXITCODE -ne 0) {
        throw "Vercel smoke test failed."
      }
    }
  } elseif (-not $VercelBaseUrl) {
    Write-Host "vercel_smoke=skipped pass -VercelBaseUrl https://your-app.vercel.app to verify frontend"
  }

  if ($SshHost -and -not $SkipWorkerDeploy -and -not $DryRun) {
    Invoke-Step "Linux worker smoke test" {
      powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "scripts/smoke-linux-worker.ps1") -HostName $SshHost -AppDir $AppDir -MinimumRows $WorkerMinimumRows
      if ($LASTEXITCODE -ne 0) {
        throw "Linux worker smoke test failed."
      }
    }
  }
} finally {
  Pop-Location
}
