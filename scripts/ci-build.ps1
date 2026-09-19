<#
Build the HAP package for Windows CI.
Usage: powershell -File scripts/ci-build.ps1
Requirement: DevEco Studio/Hvigor and the HarmonyOS SDK must be installed.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ci-common.ps1')

try {
  Write-Host '[INFO] Building HAP...'
  $logPath = Invoke-CiHvigor `
    -Arguments @('assembleHap', '--mode', 'module', '-p', 'product=default') `
    -LogName 'build.log'

  $hapFiles = @(Get-ChildItem -Path (Join-Path (Get-CiProjectRoot) 'entry\build') -Filter '*.hap' -File -Recurse -ErrorAction SilentlyContinue)
  if ($hapFiles.Count -eq 0) {
    throw "Hvigor completed but no HAP artifact was found under entry\build. See $logPath"
  }

  Write-Host '[PASS] HAP build completed.'
  $hapFiles | ForEach-Object { Write-Host "[ARTIFACT] $($_.FullName)" }
  exit 0
}
catch {
  Write-Error $_
  exit 1
}
