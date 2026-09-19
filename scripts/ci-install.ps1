<#
Install project dependencies for Windows CI.
Usage: powershell -File scripts/ci-install.ps1
Requirement: ohpm must be available on PATH.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ci-common.ps1')

$logPath = Get-CiReportPath -Name 'dependencies.log'
$previousLocation = Get-Location

try {
  $ohpm = Get-Command ohpm -ErrorAction SilentlyContinue
  if ($null -eq $ohpm) {
    throw 'ohpm was not found on PATH. Install the HarmonyOS command-line tools or add ohpm to PATH.'
  }

  Set-Location (Get-CiProjectRoot)
  Write-Host "[INFO] Installing OpenHarmony dependencies..."
  & $ohpm.Source install 2>&1 | Tee-Object -FilePath $logPath
  $exitCode = $LASTEXITCODE
  if ($exitCode -ne 0) {
    throw "ohpm install failed with exit code $exitCode. See $logPath"
  }

  Write-Host "[PASS] Dependencies installed. Log: $logPath"
  exit 0
}
catch {
  Write-Error $_
  exit 1
}
finally {
  Set-Location $previousLocation
}
