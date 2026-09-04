#!/usr/bin/env bash
# ============================================================================
# ci-cpp-test.sh — C++ 引擎测试脚本
# 角色 C（质量保障）维护
# 阶段 1 起启用，编译并运行 test/ 目录下的全部 6 个测试
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

# 测试目标列表
TARGETS=(
  "test-ggml-ops"
  "test-gguf-parse"
  "test-model-load"
  "test-smoke-generate"
  "test-tokenizer-roundtrip"
  "test-memory-check"
)

ALL_PASSED=true

for target in "${TARGETS[@]}"; do
  echo ""
  echo "--- 编译 $target ---"
  cmake --build "$BUILD_DIR" --target "$target" --config Debug -j$(nproc 2>/dev/null || echo 4) 2>&1 | tee "$REPORT_DIR/cpp-build-$target.log"
  BUILD_EXIT=${PIPESTATUS[0]}
  if [ "$BUILD_EXIT" -ne 0 ]; then
    echo "[FAIL] $target 编译失败"
    ALL_PASSED=false
    continue
  fi

  echo "--- 运行 $target ---"
  (cd "$TEST_DIR" && "$BUILD_DIR/$target" 2>&1) | tee "$REPORT_DIR/cpp-test-$target.log"
  TEST_EXIT=${PIPESTATUS[0]}

  if [ "$TEST_EXIT" -ne 0 ]; then
    echo "[FAIL] $target 测试未通过"
    ALL_PASSED=false
  else
    echo "[PASS] $target 测试通过"
  fi
done

echo ""
if [ "$ALL_PASSED" = true ]; then
  echo "[PASS] C++ 引擎测试全部通过"
  exit 0
else
  echo "[FAIL] C++ 引擎测试存在失败项"
  exit 1
fi