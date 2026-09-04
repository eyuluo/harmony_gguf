# Harmony-GGUF — 35 天开发计划

> 版本：v0.4 · 关联文档：`PRD.md`（产品需求）、`mvp.md`（功能范围）、`TDD.md`（技术设计）、`prompt.md`（角色分工）
>
> 目标：35 个工作日内完成 MVP 闭环（P0）与 Serve 服务（P1），产出可安装到真机运行的离线 GGUF 大模型运行器。
>
> 团队按 `prompt.md` 三角色并行协作（A 引擎 / B 应用 / C 质量），职责标注于各任务前缀。
>
> v0.4 变更：M1 压缩至 10 天，引擎聚焦主路径（llama / qwen2）；特殊架构（deepseek / chatglm）与完整聊天模板后移至阶段 2；B 的应用开发（UI / 注册表 / 类型声明 / Service 骨架）前移至引擎移植期间并行，缩短联调周期。

## 1. 总览

| 阶段 | 天数 | 里程碑 | 目标 |
|------|------|--------|------|
| 阶段 0 准备 | Day 1–2 | — | 环境验证、源码研读、裁剪骨架、CI/测试环境搭建 |
| 阶段 1 引擎移植 | Day 3–12 | **M1** | llama.cpp CPU 主路径（llama / qwen2）在 OHOS 跑通 |
| 阶段 2 NAPI 桥接 | Day 13–18 | **M2** | ArkTS 能加载模型并流式获取 token；特殊架构补齐 |
| 阶段 3 模型+对话 | Day 19–23 | **M3** | 形成「导入→加载→对话」最小闭环 |
| 阶段 4 完善 | Day 24–28 | **M4** | 参数配置、会话历史、性能监控达标 |
| 阶段 5 Serve | Day 29–35 | **M5** | 本地 API 服务上线（OpenAI 兼容 + SSE） |

优先级映射：**P0**（阶段 1–4）+ **P1 Serve**（阶段 5）。会话历史/性能监控属 P1，为凑齐 MVP 验收提前到阶段 4 一并完成。

架构与聊天模板范围不收缩：引擎侧完整覆盖主流架构（llama / qwen2 / gemma / mistral / deepseek / chatglm 等）并内置对应聊天模板。为压缩 M1 至 10 天，特殊架构（deepseek / chatglm）与完整聊天模板后移至阶段 2 补齐，主路径（llama / qwen2）优先打通。仅「内置模型注册表」作为独立 P1 功能（FR-26~29 的条目化 JSON 资源与匹配逻辑）不纳入 35 天。

## 2. 角色与分工

| 角色 | 职责 | 覆盖里程碑 |
|------|------|-----------|
| **A — Native 引擎工程师** | llama.cpp 移植 + 编译优化 + NAPI 桥接 + HTTP Serve + 数据持久化（注册表 / 会话 RDB / 参数 Preferences） | M1/M2/M4/M5 |
| **B — 应用开发工程师** | 全部 ArkTS 代码：UI 页面 + 业务逻辑层（InferenceService/ModelManager）+ ServeController + 参数配置 UI | M1/M2/M3/M4/M5 |
| **C — 质量保障工程师** | 单元测试 + NAPI 集成测试 + Serve API 自动化测试 + 性能基线测试 + CI 流水线搭建 + 崩溃/内存监控 | 贯穿所有阶段 |

### 角色 × 阶段 矩阵

| 阶段 | A（引擎） | B（应用） | C（质量） |
|------|-----------|-----------|-----------|
| 0 准备 | 环境验证、源码研读、裁剪骨架、CMake、注册表初稿 | 项目结构、UI 骨架 | CI 流水线、测试环境、模型集准备 |
| 1 引擎 | 引擎主路径移植、注册表完善（主责） | UI 骨架、类型声明、Service 骨架（并行） | 引擎单测、冒烟测试、性能基线定义 |
| 2 桥接 | NAPI 封装、TSFN、特殊架构补齐（主责） | 类型声明定稿、Service/Session 完善 | NAPI 集成测试、回调稳定性 |
| 3 模型+对话 | 引擎联调支持、缺陷修复、注册表匹配逻辑 | UI + 业务（主责） | 端到端测试、断网验证 |
| 4 完善 | 编译优化、性能调优、会话 RDB、参数持久化 | 参数/会话/监控 UI（主责） | 性能基线测试、崩溃/内存监控 |
| 5 Serve | Serve 核心（主责） | ServeController、控制 UI | Serve API 自动化测试、整体回归 |

> 任务前缀：`[A]` 引擎、`[B]` 应用、`[C]` 质量。无前缀为共同/协商项。

---

## 3. 阶段 0：准备与环境验证（Day 1–2）

