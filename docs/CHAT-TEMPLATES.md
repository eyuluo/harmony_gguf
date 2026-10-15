# 聊天模板兼容性

> 状态同步：2026-10-15。进度见 [STATUS.md](STATUS.md)。本轮字符串模板与架构映射测试通过，真实权重家族覆盖仍待设备验收。

## 选择规则

UI 的 `formatChatPrompt` 与 Serve 共用 `EngineState::ResolvedChatTemplate` 和引擎模板解析器。优先识别 GGUF 的 `tokenizer.chat_template`；模板不存在时检查词表中的协议标记，再采用已明确的架构默认。已有模板却无法识别时返回错误，避免按模型计算架构猜测错误聊天格式。

模型架构与聊天协议并非一一对应。例如 DeepSeek 蒸馏模型可能使用 llama 或 qwen2 架构；Nemotron 不同代可能使用 Llama3 或 ChatML。缺少模板及足够词表证据的模型会明确报错，不统一套用 ChatML。

## 当前核查范围

| 家族 | 已覆盖的字符串消息协议 | 限制 |
|------|------------------------|------|
| Qwen | ChatML，Qwen3 含 last_query_index 的思考模板；Qwen2/VL、Qwen3/MoE/Next/VL、Qwen3.5 的基础 ChatML 回退 | 后续变体仍优先依据实际 GGUF 模板；不宣称完整执行任意 Jinja |
| DeepSeek | Coder 指令格式、V2、V3/R1 风格标记识别 | 蒸馏模型按实际模板处理，不按模型名称强制 V3；工具、思考模式的复杂开关未完整支持 |
| Nemotron | Llama3、ChatML；含 truncate_history_thinking 的 Nemotron3 模板独立处理历史思考和生成前缀 | 不按 nemotron 架构统一假定 Llama3；无元数据回退需词表证据 |
| Gemma | Gemma 1/2/3/3n 的旧轮次标记，Gemma4 新轮次标记与历史通道裁剪 | 多模态结构化内容仍由应用转换为 mtmd 占位符 |
| MiniMax | M2 官方 ]~b] / [e~[ 协议，ai 角色、默认系统提示与思考生成前缀 | M2 的结构化工具调用不在当前消息类型中；不假定 01/M3 与 M2 相同，需自身模板或词表标记 |
| Llama | Llama2、Llama3、Llama4 | 缺失模板时根据词表区分协议，不统一回退 Llama3 |
| GLM | ChatGLM3、ChatGLM4；带 think 标记的新版 GLM 独立处理历史回答与 observation | 默认思考生成模式，尚无完整结构化工具请求支持 |
| Mistral 等 | 保留已有 Mistral v1/v3/v7、Phi、Cohere、Granite、Hunyuan 等内置识别与渲染 | 当前不是通用 Jinja 执行器，转换模型或社区修改版本需核查真实模板 |
| Iris | 未找到名为 iris 的引擎架构或可确定的统一协议 | 需要模型完整名称或 GGUF 路径；若其底层架构已支持且模板可识别，可按实际元数据运行 |

## 验证边界

`test/harmony/test-arch-template-map.cpp` 直接调用生产模板选择与渲染函数，验证架构缺省、元数据优先、词表推断、旧协议保持、普通多轮消息及新增专用模板的精确字符串输出。`test/harmony/test-gemma4-chat.cpp` 额外覆盖 Gemma4 媒体标记。

官方格式核查参考：

- Qwen/Qwen3-0.6B 的 tokenizer_config.json。
- MiniMaxAI/MiniMax-M2 的 chat_template.jinja。
- nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B-BF16 的 chat_template.jinja。
- zai-org/GLM-4.5 的 chat_template.jinja。
- 本地 Gemma-4-E2B-Q4_K_P.gguf 的 tokenizer.chat_template。

这些验证证明字符串消息的选择和渲染行为，不等于所有家族权重已完成真机推理、完整 Jinja 或工具调用验收。现有消息契约为 role/content 字符串，不包含 tools、tool_calls、reasoning_content 等结构化字段；不应向使用方宣称这些字段已支持。
