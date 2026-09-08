# Harmony-GGUF — TDD（技术设计文档）

> 版本：v0.1 · 关联文档：`mvp.md`（功能范围）、`PRD.md`（产品需求）

## 1. 总体架构

采用「ArkTS UI + NAPI 桥接 + C/C++ 推理引擎」三层架构：

```
┌─────────────────────────────────────────────┐
│  UI 层（ArkTS / ArkUI）                       │
│  对话页 · 模型管理页 · 参数设置页 · 会话列表    │
├─────────────────────────────────────────────┤
│  服务层（ArkTS）                               │
│  InferenceService · ModelManager · Session    │
├─────────────────────────────────────────────┤
│  桥接层（NAPI / C++）                          │
│  inference_napi.cpp · 流式回调                │
├─────────────────────────────────────────────┤
│  推理引擎（C/C++，移植 llama.cpp）             │
│  GGUF 解析 · tokenizer · 采样 · KV Cache       │
├─────────────────────────────────────────────┤
│  Serve 服务层（C/C++，cpp-httplib）           │
│  HTTP 路由 · OpenAI 兼容 API · SSE 流式       │
└─────────────────────────────────────────────┘
```

## 2. 模块划分

| 模块 | 语言 | 职责 |
|------|------|------|
| `ui/` | ArkTS | 页面与组件（对话、模型、设置） |
| `service/` | ArkTS | 业务逻辑封装，状态管理 |
| `napi/` | C++ | NAPI 接口实现，线程管理与回调 |
| `engine/` | C++ | 推理引擎（GGUF、tokenizer、采样、生成） |
| `serve/` | C++ | HTTP 服务器、OpenAI 兼容路由、SSE 流式 |
| `registry/` | ArkTS / 资源 | 内置模型注册表、架构识别与模板匹配 |
| `common/` | C++ | 日志、工具、内存池 |

## 3. NAPI 接口设计

### 3.1 模型管理
| 接口 | 入参 | 返回 | 说明 |
|------|------|------|------|
| parseGgufMetadata | 模型文件路径 | ModelMetadata | 解析 GGUF 元数据 |
| loadModel | 文件路径、加载参数 | modelId 句柄 | 加载模型并返回句柄 |
| unloadModel | modelId | 无 | 卸载模型、释放资源 |

### 3.2 推理
| 接口 | 说明 |
|------|------|
| generate | 流式生成：以回调方式逐 token 返回，完成 / 出错时通过回调通知（onToken / onDone / onError）；返回 requestId 用于停止 |
| stopGenerate | 停止指定 requestId 的生成 |
| stopAllGenerations | 停止所有进行中的生成 |

### 3.3 关键数据结构（字段说明）

| 结构 | 字段 | 说明 |
|------|------|------|
| LoadConfig | contextLength | 每槽位上下文长度（0 = 使用模型默认） |
| | threads | 推理线程数 |
| | parallel | 每个槽位池（NAPI / Serve）的槽位数，默认 2（总序列数 = 2 × parallel） |
| ModelMetadata | architecture | 架构，如 llama / qwen |
| | parameters | 参数量，如 "7B" |
| | quantization | 量化等级，如 "Q4_K_M" |
| | contextLength | 上下文长度 |
| | tokenizer | 分词器类型（BPE / SentencePiece） |
| | fileSize | 文件大小 |
| GenerateParams | temperature | 采样温度 |
| | topK | top-k 采样 |
| | topP | top-p 采样 |
| | repeatPenalty | 重复惩罚 |
| | maxTokens | 最大生成长度 |
| | threads | 线程数 |
| GenerateStats | promptTokens | 提示词 token 数 |
| | generatedTokens | 生成 token 数 |
| | ttftMs | 首字延迟（毫秒） |
| | tokensPerSecond | 生成速度 |
| ModelRegistryEntry | id | 模型唯一标识，如 "qwen2-7b" |
| | architecture | 架构名，如 "qwen2" |
| | family | 模型家族，如 "qwen" |
| | chatTemplate | 聊天模板，如 "qwen" |
| | defaultContext | 推荐上下文长度 |
| | recommendedQuants | 推荐量化等级列表 |
| | defaultParams | 默认采样参数（可覆盖全局设置） |

