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
BUILD_DIR="$PROJECT_ROOT/test/build"
mkdir -p "$REPORT_DIR" "$BUILD_DIR"

cd "$PROJECT_ROOT"

echo "[INFO] C++ 引擎测试（阶段 1 起启用）"
echo "[INFO] 测试框架: test/testing.h"
echo "[INFO] 测试源码: test/test-*.cpp"

# C++ 测试需要链接引擎库，当前阶段尚未接入 CMake
# 阶段 1 将在 test/ 下添加 CMakeLists.txt 编译测试可执行文件
echo "[SKIP] C++ 测试尚未接入构建系统，将在阶段 1 启用"
exit 0
