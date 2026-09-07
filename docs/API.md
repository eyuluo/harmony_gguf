# Harmony-GGUF — NAPI 接口契约（API.md）

> 版本：v0.2 · 本文件是 ArkTS ↔ C++（NAPI）的**接口契约**，是 A/B 角色联调的权威依据。
> 对应类型声明：`entry/src/main/cpp/types/libentry/Index.d.ts`；实现：`entry/src/main/cpp/napi/`。

## 1. 概述

- NAPI 模块名：`entry`，产物 `libentry.so`。ArkTS 侧 `import napi from 'libentry.so'`。
- 生成接口为**异步流式**：推理在独立 pthread 执行，经 `napi_threadsafe_function` 逐 token 回调，不阻塞 UI。
- **单模型实例 + 多槽位并发**：同一时刻仅一个已加载模型，但可同时处理多个生成任务（并发槽位数可配置，默认 2）。

## 2. 数据结构

### 2.1 ModelMetadata（模型元数据）

| 字段 | 类型 | 说明 |
|------|------|------|
| architecture | string | 架构，如 llama / qwen2 |
| parameters | string | 参数量，如 "7B" |
| quantization | string | 量化等级，如 "Q4_K_M" |
| contextLength | number | 训练上下文长度 |
| tokenizer | string | 分词器类型（bpe / sentencepiece / wordpiece / unigram / rwkv / plamo2） |
| fileSize | number | 文件大小（字节） |

### 2.2 LoadConfig（加载参数）

| 字段 | 类型 | 默认 | 说明 |
|------|------|------|------|
| contextLength | number? | 模型默认 | 每槽位上下文长度（0 = 使用模型默认） |
| threads | number? | 默认线程数 | 推理线程数 |
| parallel | number? | 2 | 并发槽位数（同时进行的生成任务数） |

### 2.3 GenerateParams（生成参数）

| 字段 | 类型 | 默认 | 说明 |
|------|------|------|------|
| temperature | number? | 0.8 | 采样温度 |
| topK | number? | 40 | top-k 采样 |
| topP | number? | 0.95 | top-p 采样 |
| repeatPenalty | number? | 1.0 | 重复惩罚 |
| maxTokens | number? | 512 | 最大生成长度 |
| threads | number? | 0 | 线程数（0 = 默认） |

### 2.4 GenerateStats（生成统计）

| 字段 | 类型 | 说明 |
|------|------|------|
| promptTokens | number | 提示词 token 数 |
| generatedTokens | number | 生成 token 数 |
| ttftMs | number | 首字延迟（毫秒） |
| tokensPerSecond | number | 生成速度 |

### 2.5 GenerateError（生成错误）

| 字段 | 类型 | 说明 |
|------|------|------|
| code | number | 错误码（见第 3 节） |
| message | string | 错误描述 |

### 2.6 TokenData（流式 token）

| 字段 | 类型 | 说明 |
|------|------|------|
| text | string | 本次回调的 token 文本 |

### 2.7 ModelRegistryEntry（内置模型注册表条目）

| 字段 | 说明 |
|------|------|
| id | 模型唯一标识，如 "qwen2-7b" |
| architecture | GGUF 元数据中的架构名，如 "qwen2" |
| family | 模型家族，如 "qwen" |
| chatTemplate | 聊天模板（chatml / llama / qwen / gemma / ...） |
| defaultContext | 推荐上下文长度 |
| recommendedQuants | 推荐量化等级列表 |
| defaultParams | 默认采样参数（可覆盖全局设置） |

### 2.8 ServerConfig（Serve 配置）

| 字段 | 类型 | 默认 | 说明 |
|------|------|------|------|
| host | string? | "127.0.0.1" | 监听地址（0.0.0.0 为局域网） |
| port | number? | 8080 | 端口 |
| apiKey | string? | 空 | 可选鉴权 Key（空 = 不鉴权） |

### 2.9 ServerInfo（Serve 状态）

| 字段 | 类型 | 说明 |
|------|------|------|
| host | string | 监听地址 |
| port | number | 端口 |
| lanAddress | string | 局域网访问地址（空 = 未开启局域网） |
| running | boolean | 运行状态 |

## 3. 错误码

| 错误码 | 枚举 | 说明 |
|--------|------|------|
| 0 | Ok | 成功 |
| 1001 | InvalidArgument | 参数非法 |
| 1002 | ModelNotLoaded | 模型未加载 |
| 1003 | ModelLoadFailed | 模型加载失败 |
| 1004 | InferenceFailed | 推理失败 |
| 1005 | InvalidState | 状态非法（含无空闲并发槽位） |
| 1006 | OutOfMemory | 内存不足 |
| 1007 | GenerationAborted | 生成被中止 |

## 4. 接口定义

### 4.1 模型管理

| 接口 | 签名 | 返回 | 说明 |
|------|------|------|------|
| parseGgufMetadata | `(path: string) => ModelMetadata` | 元数据 | 解析 GGUF 元数据（仅读 vocab + 元数据，不加载权重） |
| loadModel | `(path: string, config?: LoadConfig) => number` | modelId | 加载模型并返回句柄（单模型实例，恒为 1）；并发槽位按 `config.parallel` 分配 |
| unloadModel | `(modelId: number) => void` | 无 | 卸载模型、释放资源（先停止所有进行中的生成） |

### 4.2 推理

| 接口 | 签名 | 返回 | 说明 |
|------|------|------|------|
| generate | `(prompt: string, params: GenerateParams, callback: GenerateCallback) => number` | requestId | 发起一次流式生成，返回 requestId 用于停止 |
| stopGenerate | `(requestId: number) => void` | 无 | 停止指定 requestId 的生成 |
| stopAllGenerations | `() => void` | 无 | 停止所有进行中的生成 |

`GenerateCallback`：`(event: 'token' | 'done' | 'error' | 'stopped', data: TokenData | GenerateStats | GenerateError) => void`

- `token`：逐 token 回调，`data` 为 `TokenData`。
- `done`：自然完成，`data` 为 `GenerateStats`。
- `stopped`：被 `stopGenerate` / `stopAllGenerations` 中止，`data` 为 `GenerateStats`。
- `error`：出错，`data` 为 `GenerateError`。

> 并发语义：`generate` 最多同时有 `LoadConfig.parallel` 个任务在执行；槽位已满时抛错（错误码 1005）。
> 每个槽位独立维护 KV cache 与采样器；达到槽位上下文上限时自动滑动上下文窗口（context shift），不截断长对话。

### 4.3 本地 API 服务（Serve）

| 接口 | 签名 | 返回 | 说明 |
|------|------|------|------|
| startServer | `(config?: ServerConfig) => void` | 无 | 启动本地 HTTP 服务器（OpenAI 兼容） |
| stopServer | `() => void` | 无 | 停止服务器 |
| getServerStatus | `() => ServerInfo` | 状态 | 获取服务器状态与访问地址 |

Serve 路由：`GET /health`、`GET /v1/models`、`POST /v1/chat/completions`、`POST /v1/completions`（支持 `stream: true` SSE）。请求经同一并发槽位池调度，超出槽位数时排队等待。