### Day 1 — 环境与上游研读
- [A] 确认 OHOS NDK（clang）可用，`hvigorw assembleHap` 构建现有模板成功（当前仅有 `add()` 示例）。
- [A] 研读 `D:\project\llama.cpp` 关键文件：`ggml/src/ggml-cpu`、`src/llama-model*.cpp`、`src/llama-arch.cpp`、`src/llama-graph.cpp`、`src/llama-context.cpp`、`src/llama-sampler.cpp`。
- [A] 确定 MVP 支持的**目标架构范围**：覆盖主流开源模型架构（llama / qwen2 / gemma / mistral / deepseek / chatglm 等），与 PRD FR-26 注册表范围对齐，不收缩；但主路径（llama / qwen2）先行。
- [B] 读 `TDD.md`，搭建 ArkTS 项目目录骨架（`ui/`、`service/`、`registry/`）。
- [C] 确认 hypium 单元测试框架可用，搭建 CI 流水线（`hvigorw assembleHap` + `codeLinter` 自动化脚本）。

### Day 2 — 裁剪骨架与 CMake 打通
- [A] 在 `entry/src/main/cpp/` 下建立目录骨架：`engine/`、`napi/`、`common/`（后续 `serve/`）。
- [A] 将 `ggml` CPU 后端与 `engine/` 源文件加入 `CMakeLists.txt`，确认可被 OHOS NDK 编译通过（不要求能跑，先编译）。
- [A] 验证 NEON 编译选项与 `pthread`、`mmap` 可用性。
- [A] 编写内置注册表 `registry/models.json` 初稿（架构→chatTemplate→defaultParams 映射）。
- [B] 搭建 UI 页面空壳（对话页 / 模型导入页 / 设置页）。
- [C] 准备多架构小型测试模型集（llama / qwen2 / gemma / mistral / deepseek / chatglm 各一个 Q4 小模型）。

**验收**：裁剪后的引擎源码能产出 `libentry.so`，无编译错误；CI 流水线可运行。

---

## 4. 阶段 1：llama.cpp 引擎移植（Day 3–12）

> 策略：只保留 CPU 后端，裁剪 CUDA/Metal/Vulkan/多模态/远程 RPC。M1 聚焦主路径（llama / qwen2，GQA + 标准 RoPE），最快打通「权重加载 → 前向 → 采样 → 解码」生成链；特殊架构（deepseek / chatglm）与完整聊天模板后移至阶段 2 补齐。B 应用开发同期并行（见阶段内并行任务）。

### Day 3–4 — ggml 核心张量与算子（A 主责）
- [A] 移植 `ggml` 张量结构、内存管理与基础算子（matmul、softmax、rmsnorm、rope 等 CPU 实现）。
- [A] 裁剪非 CPU 后端，保留 NEON 优化路径。
- [C] 为 ggml 基础算子编写单元测试（与 CPU 参考实现比对数值）。

### Day 5–6 — GGUF 解析与主路径权重加载（A 主责）
- [A] 移植 `llama-model` 的 GGUF 读取：文件头、KV 元数据、tensor infos。
- [A] 实现 `parseGgufMetadata` 底层数据（architecture、parameters、quantization、contextLength、tokenizer、fileSize）。
- [A] 移植 `llama-arch`，先注册 llama、qwen2 架构定义与权重映射，支持 Q4_K_M / Q8_0 反量化。
- [C] 构造样例 GGUF 文件，编写 GGUF 解析单测（校验各元数据字段）；llama/qwen2 加载冒烟。

### Day 7–8 — 前向推理、KV Cache 与采样（A 主责）
- [A] 移植 `llama-context` 与 `llama-graph`，组装前向计算图。
- [A] 实现 KV Cache 按 context 长度分配与复用（GQA、RoPE 标准变体）。
- [A] 移植 `llama-sampler`（temperature / top-k / top-p / repeat penalty）。
- [C] 对主路径做冒烟测试；定义性能基线指标（首字延迟 < 5s、tokens/s 目标值，参考 PRD 非功能需求）。

### Day 9 — tokenizer（A 主责）
- [A] 移植 BPE 与 SentencePiece tokenizer（`llama-vocab`）主路径。
- [A] 实现 encode/decode 与 chatml 模板基础（其余家族模板后移至阶段 2）。
- [C] tokenizer 编码/解码往返单元测试（token→id→token 一致性）。

### Day 10 — 生成循环与命令行验证（A 主责）
- [A] 实现 `generate` 底层循环：encode → 前向 → 采样 → decode → 追加 KV。
- [A] 编写一个 C++ 自测入口（非 UI），加载 llama / qwen2 小型测试模型跑通生成。
- [C] 对生成循环做内存检查（KV Cache 复用、无泄漏）。

