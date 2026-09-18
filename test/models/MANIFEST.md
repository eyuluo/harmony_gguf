# 测试模型集清单

> 角色 C（质量保障）维护 · 阶段 0 交付物
> 用途：为引擎移植、NAPI 集成、端到端测试提供多架构小型 Q4 测试模型

## 1. 目标

覆盖 PRD FR-26 要求的 6 大主流架构，每个架构准备一个 Q4 量化的小型 GGUF 模型，
用于冒烟测试、集成测试与性能基线测量。

## 2. 模型清单

| 架构 | 模型名称 | 量化 | 大小(约) | 用途 | 状态 |
|------|----------|------|----------|------|------|
| llama | TinyLlama-1.1B-Chat-v1.0 | Q4_K_M | ~640 MB | 主路径冒烟、M1 验收 | 待获取 |
| qwen2 | Qwen2-0.5B-Instruct | Q4_K_M | ~400 MB | 主路径冒烟、M1 验收 | 待获取 |
| gemma | gemma-2-2b-it | Q4_K_M | ~1.6 GB | 第二批架构冒烟 | 待获取 |
| mistral | Mistral-7B-Instruct-v0.3 | Q4_K_M | ~4.4 GB | 第二批架构冒烟 | 待获取 |
| deepseek | DeepSeek-R1-Distill-Qwen-1.5B | Q4_K_M | ~1.0 GB | 特殊架构补齐（阶段2） | 待获取 |
| chatglm | chatglm3-6b | Q4_K_M | ~3.5 GB | 特殊架构补齐（阶段2） | 待获取 |

M2 原生 MLA 验证需另备 `deepseek2-mla-q4_k_m.gguf`，其 GGUF `general.architecture` 必须为 `deepseek2`，且包含真实权重。以上 DeepSeek-R1-Distill-Qwen 只覆盖 qwen2 蒸馏路线，不能证明原生 DeepSeek MLA 已覆盖。该额外模型尚无自动下载项，部署和设备用例见 `reports/test-report-M2.md`。

## 3. 获取方式

运行获取脚本自动下载（需网络，下载到 `test/models/inference/`）：

```bash
bash scripts/fetch-test-models.sh
```

或手动从 Hugging Face 下载 `.gguf` 文件，放入 `test/models/inference/` 目录。

## 4. 目录结构

```
test/models/
├── MANIFEST.md              # 本文件
├── inference/               # 推理测试模型（Q4 量化，较大）
│   ├── tinyllama-1.1b-chat-q4_k_m.gguf
│   ├── qwen2-0.5b-instruct-q4_k_m.gguf
│   ├── gemma-2-2b-it-q4_k_m.gguf
│   ├── mistral-7b-instruct-v0.3-q4_k_m.gguf
│   ├── deepseek-r1-distill-qwen-1.5b-q4_k_m.gguf
│   └── chatglm3-6b-q4_k_m.gguf
├── ggml-vocab-*.gguf        # tokenizer 往返测试数据（已有）
├── ggml-vocab-*.gguf.inp    # 编码输入
└── ggml-vocab-*.gguf.out    # 期望输出
```

## 5. 使用场景

| 阶段 | 测试类型 | 使用模型 |
|------|----------|----------|
| 阶段 1 (M1) | 引擎冒烟 | llama + qwen2 |
| 阶段 1 (Day12) | 第二批冒烟 | gemma + mistral |
| 阶段 2 (M2) | NAPI 集成 | llama + qwen2 |
| 阶段 2 | 特殊架构补齐 | deepseek + chatglm |
| 阶段 3 (M3) | 端到端 | llama + qwen2 |
| 阶段 4 (M4) | 性能基线 | llama（主基准） |
| 阶段 4 | 崩溃/内存压测 | llama（长对话 20 轮） |
| 阶段 5 (M5) | Serve API | llama + qwen2 |

## 6. 注意事项

- 模型文件较大，**不纳入版本控制**（已在 `.gitignore` 排除 `*.gguf` 中大于 vocab 的文件）
- `test/models/inference/` 目录通过 `.gitkeep` 保留结构
- 真机测试时通过 `hdc file send` 推送模型到设备
- 性能基线以 llama Q4_K_M 为基准（参考 PRD：首字延迟 < 5s）
