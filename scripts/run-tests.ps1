#!/usr/bin/env powershell
# ============================================================================
# run-tests.ps1 — 本地测试一键运行脚本
# 角色 C（质量保障）维护
# 用法：
#   .\scripts\run-tests.ps1              # 全部测试
#   .\scripts\run-tests.ps1 -Lint         # 仅代码检查
#   .\scripts\run-tests.ps1 -Build        # 仅构建
#   .\scripts\run-tests.ps1 -Test         # 仅单元测试
#   .\scripts\run-tests.ps1 -CppTest      # C++ 引擎测试
# ============================================================================
param(
  [switch]$Lint,
  [switch]$Build,
  [switch]$Test,
  [switch]$CppTest
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ReportDir = Join-Path $ProjectRoot "reports"
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null

# 查找 hvigorw
$Hvigorw = $null
if (Get-Command hvigorw -ErrorAction SilentlyContinue) {
  $Hvigorw = "hvigorw"
} elseif (Test-Path "D:\Programs\DevEco Studio\tools\hvigor\bin\hvigorw.bat") {
  $Hvigorw = "D:\Programs\DevEco Studio\tools\hvigor\bin\hvigorw.bat"
} else {
  Write-Host "[ERROR] 未找到 hvigorw，请确认 DevEco Studio 安装路径" -ForegroundColor Red
  exit 1
}

Write-Host "[INFO] 使用 hvigorw: $Hvigorw" -ForegroundColor Cyan

# 如果未指定任何参数，运行全部
$RunAll = -not ($Lint -or $Build -or $Test -or $CppTest)

$ExitCode = 0

if ($RunAll -or $Lint) {
  Write-Host "`n=== 代码检查 (codeLinter) ===" -ForegroundColor Yellow
  & $Hvigorw codeLinter --mode module -p product=default 2>&1 | Tee-Object -FilePath (Join-Path $ReportDir "lint-raw.log")
  if ($LASTEXITCODE -ne 0) { $ExitCode = $LASTEXITCODE }
}

if ($RunAll -or $Build) {
  Write-Host "`n=== 构建 HAP (assembleHap) ===" -ForegroundColor Yellow
  & $Hvigorw assembleHap --mode module -p product=default 2>&1 | Tee-Object -FilePath (Join-Path $ReportDir "build-raw.log")
  if ($LASTEXITCODE -ne 0) { $ExitCode = $LASTEXITCODE }
}

if ($RunAll -or $Test) {
  Write-Host "`n=== 单元测试 (test) ===" -ForegroundColor Yellow
  & $Hvigorw test --mode module -p product=default 2>&1 | Tee-Object -FilePath (Join-Path $ReportDir "test-raw.log")
  if ($LASTEXITCODE -ne 0) { $ExitCode = $LASTEXITCODE }
}

if ($RunAll -or $CppTest) {
  Write-Host "`n=== C++ 引擎测试 ===" -ForegroundColor Yellow
  Write-Host "[SKIP] C++ 测试尚未接入构建系统，将在阶段 1 启用" -ForegroundColor DarkGray
}

Write-Host "`n=== 测试完成 (退出码: $ExitCode) ===" -ForegroundColor $(if ($ExitCode -eq 0) { "Green" } else { "Red" })
exit $ExitCode