### 3.4 本地 API 服务（Serve）
| 接口 | 说明 |
|------|------|
| startServer | 启动本地 HTTP 服务器，传入 ServerConfig |
| stopServer | 停止服务器 |
| getServerStatus | 获取服务器状态与访问地址 |

| 结构 | 字段 | 说明 |
|------|------|------|
| ServerConfig | host | 监听地址（127.0.0.1 或 0.0.0.0） |
| | port | 端口 |
| | apiKey | 可选鉴权 Key |
| ServerInfo | host | 监听地址 |
| | port | 端口 |
| | lanAddress | 局域网访问地址 |
| | running | 运行状态 |

## 4. 线程模型

- **主线程（ArkTS）**：仅负责 UI 渲染与状态更新。
- **推理线程（C++，每个生成任务一个独立 pthread）**：执行模型推理，避免阻塞 UI。
- **回调机制**：NAPI `napi_threadsafe_function` 将 token 从推理线程安全回调到 JS 线程。
- **多槽位并发**：单模型实例可同时处理多个生成任务，槽位按来源分为两个独立池——NAPI 直接调用与 Serve HTTP 服务各 `LoadConfig.parallel` 个（默认各 2，互不抢占）；每个任务独占一个 KV cache 序列槽位（seq_id）与独立采样器；`llama_decode` 非线程安全，用互斥锁保护，请求间交错执行。

```
ArkTS UI ──NAPI调用──►  C++ 推理线程 ──线程安全函数──►  JS 回调(逐 token)
                              │
             stopGenerate(requestId) ◄──────────── 用户点击停止
             stopAllGenerations()  ◄──────────── 停止全部
```

## 5. 数据流

### 5.1 模型导入流程
```
文件选择器(FilePicker) → 拷贝到沙箱 models/ 目录
  → parseGgufMetadata() 读取 GGUF 元数据（含架构）
  → 按架构匹配内置注册表 → 应用默认 chat template / 参数
  → 写入本地模型索引(Preferences/RDB)
  → 展示模型列表
```

### 5.2 推理流程
```
用户输入 → 组装 prompt（含历史与模板）
  → generate() 进入 C++
  → tokenizer 编码 → 前向推理 → 采样 → 解码 token
  → 逐 token 回调 ArkTS → 渲染
  → 结束/停止 → 回调 stats
```

### 5.3 Serve 请求流程
```
外部客户端(HTTP) → cpp-httplib 路由 → 鉴权校验
  → 分配并发槽位（满则排队等待） → 推理引擎生成
  → SSE 逐 token 返回 data: {...}
  → 结束 → data: [DONE] → 关闭连接
```

## 6. 数据存储设计

| 数据 | 存储方式 | 说明 |
|------|----------|------|
| GGUF 文件 | 沙箱 `models/` 目录 | 原始模型文件 |
| 模型索引 | Preferences / 关系型数据库 | 元数据缓存 |
| 会话记录 | 关系型数据库（RDB） | 消息、会话元数据 |
| 模型注册表 | 内置 JSON 资源 + 用户覆盖配置 | 模型默认模板与参数 |
| 应用设置 | Preferences | 参数默认值 |

## 7. 内置模型注册表设计

### 7.1 概述
内置一张 JSON 资源表（`registry/models.json`），收录主流开源模型的架构、聊天模板与默认参数。加载 / 导入模型时按架构字段自动匹配，免配置套用正确模板。

### 7.2 条目字段
| 字段 | 说明 |
|------|------|
| id | 模型唯一标识，如 `qwen2-7b` |
| architecture | GGUF 元数据中的架构名，如 `qwen2` |
| family | 模型家族，如 `qwen` |
| chatTemplate | 对应聊天模板（chatml / llama / qwen / ...） |
| defaultContext | 推荐上下文长度 |
| recommendedQuants | 推荐量化等级列表 |
| defaultParams | 默认采样参数（可覆盖全局设置） |

### 7.3 匹配流程
```
加载模型 → 读取 GGUF metadata.architecture
  → 在注册表中查找 architecture
  → 命中：套用 chatTemplate + defaultParams
  → 未命中：回退到通用模板（如 chatml），允许用户手动选择
```

### 7.4 版本与扩展
- 注册表随应用版本内置，支持联网 / 离线更新。
- 用户可新增 / 覆盖自定义条目（存储于本地 RDB，优先级高于内置表）。

