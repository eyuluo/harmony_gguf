<#
Run the ArkTS code linter for Windows CI.
Usage: powershell -File scripts/ci-lint.ps1
Requirement: DevEco Studio/Hvigor must be discoverable by hvigorw.bat.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ci-common.ps1')

try {
  Write-Host '[INFO] Running codeLinter...'
  $logPath = Invoke-CiHvigor `
    -Arguments @('codeLinter', '--mode', 'module', '-p', 'product=default') `
    -LogName 'lint.log'
  Write-Host "[PASS] codeLinter completed. Log: $logPath"
  exit 0
}
catch {
  Write-Error $_
  exit 1
}
