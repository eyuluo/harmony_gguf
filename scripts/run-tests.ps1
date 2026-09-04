# ============================================================================
# run-tests.ps1 — 一键运行全部测试（PowerShell 版）
# 角色 C（质量保障）维护
# 用法：
#   .\scripts\run-tests.ps1              # 运行全部
#   .\scripts\run-tests.ps1 -Lint        # 仅代码检查
#   .\scripts\run-tests.ps1 -Build       # 仅构建
#   .\scripts\run-tests.ps1 -Test        # 仅 ArkTS 单元测试
#   .\scripts\run-tests.ps1 -CppTest     # 仅 C++ 引擎测试
# ============================================================================

param(
  [switch]$Lint,
  [switch]$Build,
  [switch]$Test,
  [switch]$CppTest
)

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

# 查找 cmake
$Cmake = $null
if (Get-Command cmake -ErrorAction SilentlyContinue) {
  $Cmake = "cmake"
} elseif (Test-Path "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe") {
  $Cmake = "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
}

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

  if (-not $Cmake) {
    Write-Host "[SKIP] 未找到 cmake，跳过 C++ 测试" -ForegroundColor DarkGray
  } else {
    $TestDir = Join-Path $ProjectRoot "test"
    $BuildDir = Join-Path $TestDir "build"

    # 配置 CMake
    Write-Host "[INFO] 配置 CMake..." -ForegroundColor Cyan
    & $Cmake -B $BuildDir -S $TestDir 2>&1 | Tee-Object -FilePath (Join-Path $ReportDir "cpp-cmake.log")
    if ($LASTEXITCODE -ne 0) {
      Write-Host "[FAIL] CMake 配置失败" -ForegroundColor Red
      $ExitCode = 1
    } else {
      # 测试目标列表
      $Targets = @("test-ggml-ops", "test-gguf-parse", "test-model-load", "test-smoke-generate", "test-tokenizer-roundtrip", "test-memory-check")
      $AllPassed = $true

      foreach ($target in $Targets) {
        Write-Host "`n--- 编译 $target ---" -ForegroundColor Cyan
        & $Cmake --build $BuildDir --target $target --config Debug 2>&1 | Tee-Object -FilePath (Join-Path $ReportDir "cpp-build-$target.log")
        if ($LASTEXITCODE -ne 0) {
          Write-Host "[FAIL] $target 编译失败" -ForegroundColor Red
          $AllPassed = $false
          continue
        }

        Write-Host "--- 运行 $target ---" -ForegroundColor Cyan
        $exePath = Join-Path $BuildDir "Debug\$target.exe"
        Push-Location $TestDir
        & $exePath 2>&1 | Tee-Object -FilePath (Join-Path $ReportDir "cpp-test-$target.log")
        $testExit = $LASTEXITCODE
        Pop-Location

        if ($testExit -ne 0) {
          Write-Host "[FAIL] $target 测试未通过" -ForegroundColor Red
          $AllPassed = $false
        } else {
          Write-Host "[PASS] $target 测试通过" -ForegroundColor Green
        }
      }

      if (-not $AllPassed) { $ExitCode = 1 }
    }
  }
}

Write-Host "`n=== 测试完成 (退出码: $ExitCode) ===" -ForegroundColor $(if ($ExitCode -eq 0) { "Green" } else { "Red" })
exit $ExitCode