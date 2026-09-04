#!/usr/bin/env bash
# ============================================================================
# fetch-test-models.sh — 获取多架构 Q4 测试模型
# 角色 C（质量保障）维护 · 阶段 0 交付物
# 用法：bash scripts/fetch-test-models.sh [架构名]
#   不带参数：下载全部 6 个架构模型
#   带参数：仅下载指定架构（llama/qwen2/gemma/mistral/deepseek/chatglm）
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MODEL_DIR="$PROJECT_ROOT/test/models/inference"
mkdir -p "$MODEL_DIR"

# 模型定义：架构|HuggingFace仓库|文件名|本地保存名
declare -a MODELS=(
  "llama|unsloth/TinyLlama-1.1B-Chat-v1.0-GGUF|tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf|tinyllama-1.1b-chat-q4_k_m.gguf"
  "qwen2|Qwen/Qwen2-0.5B-Instruct-GGUF|qwen2-0_5b-instruct-q4_k_m.gguf|qwen2-0.5b-instruct-q4_k_m.gguf"
  "gemma|bartowski/gemma-2-2b-it-GGUF|gemma-2-2b-it-Q4_K_M.gguf|gemma-2-2b-it-q4_k_m.gguf"
  "mistral|bartowski/Mistral-7B-Instruct-v0.3-GGUF|Mistral-7B-Instruct-v0.3-Q4_K_M.gguf|mistral-7b-instruct-v0.3-q4_k_m.gguf"
  "deepseek|bartowski/DeepSeek-R1-Distill-Qwen-1.5B-GGUF|DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf|deepseek-r1-distill-qwen-1.5b-q4_k_m.gguf"
  "chatglm|bartowski/chatglm3-6b-GGUF|chatglm3-6b-Q4_K_M.gguf|chatglm3-6b-q4_k_m.gguf"
)

HF_BASE="https://huggingface.co"

download_model() {
  local arch="$1" repo="$2" remote_file="$3" local_file="$4"
  local url="$HF_BASE/$repo/resolve/main/$remote_file"
  local dest="$MODEL_DIR/$local_file"

  if [ -f "$dest" ]; then
    echo "[SKIP] $arch: $local_file 已存在"
    return 0
  fi

  echo "[DOWNLOAD] $arch: $remote_file"
  echo "  来源: $url"
  echo "  目标: $dest"

  if command -v curl &>/dev/null; then
    curl -L -o "$dest" "$url" || {
      echo "[ERROR] 下载失败: $arch"
      rm -f "$dest"
      return 1
    }
  elif command -v wget &>/dev/null; then
    wget -O "$dest" "$url" || {
      echo "[ERROR] 下载失败: $arch"
      rm -f "$dest"
      return 1
    }
  else
    echo "[ERROR] 需要 curl 或 wget"
    return 1
  fi

  echo "[DONE] $arch: $local_file ($(du -h "$dest" | cut -f1))"
}

# 主逻辑
TARGET_ARCH="${1:-}"

for entry in "${MODELS[@]}"; do
  IFS='|' read -r arch repo remote_file local_file <<< "$entry"
  if [ -n "$TARGET_ARCH" ] && [ "$TARGET_ARCH" != "$arch" ]; then
    continue
  fi
  download_model "$arch" "$repo" "$remote_file" "$local_file" || {
    echo "[WARN] $arch 下载失败，跳过（可稍后重试）"
  }
done

echo ""
echo "=== 测试模型集状态 ==="
for entry in "${MODELS[@]}"; do
  IFS='|' read -r arch repo remote_file local_file <<< "$entry"
  dest="$MODEL_DIR/$local_file"
  if [ -f "$dest" ]; then
    size=$(du -h "$dest" | cut -f1)
    echo "  [OK]   $arch ($size) — $local_file"
  else
    echo "  [MISS] $arch — $local_file"
  fi
done