### Day 11 — M1 验收
- [A/C] 真机/模拟器上运行 C++ 自测，确认主路径（llama / qwen2）能产出合理 token 输出。
- [A] 记录首版性能基线（首字延迟、tokens/s）。

### Day 12 — 缓冲与第二批架构冒烟
- [A] 落地第二批架构：gemma / gemma2（sliding window、logit soft-capping）、mistral（sliding window / 长上下文）。
- [A] 若第二批延误，仅顺延该批，主路径与 M1 验收不受影响。

### 阶段内并行任务（B/C，贯穿 Day 3–12）
- [A] 完善 `registry/models.json`（对齐 `ModelRegistryEntry` 字段，见 `API.md` 第 2.7 节）。
- [B] 编写/评审 `Index.d.ts` 类型声明初稿（对齐 A 的接口签名）。
- [B] 实现 `InferenceService` / `Session` 骨架（依赖类型声明，不依赖引擎可用）。
- [B] 推进 UI：模型导入页、对话页、参数设置页的静态交互。
- [C] 维护引擎单测与冒烟；预写 NAPI 集成测试用例（接口签名就绪后即可跑）。

**验收（M1）**：OHOS 环境下主路径（llama / qwen2）跑通简单前向推理，输出 token 合理、无崩溃；gemma / mistral 作为 Day 12 缓冲期补齐项。

---

## 5. 阶段 2：NAPI 桥接 + 架构补齐（Day 13–18）

### Day 13–14 — NAPI 基础封装（A 主责）
- [A] 定义并实现 `parseGgufMetadata` / `loadModel` / `unloadModel` 的 NAPI 导出。
- [A] 实现 ArkTS 与 C++ 的参数/返回值转换、错误码规范（`docs/TDD.md` 第 3 节）。
- [B] 定稿 `Index.d.ts` 类型声明，补全所有导出类型。

### Day 15–16 — 流式回调（A 主责）
- [A] 封装 `napi_threadsafe_function` 工具类（`common/`）。
- [A] 实现 `generate`（onToken / onDone / onError）与 `stopGenerate`（原子标志位）。
- [A] 推理置于独立 pthread，确认不阻塞 UI 主线程。
- [C] NAPI 集成测试：参数转换、错误码返回、回调时序；TSFN 连续多 token、停止中断稳定性测试。

### Day 17 — 特殊架构与聊天模板补齐（A 主责）
- [A] 落地第三批特殊架构：deepseek（MLA 多查询潜在注意力）、chatglm（GLM 双向掩码、rotary 变体）。
- [A] 补齐完整聊天模板：chatml / llama / qwen / gemma / chatglm 等家族模板。
- [C] 各批次架构落地后立即冒烟测试。

### Day 18 — M2 验收
- [B/C] ArkTS 侧能加载模型、发起生成并逐 token 收到回调。

**验收（M2）**：ArkTS 能加载模型并流式获取 token；停止生成可中断；主流架构覆盖完整。

---

## 6. 阶段 3：模型管理 + 对话 UI（Day 19–23）

### Day 19–20 — 模型导入与元数据（B 主责）
- [B] 文件选择器（FilePicker）导入 `.gguf`，拷贝到沙箱 `models/`。
- [B] 调用 `parseGgufMetadata` 展示元数据（架构、量化、参数量、大小）。
- [B] 模型列表、删除与存储占用展示（`ModelManager`）。
- [A] 支持 B 联调，修复引擎/桥接缺陷。

### Day 21–22 — 对话界面（B 主责）
- [B] 完成 `InferenceService` 与 `Session` 封装（`service/`）。
- [B] 对话页：多轮消息、流式打字机效果、停止生成、复制、重新生成、新建/切换会话。
- [A] 注册表匹配逻辑（architecture→chatTemplate 匹配、未命中回退通用模板）。
- [C] UI 冒烟与流程测试。

### Day 23 — M3 验收
- [B/C] 端到端跑通「导入 → 加载 → 对话」；断网验证全程离线。

**验收（M3）**：形成可用的最小闭环，满足 PRD 验收标准 1–3。

---

## 7. 阶段 4：参数配置与完善（Day 24–28）

### Day 24–25 — 参数配置（A/B 主责）
- [B] 参数设置页 UI：context length、max tokens、threads、temperature、top-k、top-p、repeat penalty。
- [A] 参数写入 Preferences（持久化），生成时生效。
- [A] 编译优化与性能调优（OpenMP/std::thread、NEON 路径确认）。

