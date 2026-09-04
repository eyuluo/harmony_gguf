#!/usr/bin/env bash
# ============================================================================
# ci-build.sh — 构建 HAP 脚本
# 角色 C（质量保障）维护
# 用法：bash scripts/ci-build.sh
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
echo "[INFO] 开始构建 HAP..."

# 构建 HAP
"$HVIGORW" assembleHap --mode module -p product=default 2>&1 | tee "$REPORT_DIR/build-raw.log"

BUILD_EXIT=${PIPESTATUS[0]}

if [ "$BUILD_EXIT" -ne 0 ]; then
  echo "[FAIL] HAP 构建失败，详见 reports/build-raw.log"
  exit "$BUILD_EXIT"
fi

# 检查产物
HAP_DIR="$PROJECT_ROOT/entry/build/default/outputs/default"
if ls "$HAP_DIR"/*.hap 1>/dev/null 2>&1; then
  echo "[PASS] HAP 构建成功"
  ls -lh "$HAP_DIR"/*.hap
  exit 0
else
  echo "[FAIL] 未找到 HAP 产物"
  exit 1
fi
