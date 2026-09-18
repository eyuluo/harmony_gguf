# Harmony-GGUF

#项目开发中，预计9月开发完毕

面向 HarmonyOS（NEXT / 原生 ArkTS）的本地 GGUF 大模型运行器。纯离线运行，数据不出设备，让鸿蒙设备像运行聊天应用一样在本机运行开源大模型。

## 特性

- **纯本地离线**：GGUF 模型导入、解析、加载、推理全程本地，除用户主动下载模型外无任何网络请求。
- **流式对话**：逐 token 流式输出，打字机效果，支持多轮上下文和停止/复制/重新生成。
- **模型管理**：导入 `.gguf` 文件，解析并展示元数据（架构、参数量、量化等级、上下文长度、tokenizer）。
- **参数可调**：temperature、top-k、top-p、repeat penalty、context length、max tokens、线程数。
- **本地 API 服务（Serve，P1）**：OpenAI 兼容接口（`/v1/chat/completions`、`/v1/completions`、`/v1/models`），支持 SSE 流式、局域网访问与可选鉴权。
- **内置模型注册表（P1）**：自动识别架构并套用聊天模板与默认参数。

## 技术架构

「ArkTS UI + NAPI 桥接 + C/C++ 推理引擎」三层架构：

| 层级 | 技术 | 职责 |
|------|------|------|
| UI 层 | ArkTS + ArkUI | 对话页、模型管理页、参数设置页、会话列表 |
| 服务层 | ArkTS | InferenceService · ModelManager · Session |
| 桥接层 | NAPI | 推理接口封装、`napi_threadsafe_function` 流式回调 |
| 推理引擎 | C/C++（移植 llama.cpp） | GGUF 解析、tokenizer、采样、KV Cache |
| Serve 服务 | C/C++（cpp-httplib） | HTTP 路由、OpenAI 兼容 API、SSE 流式 |

MVP 阶段仅 CPU 推理；NPU/GPU 加速属于 P2。

## 目录结构

```
Harmony_gguf/
├── AppScope/            # 应用级配置（app.json5、资源）
├── entry/               # 主模块（hap）
│   └── src/main/
│       ├── ets/         # ArkTS 代码（entryability、pages）
│       ├── cpp/         # C++ 代码（napi_init.cpp、CMakeLists.txt、types/）
│       └── resources/   # 资源文件
├── hvigor/              # hvigor 构建配置
├── docs/                # PRD / MVP / TDD 设计文档
├── build-profile.json5  # 构建配置（SDK 26.0.0，HarmonyOS）
└── oh-package.json5     # 依赖声明
```

业务代码最终按 `docs/TDD.md` 组织为 `ui/`、`service/`、`registry/`（ArkTS）与 `napi/`、`engine/`、`serve/`、`common/`（C++）。

## 快速开始

### 环境要求

- DevEco Studio（HarmonyOS SDK 26.0.0，API 12+）
- OHOS NDK（clang）用于 native 编译

### 构建

使用 DevEco Studio 打开工程根目录，执行 `Build → Build Hap(s)/App(s)`。

构建只会生成 HAP，不会自动显示应用界面。需要查看和使用 UI 时，请启动模拟器、选择 `entry` 模块并点击 DevEco Studio 顶部的 Run。完整的新成员操作流程见 [UI 运行与使用说明](docs/RUN-AND-USE.md)。

命令行构建（需已安装 hvigor 命令）：

```bash
hvigorw assembleHap --mode module -p product=default
```

### 测试

- 单元测试（`entry/src/test`）基于 `@ohos/hypium`，通过 DevEco Studio 运行。
- 设备测试（`entry/src/ohosTest`）需连接真机/模拟器。

## 文档

| 文档                                         | 说明 |
|--------------------------------------------|------|
| [docs/PRD.md](docs/PRD.md)                 | 产品需求文档 |
| [docs/mvp.md](docs/mvp.md)                 | 功能范围与优先级 |
| [docs/TDD.md](docs/TDD.md)                 | 技术设计（架构、NAPI 接口、数据流、线程模型） |
| [docs/RUN-AND-USE.md](docs/RUN-AND-USE.md) | UI 构建、模拟器运行、模型导入与常见问题 |
