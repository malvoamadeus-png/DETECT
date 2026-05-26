$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

Push-Location $root
try {
  $trackedFiles = git ls-files
  $blockedNames = @(
    "^\.env$",
    "^\.env\.local$",
    "\.env\..*\.local$"
  )
  foreach ($file in $trackedFiles) {
    foreach ($pattern in $blockedNames) {
      if ($file -match $pattern) {
        throw "Secret-like env file is tracked: $file"
      }
    }
  }

  $textFiles = $trackedFiles | Where-Object {
    $_ -notmatch "package-lock\.json$" -and
    $_ -notmatch "\.(png|jpg|jpeg|gif|webp|ico|pdf|zip|gz|bin)$"
  }

  $secretPatterns = @(
    "sk-[A-Za-z0-9_-]{20,}",
    "postgres(?:ql)?://[^`"'\s]+:[^`"'\s]+@",
    "(?i)(api[_-]?key|secret|token|password)\s*=\s*[`"'][^`"']{8,}[`"']",
    "(?i)(api[_-]?key|secret|token|password)\s*:\s*[`"'][^`"']{8,}[`"']"
  )

  foreach ($file in $textFiles) {
    $content = Get-Content -LiteralPath $file -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) {
      continue
    }
    foreach ($pattern in $secretPatterns) {
      if ($content -match $pattern) {
        throw "Potential secret found in tracked file: $file"
      }
    }
  }

  Write-Host "secrets=ok tracked_files=$($trackedFiles.Count)"
} finally {
  Pop-Location
}
