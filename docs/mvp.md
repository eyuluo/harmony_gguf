# Harmony-GGUF 运行工具 — MVP 功能规划

> 目标：在 HarmonyOS（NEXT / 原生 ArkTS）上运行本地 GGUF 大模型，实现离线推理与对话。

## 一、项目定位

- 纯本地、离线运行 GGUF 模型，数据不出设备。
- 类似 llama.cpp / Ollama 的移动端运行器，面向 HarmonyOS 6+生态。
- 采用「ArkTS UI + 原生 C/C++ 推理引擎（NAPI 桥接）」的双层架构。
- 内置本地 HTTP API 服务（Serve），提供 OpenAI 兼容接口供其他应用 / 局域网调用。

## 二、技术架构概览

| 层级 | 技术选型 | 说明 |
|------|----------|------|
| UI 层 | ArkTS + ArkUI | 对话界面、模型管理、参数设置 |
| 桥接层 | NAPI | ArkTS 与 C++ 推理引擎通信（同步/异步、流式回调） |
| 推理层 | C/C++（移植 llama.cpp） | GGUF 解析、tokenizer、采样、生成 |
| 服务层 | C/C++ HTTP Server（cpp-httplib） | OpenAI 兼容 API、SSE 流式、局域网访问 |
| 加速 | CPU 优先，后续 NPU（NNR / HiAI） | MVP 阶段先跑通 CPU 推理 |

## 三、核心功能清单

### 1. 模型管理（P0）
- [ ] GGUF 模型导入（从沙箱文件、系统文件选择器、局域网/URL 下载）
- [ ] 模型列表展示（名称、参数量、量化等级、文件大小）
- [ ] GGUF 元数据解析与展示（架构、tokenizer 类型、上下文长度等）
- [ ] 模型删除 / 存储占用管理

### 2. 推理引擎（P0）
- [ ] GGUF 文件加载与校验
- [ ] tokenizer 加载（BPE / SentencePiece 等）
- [ ] 前向推理 + KV Cache 管理
- [ ] 采样策略：temperature、top-k、top-p、repetition penalty
- [ ] 流式 token 输出（NAPI 回调到 ArkTS）

### 3. 对话界面（P0）
- [ ] 多轮对话（维护历史上下文）
- [ ] 流式打字机效果展示
- [ ] 新建/切换会话、清空上下文
- [ ] 复制 / 重新生成 / 停止生成

### 4. 推理参数配置（P0）
- [ ] 上下文长度（context length）
- [ ] 最大生成长度（max tokens）
- [ ] 采样参数（temperature、top-k、top-p、repeat penalty）
- [ ] 线程数 / CPU 核心数设置

### 5. 本地 API 服务（Serve）（P1）
- [ ] 独立启动模式：无需进入对话界面，一键启动 Serve 作为常驻服务
- [ ] 与对话推理解耦、独立生命周期，支持后台保持（长时任务 / 屏幕常亮）
- [ ] 启动 / 停止本地 HTTP 服务器（localhost，可选局域网监听）
- [ ] OpenAI 兼容接口：`POST /v1/chat/completions`、`POST /v1/completions`、`GET /v1/models`
- [ ] 流式响应（SSE / Server-Sent Events）
- [ ] 健康检查接口 `GET /health`
- [ ] 端口与监听地址配置、访问地址展示（含局域网 IP / 二维码）
- [ ] 请求队列与单模型串行调度、鉴权（可选 API Key）

### 6. 内置模型注册表（P1）
- [ ] 内置主流开源模型清单（llama / qwen / gemma / mistral / deepseek / chatglm 等）
- [ ] 每个条目：模型 id、架构、聊天模板（chat template）、推荐量化、默认采样参数
- [ ] 导入 / 下载模型时按架构自动匹配注册表，应用默认配置
- [ ] 注册表版本化，支持用户自定义 / 扩展条目

### 7. 会话与历史（P1）
- [ ] 会话持久化（本地存储，SQLite / Preferences）
- [ ] 会话列表与历史记录
- [ ] 导出 / 分享对话记录

### 8. 性能与监控（P1）
- [ ] 首字延迟、生成速度（tokens/s）统计
- [ ] 内存占用显示
- [ ] 加载进度条（模型加载耗时）

### 9. 硬件加速（P2）
- [ ] NPU / GPU 加速（NNR、HiAI、CANN）
- [ ] 量化模型适配（Q4_0、Q5_K_M、Q8_0 等）

### 10. 高级能力（P2）
- [ ] 多模态模型支持（视觉/语音）
- [ ] 提示词模板管理（ChatML、Llama、Qwen 等）
- [ ] 自定义 System Prompt
- [ ] 网络模型下载（Hugging Face 镜像等）

## 四、优先级划分

| 优先级 | 范围 | 目标 |
|--------|------|------|
| **P0（MVP 核心）** | 模型管理、推理引擎、对话界面、参数配置 | 跑通「导入 GGUF → 加载 → 流式对话」最小闭环 |
| **P1（增强）** | 会话历史、性能监控、本地 API 服务（Serve）、内置模型注册表 | 完善用户体验，可被外部程序集成 |
| **P2（进阶）** | NPU 加速、多模态、提示词模板 | 差异化能力与性能优化 |

## 五、MVP 验收标准（最小闭环）

1. 用户可导入一个 GGUF 模型文件。
2. App 能解析模型元数据并正确加载。
3. 输入文本后，模型能流式输出回答。
4. 可调节 temperature / context 等关键参数并生效。
5. 全程离线运行，无网络依赖。

## 六、关键技术风险

- **llama.cpp 移植到 HarmonyOS**：需用 OHOS NDK（clang）编译，验证 NAPI 与 pthread/NEON 支持。
- **内存限制**：移动端内存有限，需关注 KV Cache 与量化模型选择。
- **NPU 适配**：NNR / HiAI 对 Transformer 算子支持尚不完整，P0 先 CPU。
