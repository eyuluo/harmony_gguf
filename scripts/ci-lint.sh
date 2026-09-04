#!/usr/bin/env bash
# ============================================================================
# ci-lint.sh — ArkTS 代码检查脚本
# 角色 C（质量保障）维护
# 用法：bash scripts/ci-lint.sh
# 退出码：0 成功，非0 失败
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPORT_DIR="$PROJECT_ROOT/reports"
mkdir -p "$REPORT_DIR"

cd "$PROJECT_ROOT"

# 查找 hvigorw
HVIGORW="${HVIGORW:-}"
if [ -z "$HVIGORW" ]; then
  if command -v hvigorw &>/dev/null; then
    HVIGORW="hvigorw"
  elif [ -f "$DEVECO_HOME/tools/hvigor/bin/hvigorw.bat" ]; then
    HVIGORW="$DEVECO_HOME/tools/hvigor/bin/hvigorw.bat"
  else
    echo "[ERROR] 未找到 hvigorw，请设置 HVIGORW 或 DEVECO_HOME 环境变量"
    exit 1
  fi
fi

echo "[INFO] 使用 hvigorw: $HVIGORW"
echo "[INFO] 执行 codeLinter..."

# 运行 codeLinter
"$HVIGORW" codeLinter --mode module -p product=default 2>&1 | tee "$REPORT_DIR/lint-raw.log"

LINT_EXIT=${PIPESTATUS[0]}

if [ "$LINT_EXIT" -ne 0 ]; then
  echo "[FAIL] codeLinter 发现问题，详见 reports/lint-raw.log"
  exit "$LINT_EXIT"
fi

echo "[PASS] codeLinter 通过"
exit 0
