#!/usr/bin/env bash
# ============================================================================
# run-engine-tests.sh — M1 验收：一键运行全部 C++ 引擎测试
# 角色 C（质量保障）维护
# 用法：bash scripts/run-engine-tests.sh
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_DIR="$PROJECT_ROOT/test"
BUILD_DIR="$TEST_DIR/build"
REPORT_DIR="$PROJECT_ROOT/reports"
mkdir -p "$REPORT_DIR" "$BUILD_DIR"

cd "$TEST_DIR"

echo "=========================================="
echo "  Harmony-GGUF 引擎测试 (M1 验收)"
echo "=========================================="
echo ""

# 配置 CMake
echo "[1/4] 配置 CMake..."
cmake -B "$BUILD_DIR" -S . -DCMAKE_BUILD_TYPE=Debug 2>&1 | tee "$REPORT_DIR/cpp-cmake.log"
echo ""

# 编译全部测试
echo "[2/4] 编译全部测试..."
cmake --build "$BUILD_DIR" -j$(nproc 2>/dev/null || echo 4) 2>&1 | tee "$REPORT_DIR/cpp-build.log"
echo ""

# 运行全部测试
TESTS=(
    "test-ggml-ops:ggml 基础算子"
    "test-gguf-parse:GGUF 解析"
    "test-model-load:模型加载冒烟"
    "test-smoke-generate:主路径生成冒烟"
    "test-tokenizer-roundtrip:tokenizer 往返"
    "test-memory-check:内存检查"
)

TOTAL=0
PASSED=0
FAILED=0

echo "[3/4] 运行测试..."
echo ""

for entry in "${TESTS[@]}"; do
    IFS=':' read -r name label <<< "$entry"
    TOTAL=$((TOTAL + 1))
    echo "--- $label ($name) ---"
    if "$BUILD_DIR/$name" 2>&1 | tee "$REPORT_DIR/$name.log"; then
        echo "[PASS] $label"
        PASSED=$((PASSED + 1))
    else
        echo "[FAIL] $label"
        FAILED=$((FAILED + 1))
    fi
    echo ""
done

echo "=========================================="
echo "  M1 验收结果"
echo "=========================================="
echo "  总计: $TOTAL"
echo "  通过: $PASSED"
echo "  失败: $FAILED"
echo "=========================================="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
