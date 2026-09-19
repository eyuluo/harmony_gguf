<#
Common helpers for Windows CI scripts.
Dot-source this file from ci-install.ps1, ci-lint.ps1, or ci-build.ps1.
Logs are written to reports/ci.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:CiProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script:CiReportDirectory = Join-Path $script:CiProjectRoot 'reports\ci'

function Initialize-CiReportDirectory {
  New-Item -ItemType Directory -Path $script:CiReportDirectory -Force | Out-Null
  return $script:CiReportDirectory
}

function Get-CiProjectRoot {
  return $script:CiProjectRoot
}

function Get-CiReportPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name
  )

  Initialize-CiReportDirectory | Out-Null
  return (Join-Path $script:CiReportDirectory $Name)
}

function Resolve-CiHvigorw {
  $wrapper = Join-Path $script:CiProjectRoot 'hvigorw.bat'
  if (-not (Test-Path -LiteralPath $wrapper -PathType Leaf)) {
    throw "Repository hvigorw wrapper was not found: $wrapper"
  }

  return $wrapper
}

function Invoke-CiHvigor {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Arguments,

    [Parameter(Mandatory = $true)]
    [string]$LogName
  )

  $wrapper = Resolve-CiHvigorw
  $logPath = Get-CiReportPath -Name $LogName
  $previousLocation = Get-Location
  $previousErrorAction = $ErrorActionPreference

  try {
    Set-Location $script:CiProjectRoot
    $ErrorActionPreference = 'Continue'
    & $wrapper @Arguments 2>&1 | Tee-Object -FilePath $logPath
    $exitCode = $LASTEXITCODE
  }
  finally {
    $ErrorActionPreference = $previousErrorAction
    Set-Location $previousLocation
  }

  if ($exitCode -ne 0) {
    throw "Hvigor command failed with exit code $exitCode. See $logPath"
  }

  return $logPath
}
