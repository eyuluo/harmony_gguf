# Harmony-GGUF — 项目级 Agent 指南（AGENTS.md）

本文件为在本仓库工作的 AI 代理提供项目背景、命令与约定。开始任何任务前，先阅读 `docs/` 下相关文档。

## 1. 项目概述

面向 HarmonyOS（NEXT / 原生 ArkTS）的**纯本地、离线 GGUF 大模型运行器**。数据不出设备，类似移动端 llama.cpp / Ollama。三层架构：

```
ArkTS UI（ArkUI） → 服务层（ArkTS） → NAPI 桥接（C++） → 推理引擎（C++，移植 llama.cpp，仅 CPU）
                                                        → Serve 服务（C++，cpp-httplib，OpenAI 兼容）
```

- NAPI 模块名：`entry`，产物 `libentry.so`（ArkTS 侧 `import napi from 'libentry.so'`）。
- MVP 仅 CPU 推理；NPU/GPU 属 P2。架构范围不收缩（llama / qwen2 / gemma / mistral / deepseek / chatglm 等）。

## 2. 环境与工具链

- 操作系统：Windows 11，Shell：PowerShell 7+。
- DevEco Studio，HarmonyOS SDK 26.0.0（API 12+），OHOS NDK（clang），native 编译器为 BiSheng。
- 上游源码：`D:\project\llama.cpp`（0.3.0-dev，**非 git 仓库**）。

## 3. 命令

```powershell
# 构建 HAP
hvigorw assembleHap --mode module -p product=default

# 单元测试（ArkTS，@ohos/hypium）
hvigorw test

# 代码检查（ArkTS，规则见 code-linter.json5）
hvigorw codeLinter
```

> 注意：本仓库无 `hvigorw` 可执行脚本时，需通过 DevEco Studio 内置功能或系统已安装的 hvigor 命令执行。构建/测试前若不确定，先确认命令是否可用。

## 4. 目录结构

```
Harmony_gguf/
├── docs/            # 设计文档（见 §5）
├── entry/           # 主模块（hap）
│   └── src/main/
│       ├── ets/     # ArkTS 代码（entryability、pages）
│       ├── cpp/     # C++（napi_init.cpp、CMakeLists.txt、types/libentry/）
│       └── resources/
├── test/            # C++ 测试（移植自 llama.cpp，testing.h 框架）
│   ├── testing.h
│   ├── test-*.cpp   # gguf / tokenizer / sampling / rope / quantize / archs / chat-template / jinja / opt
│   └── models/      # vocab 测试数据（ggml-vocab-*.gguf + .inp/.out）
├── AppScope/        # 应用级配置
├── build-profile.json5
└── oh-package.json5
```

业务代码最终按 `docs/TDD.md` 组织：
- ArkTS：`ui/`、`service/`、`registry/`
- C++：`napi/`、`engine/`、`serve/`、`common/`

## 5. 文档导航

| 文档 | 用途 |
|------|------|
| `docs/PRD.md` | 产品需求（用户故事、功能/非功能需求、验收标准） |
| `docs/mvp.md` | 功能范围与优先级（P0/P1/P2） |
| `docs/TDD.md` | 技术设计（架构、NAPI 接口、数据流、线程模型、Serve） |
| `docs/PLAN-35DAY.md` | 35 天开发计划（阶段 0–5、里程碑 M1–M5、三角色分工） |

## 6. 开发约定

- **语言**：所有输出（代码注释、文档、回复）使用简体中文；专业术语可保留英文。
- **注释**：默认不写注释，除非用户明确要求。
- **代码风格**：遵循现有代码与 DevEco 模板；ArkTS 通过 `code-linter.json5` 校验（性能 + typescript-eslint + 安全规则）。
- **错误码**：NAPI 统一使用 `docs/API.md` 第 3 节的 0 / 1001–1007 规范。

## 7. 关键约束（务必遵守）

1. **禁止整体拷贝上游源码**：`D:\project\llama.cpp` 仅按 `docs/PORTING.md` 清单**按需移植**所需文件，不整目录复制。
2. **只保留 CPU 后端**：裁剪 CUDA/Metal/Vulkan/OpenCL/SYCL/CANN/RPC 等所有非 CPU 后端与非 ARM 架构代码。
3. **架构范围不收缩**：引擎需覆盖 llama / qwen2 / gemma / mistral / deepseek / chatglm 等主流架构及其聊天模板。
4. **单模型实例**：同一时刻仅一个已加载模型；切换即卸载旧模型。
5. **流式与线程安全**：生成经 `napi_threadsafe_function` 逐 token 回调，推理置于独立 pthread，不阻塞 UI；停止走原子标志位。
6. **隐私与安全**：全程离线；Serve 默认仅监听 `127.0.0.1`，局域网与鉴权需显式开启。
7. **测试双轨**：ArkTS 侧用 `@ohos/hypium`（`entry/src/test`）；C++ 侧用 `test/` 下 `testing.h` 框架（用于 M1 本地/真机 shell 验证）。

## 8. 角色分工（见 prompt.md）

- **A — Native 引擎工程师**：llama.cpp 移植、编译优化、NAPI 桥接、HTTP Serve（M5）。
- **B — 应用开发工程师**：全部 ArkTS 代码（UI、InferenceService/ModelManager/注册表/会话存储、ServeController、参数配置）。
- **C — 质量保障工程师**：单元/集成/API 自动化测试、性能基线、CI、崩溃与内存监控（贯穿全程）。