### Day 26–27 — 会话历史与性能监控（A/B 主责）
- [A] 会话持久化（RDB），提供会话 CRUD 数据层接口。
- [B] 会话列表与历史浏览 UI。
- [B] 首字延迟（TTFT）、生成速度（tokens/s）、内存占用、加载进度展示（`GenerateStats`）。
- [A] 提供 `GenerateStats` 底层统计数据支持。
- [C] 性能基线测试：首字延迟、tokens/s 实测并记录。

### Day 28 — M4 验收
- [C] 崩溃/内存监控：长对话 20 轮压力测试，检查内存泄漏与稳定性。
- [B/C] 完成 MVP 验收标准 1–5（含参数生效、断网验证）。

**验收（M4）**：达到 PRD「验收标准（MVP）」全部 5 项。

---

## 8. 阶段 5：本地 API 服务（Serve）（Day 29–35）

### Day 29–30 — Serve 核心（A 主责）
- [A] 引入 cpp-httplib，实现 `startServer` / `stopServer` / `getServerStatus`（`serve/`）。
- [A] 路由：`GET /health`、`GET /v1/models`、`POST /v1/chat/completions`、`POST /v1/completions`。
- [A] 复用推理引擎，实现单模型实例 + FIFO 请求队列。
- [B] 实现 `ServeController` 骨架与 Serve 控制 UI（启停、状态）。

### Day 31 — SSE 流式（A 主责）
- [A] `stream: true` 时输出 `text/event-stream`，逐 token `data: {...}`，结束 `data: [DONE]`。
- [C] SSE 流式响应自动化测试（逐 token 校验格式）。

### Day 32 — 鉴权与局域网（A 主责）
- [A] 可选 API Key（`Authorization: Bearer`，失败 401）。
- [A] 默认 `127.0.0.1`，局域网 `0.0.0.0` 显式开启 + 二次确认；展示访问地址。
- [C] 鉴权与并发队列测试（401、FIFO 串行）。

### Day 33–34 — 独立启动与集成联调
- [A] Serve 独立启动模式与后台保持（长时任务）、通知栏/状态栏提示。
- [B] Serve 控制 UI 联调（启停状态同步、访问地址展示、局域网开关）。
- [C] 长时运行压力测试与并发稳定性验证。

### Day 35 — M5 验收与整体回归
- [C] Serve API 自动化测试：按 PRD「验收标准（P1 / Serve）」验证 `curl` 调用（`/health`、`/v1/models`、流式补全）。
- [C] 全量回归：构建 + lint（`code-linter.json5`）+ 单测 + 真机测试。

**验收（M5）**：Serve 上线，OpenAI 兼容接口 + SSE 流式可用，局域网可访问。

---

## 9. 风险与对策

| 风险 | 影响阶段 | 对策 |
|------|----------|------|
| llama.cpp 在 OHOS NDK 编译失败 | 阶段 1 | 阶段 0 提前验证 clang+NEON+pthread；必要时裁剪特性 |
| 权重加载/算子 bug 拖慢 M1 | 阶段 1 | M1 聚焦主路径 llama/qwen2，特殊架构后移至阶段 2；尽早引入小模型冒烟自测 |
| NAPI 线程安全回调崩溃 | 阶段 2 | 封装 TSFN 工具类 + 单测覆盖；停止生成走原子标志位 |
| 移动端内存不足 | 阶段 3/4 | 限制 context 长度、推荐 Q4 量化、OOM 优雅降级 |
| Serve 并发线程竞争 | 阶段 5 | 单实例 + 请求队列串行，加锁保护推理状态 |
| 注册表匹配失败 | 阶段 3 | 未命中回退通用模板，预留手动选择接口 |
| 三角色并行接口不齐 | 阶段 2/3 | 以 `API.md` 为接口契约，A/B 在阶段 1 即并行对齐 `Index.d.ts` 与错误码 |
| 主路径延误挤压特殊架构 | 阶段 1/2 | 特殊架构已后移至阶段 2；若仍延误，优先保 llama/qwen2 + gemma/mistral 主路径，deepseek/chatglm 作为最后补齐项 |

## 10. 依赖与前置条件

- OHOS SDK 26.0.0 + DevEco Studio 环境可用。
- `D:\project\llama.cpp` 源码快照（0.3.0-dev）可访问。
- 一台 HarmonyOS NEXT 真机（或模拟器）用于真机测试。
- 至少 1 个 Q4 量化的小型 GGUF 模型用于联调（建议覆盖各架构的小模型集）。

## 11. 范围外（35 天内不做）

- 内置模型注册表条目化实现（FR-26~29 的 JSON 资源与自动匹配逻辑）——引擎侧架构与聊天模板已完整覆盖，仅注册表作为独立功能后置。
- NPU/GPU 加速、多模态、提示词模板管理、网络模型下载（P2）。
- 会话导出/分享（P1 扩展）。
