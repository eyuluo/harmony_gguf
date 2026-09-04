#!/usr/bin/env bash
# ============================================================================
# ci-cpp-test.sh — C++ 引擎测试脚本
# 角色 C（质量保障）维护
# 阶段 1 起启用，编译并运行 test/ 目录下的测试
# 用法：bash scripts/ci-cpp-test.sh
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPORT_DIR="$PROJECT_ROOT/reports"
TEST_DIR="$PROJECT_ROOT/test"
BUILD_DIR="$TEST_DIR/build"
mkdir -p "$REPORT_DIR" "$BUILD_DIR"

cd "$TEST_DIR"

echo "[INFO] C++ 引擎测试"
echo "[INFO] 测试框架: test/testing.h"
echo "[INFO] 测试目录: test/harmony/"

# 检查 cmake 是否可用
if ! command -v cmake &>/dev/null; then
  echo "[ERROR] 未找到 cmake"
  exit 1
fi

echo "[INFO] 配置 CMake..."
cmake -B "$BUILD_DIR" -S . -DCMAKE_BUILD_TYPE=Debug 2>&1 | tee "$REPORT_DIR/cpp-cmake.log"
CMAKE_CONFIG_EXIT=${PIPESTATUS[0]}
if [ "$CMAKE_CONFIG_EXIT" -ne 0 ]; then
  echo "[FAIL] CMake 配置失败"
  exit "$CMAKE_CONFIG_EXIT"
fi

echo "[INFO] 编译测试..."
cmake --build "$BUILD_DIR" --target test-ggml-ops -j$(nproc 2>/dev/null || echo 4) 2>&1 | tee "$REPORT_DIR/cpp-build.log"
BUILD_EXIT=${PIPESTATUS[0]}
if [ "$BUILD_EXIT" -ne 0 ]; then
  echo "[FAIL] 编译失败"
  exit "$BUILD_EXIT"
fi

echo "[INFO] 运行 ggml 算子测试..."
"$BUILD_DIR/test-ggml-ops" 2>&1 | tee "$REPORT_DIR/cpp-test.log"
TEST_EXIT=${PIPESTATUS[0]}

if [ "$TEST_EXIT" -ne 0 ]; then
  echo "[FAIL] ggml 算子测试未通过"
  exit "$TEST_EXIT"
fi

echo "[PASS] C++ 引擎测试通过"
exit 0
