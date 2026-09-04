#!/usr/bin/env bash
# ============================================================================
# ci-test.sh — ArkTS 单元测试脚本
# 角色 C（质量保障）维护
# 用法：bash scripts/ci-test.sh
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPORT_DIR="$PROJECT_ROOT/reports"
mkdir -p "$REPORT_DIR"

cd "$PROJECT_ROOT"

HVIGORW="${HVIGORW:-}"
if [ -z "$HVIGORW" ]; then
  if command -v hvigorw &>/dev/null; then
    HVIGORW="hvigorw"
  elif [ -n "${DEVECO_HOME:-}" ] && [ -f "$DEVECO_HOME/tools/hvigor/bin/hvigorw.bat" ]; then
    HVIGORW="$DEVECO_HOME/tools/hvigor/bin/hvigorw.bat"
  else
    echo "[ERROR] 未找到 hvigorw"
    exit 1
  fi
fi

echo "[INFO] 使用 hvigorw: $HVIGORW"
echo "[INFO] 执行 ArkTS 单元测试..."

# 运行单元测试
"$HVIGORW" test --mode module -p product=default 2>&1 | tee "$REPORT_DIR/test-raw.log"

TEST_EXIT=${PIPESTATUS[0]}

if [ "$TEST_EXIT" -ne 0 ]; then
  echo "[FAIL] 单元测试未通过，详见 reports/test-raw.log"
  exit "$TEST_EXIT"
fi

echo "[PASS] 单元测试通过"
exit 0
