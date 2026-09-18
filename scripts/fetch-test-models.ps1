# ============================================================================
# fetch-test-models.ps1 — 获取多架构 Q4 测试模型
# 角色 C（质量保障）维护 · 阶段 0 交付物
#
# 用法：
#   .\scripts\fetch-test-models.ps1
#       下载全部 6 个架构模型
#
#   .\scripts\fetch-test-models.ps1 llama
#       仅下载 llama
#
#   .\scripts\fetch-test-models.ps1 qwen2
#       仅下载 qwen2
#
# 支持：
#   llama / qwen2 / gemma / mistral / deepseek / chatglm
# ============================================================================

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$ModelDir = Join-Path $ProjectRoot "test\models\inference"

New-Item -ItemType Directory -Force -Path $ModelDir | Out-Null

$Models = @(
    @{
        Arch = "llama"
        Repo = "TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF"
        RemoteFile = "tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf"
        LocalFile = "tinyllama-1.1b-chat-q4_k_m.gguf"
    },
    @{
        Arch = "qwen2"
        Repo = "Qwen/Qwen2-0.5B-Instruct-GGUF"
        RemoteFile = "qwen2-0_5b-instruct-q4_k_m.gguf"
        LocalFile = "qwen2-0.5b-instruct-q4_k_m.gguf"
    },
    @{
        Arch = "gemma"
        Repo = "bartowski/gemma-2-2b-it-GGUF"
        RemoteFile = "gemma-2-2b-it-Q4_K_M.gguf"
        LocalFile = "gemma-2-2b-it-q4_k_m.gguf"
    },
    @{
        Arch = "mistral"
        Repo = "bartowski/Mistral-7B-Instruct-v0.3-GGUF"
        RemoteFile = "Mistral-7B-Instruct-v0.3-Q4_K_M.gguf"
        LocalFile = "mistral-7b-instruct-v0.3-q4_k_m.gguf"
    },
    @{
        Arch = "deepseek"
        Repo = "bartowski/DeepSeek-R1-Distill-Qwen-1.5B-GGUF"
        RemoteFile = "DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf"
        LocalFile = "deepseek-r1-distill-qwen-1.5b-q4_k_m.gguf"
    },
    @{
        Arch = "chatglm"
        Repo = "mradermacher/ChatGLM3-6B-GGUF"
        RemoteFile = "chatglm3-6b.Q4_K_M.gguf"
        LocalFile = "chatglm3-6b-q4_k_m.gguf"
    }
)

$TargetArch = ""
if ($args.Count -gt 0) {
    $TargetArch = $args[0]
}

if ($TargetArch) {
    $valid = $false

    foreach ($model in $Models) {
        if ($model.Arch -eq $TargetArch) {
            $valid = $true
            break
        }
    }

    if (-not $valid) {
        Write-Host "[ERROR] Unknown architecture: $TargetArch"
        Write-Host "[INFO] Supported: llama, qwen2, gemma, mistral, deepseek, chatglm"
        exit 1
    }
}

foreach ($model in $Models) {

    if ($TargetArch -and $TargetArch -ne $model.Arch) {
        continue
    }

    $url = "https://huggingface.co/$($model.Repo)/resolve/main/$($model.RemoteFile)"
    $dest = Join-Path $ModelDir $model.LocalFile

    if (Test-Path -LiteralPath $dest) {
        Write-Host "[SKIP] $($model.Arch): $($model.LocalFile)"
        continue
    }

    Write-Host "[DOWNLOAD] $($model.Arch): $($model.RemoteFile)"
    Write-Host "  URL:  $url"
    Write-Host "  File: $dest"

    try {
        Invoke-WebRequest `
            -Uri $url `
            -OutFile $dest `
            -UseBasicParsing

        $sizeMB = [math]::Round(
            (Get-Item -LiteralPath $dest).Length / 1MB,
            1
        )

        Write-Host "[DONE] $($model.Arch): $($sizeMB) MB"
    }
    catch {
        Write-Host "[ERROR] Download failed: $($model.Arch)"
        Write-Host $_.Exception.Message

        Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "=== Test model status ==="

foreach ($model in $Models) {

    $dest = Join-Path $ModelDir $model.LocalFile

    if (Test-Path -LiteralPath $dest) {

        $sizeMB = [math]::Round(
            (Get-Item -LiteralPath $dest).Length / 1MB,
            1
        )

        Write-Host "[OK]   $($model.Arch) - $sizeMB MB - $($model.LocalFile)"
    }
    else {
        Write-Host "[MISS] $($model.Arch) - $($model.LocalFile)"
    }
}