## 8. 关键流程时序

```
用户点击发送
  → UI 追加用户消息
  → InferenceService.generate(...)
  → NAPI 调用（异步）
  → 推理线程开始生成
  → 逐 token 回调 → UI 流式更新
  → 生成完成 → 保存会话 → 更新 stats 展示
```

## 9. Serve 服务设计

### 9.1 架构
Serve 复用推理引擎，通过 cpp-httplib 暴露 HTTP 接口；运行于独立线程，与 UI 推理共用同一已加载模型（单模型实例 + 多槽位并发）。

Serve 支持独立启动模式：可作为常驻服务单独运行，无需进入对话界面；生命周期与 UI 解耦，由专门的 ServeController 管理。

### 9.2 路由（OpenAI 兼容）
| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/health` | 健康检查 |
| GET | `/v1/models` | 模型列表 |
| GET | `/v1/models/{id}` | 模型详情 |
| POST | `/v1/chat/completions` | 聊天补全（支持流式 `stream: true`） |
| POST | `/v1/completions` | 文本补全 |

### 9.3 流式响应（SSE）
`stream: true` 时返回 `Content-Type: text/event-stream`，逐 token 输出 `data: {...}\n\n`，结束发送 `data: [DONE]`。

### 9.4 请求调度
- 单模型实例 + 多槽位并发：同时处理多个生成任务，槽位分为 NAPI 池与 Serve 池，各 `LoadConfig.parallel` 个（默认各 2，互不抢占）；任务独占一个 KV cache 序列槽位（seq_id）。
- 满负载：Serve 请求超出 Serve 池槽位数时排队等待空闲槽位。
- 停止：`stopGenerate(requestId)` 按请求停止，`stopAllGenerations()` 停止全部；长对话达到槽位上下文上限时自动滑动上下文窗口（context shift）。
- 鉴权：配置 API Key 时校验 `Authorization: Bearer <key>`。

### 9.5 安全
- 默认监听 `127.0.0.1`；用户显式开启后监听 `0.0.0.0` 供局域网访问。
- 局域网模式默认关闭，需在 UI 中二次确认并展示访问地址。

### 9.6 生命周期与后台运行
- Serve 由独立 ServeController 管理，可脱离 UI 单独启动 / 停止。
- 应用启动时可选择进入「对话模式」或「Serve 服务模式」。
- 后台保持：前台运行时保持服务；退后台需申请长时任务（Long-running task）或屏幕常亮，避免被系统挂起。
- 服务状态常驻提示（通知栏 / 状态栏），可随时一键停止。

## 10. 性能设计

- **内存**：KV Cache 按 context 长度分配；小内存设备推荐 Q4 量化。
- **加载优化**：模型加载置于后台线程，展示进度；支持 mmap。
- **采样**：CPU 多线程（OpenMP / std::thread），线程数可配置。
- **NPU 预留**：引擎层抽象后端接口（CPU / NPU），后续接入 NNR。

## 11. 技术风险与对策

| 风险 | 影响 | 对策 |
|------|------|------|
| llama.cpp 在 OHOS NDK 编译失败 | 阻断开发 | 提前验证 clang + NEON + pthread；必要时裁剪特性 |
| NAPI 线程安全回调复杂 | 崩溃风险 | 封装 `napi_threadsafe_function` 工具类并单测 |
| 移动端内存不足 | 加载/推理失败 | 限制 context 长度、推荐量化模型、OOM 优雅降级 |
| NPU 算子支持不全 | 加速受限 | P0 仅 CPU，NPU 作为 P2 独立后端 |
| Serve 并发访问导致线程竞争 | 崩溃 / 结果错乱 | 单实例 + 多槽位并发，每个槽位独立 KV cache 序列与采样器；`llama_decode` 加锁保护推理状态 |

## 12. 里程碑（MVP）

1. **M1**：llama.cpp 编译产物可在 OHOS 环境跑通简单前向推理。
2. **M2**：NAPI 桥接完成，ArkTS 能加载模型并流式获取 token。
3. **M3**：模型管理 + 对话 UI 完成，形成可用的最小闭环。
4. **M4**：参数配置、会话历史、性能监控补齐，达到 MVP 验收标准。
5. **M5**：本地 API 服务（Serve）上线，支持 OpenAI 兼容接口与局域网访问。
