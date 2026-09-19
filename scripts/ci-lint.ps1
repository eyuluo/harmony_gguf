<#
Usage:
  1. Set CODELINTER_HOME to the CodeLinter command-line tools directory, for example:
       $env:CODELINTER_HOME = 'D:\Tools\EditTheCode\command-line-tools'
  2. Alternatively, set CODELINTER_NODE and CODELINTER_ENTRY to the full paths of
     the CodeLinter Node runtime and entry script.
  3. Run the CI lint wrapper from the project root, for example:
       powershell -ExecutionPolicy Bypass -File scripts/ci-lint.ps1

By default, only errors cause a non-zero exit code. Set CODELINTER_EXIT_ON to
override the threshold, for example: error,warn.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ci-common.ps1')

function Resolve-CodeLinterNode {
  $candidates = @()
  if ($env:CODELINTER_NODE) { $candidates += $env:CODELINTER_NODE }
  $toolsHome = if ($env:CODELINTER_HOME) { $env:CODELINTER_HOME } else { $env:CODELINE_TOOLS_HOME }
  if ($toolsHome) { $candidates += (Join-Path $toolsHome 'tool\node\node.exe') }
  $candidates += 'D:\Tools\EditTheCode\command-line-tools\tool\node\node.exe'
  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return (Resolve-Path -LiteralPath $candidate).Path }
  }
  throw 'CodeLinter Node runtime was not found. Set CODELINTER_NODE or CODELINTER_HOME.'
}

function Resolve-CodeLinterEntry {
  $candidates = @()
  if ($env:CODELINTER_ENTRY) { $candidates += $env:CODELINTER_ENTRY }
  $toolsHome = if ($env:CODELINTER_HOME) { $env:CODELINTER_HOME } else { $env:CODELINE_TOOLS_HOME }
  if ($toolsHome) { $candidates += (Join-Path $toolsHome 'codelinter\index.js') }
  $candidates += 'D:\Tools\EditTheCode\command-line-tools\codelinter\index.js'
  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return (Resolve-Path -LiteralPath $candidate).Path }
  }
  throw 'CodeLinter entry was not found. Set CODELINTER_ENTRY or CODELINTER_HOME.'
}

try {
  $projectRoot = Get-CiProjectRoot
  $node = Resolve-CodeLinterNode
  $entry = Resolve-CodeLinterEntry
  $toolsHome = if ($env:CODELINTER_HOME) { $env:CODELINTER_HOME } elseif ($env:CODELINE_TOOLS_HOME) { $env:CODELINE_TOOLS_HOME } else { 'D:\Tools\EditTheCode\command-line-tools' }
  $sdkRoot = Join-Path $toolsHome 'sdk'
  $config = Join-Path $projectRoot 'code-linter.json5'
  $report = Get-CiReportPath -Name 'lint-report.xml'
  $logPath = Get-CiReportPath -Name 'lint.log'
  $exitOn = if ($env:CODELINTER_EXIT_ON) { $env:CODELINTER_EXIT_ON } else { 'error' }

  if (-not (Test-Path -LiteralPath $sdkRoot -PathType Container)) { throw "CodeLinter SDK directory was not found: $sdkRoot" }
  if (-not (Test-Path -LiteralPath $config -PathType Leaf)) { throw "CodeLinter configuration was not found: $config" }

  Write-Host '[INFO] Running standalone CodeLinter...'
  & $node $entry $sdkRoot '--config' $config '--product' 'default' '--format' 'xml' '--output' $report '--exit-on' $exitOn $projectRoot 2>&1 |
    Tee-Object -FilePath $logPath
  $exitCode = $LASTEXITCODE
  if ($exitCode -ne 0) { throw "CodeLinter failed with exit code $exitCode. See $logPath" }

  Write-Host "[PASS] CodeLinter completed. Report: $report"
  exit 0
}
catch {
  Write-Error $_
  exit 1
}
