# 阶段 2（M2）测试报告

> 更新日期：2026-09-17
>
> 角色：C（质量保障）
>
> 当前结论：**阶段 2 测试进行中，尚未完成验收**

## 1. 当前进度

M2 已完成测试代码、C++ 状态机回归、双 ABI 编译、模拟器部署、无模型契约、vocab-only 边界和 Qwen2 真实推理冒烟。当前进行到 **Qwen2 作为主模型的 NAPI 桥接分组回归准备**。

本轮已按用户要求停止测试。SmolLM2 独立冒烟及依赖它的模型切换用例延后；其他未具备权重文件的架构也未执行。M2 不得标记为完成。

| 测试层 | 状态 | 当前证据 |
|---|---|---|
| C++ EngineState | 已完成 | 11 用例、59 断言、0 失败、0 异常、0 跳过 |
| Native 构建 | 已完成 | arm64-v8a、x86_64 均完成编译和链接 |
| 无模型 NAPI 契约 | 已完成 | 7 项全部通过 |
| vocab-only 边界 | 已完成 | 元数据解析成功，推理加载按预期拒绝 |
| Qwen2 独立冒烟 | 已完成 | 1/1 通过，用时 39.723 秒 |
| NAPI 桥接完整回归 | 进行中 | 部分场景已观察通过，需隔离重跑形成有效验收结果 |
| SmolLM2 / llama 冒烟 | 延后 | 用户明确要求暂不执行 |
| 模型切换 | 延后 | 当前用例依赖 SmolLM2 |
| 其余架构冒烟 | 未开始 | 缺少对应带权重 GGUF |
| 1006 内存不足 | 未覆盖 | 缺少稳定、非破坏性的故障注入接口 |

## 2. 测试范围与实现

- `test/harmony/test-napi-bridge.cpp`：11 个纯 C++ 用例，覆盖模型生命周期、失败清理、NAPI/Serve 双池、槽位上限与复用、请求隔离、停止全部、卸载等待和重复结束保护。
- `entry/src/ohosTest/ets/test/NapiIntegration.test.ets`：设备侧 NAPI 契约、模型管理、流式回调、并发、停止、卸载和架构冒烟。
- `entry/src/ohosTest/ets/test/M2GenerationProbe.ets`：记录 token、终态、统计与错误；检查超时、重复终态和迟到回调。
- `entry/src/ohosTest/ets/test/M2Fixtures.ets`：解析测试应用沙箱中的模型路径并维护架构夹具。

停止操作以 `stopped + GenerateStats` 为成功标准。契约保留错误码 1007，但当前主动停止不通过 `error` 回调返回 1007。1006 不采用耗尽模拟器内存的破坏性方法验证。

## 3. 执行环境

| 项目 | 值 |
|---|---|
| 主机 | Windows 11，PowerShell 7+ |
| 模拟器 | DevEco Mate 60 RS |
| 系统 | HarmonyOS 6.1.0.126，API 24 |
| ABI | x86_64 |
| HDC 目标 | `127.0.0.1:5555` |
| 数据分区 | 约 5.7 GB，总可用约 4.6 GB |
| 应用 | `cn.hyshiling.Harmony_gguf`，debug |
| 安装状态 | 主 HAP、ohosTest HAP 均可 unsigned 安装 |
| 模型沙箱 | `/data/storage/el2/base/files/m2-models/` |

已部署的真实权重模型：

| 文件 | 大小 | 用途 |
|---|---:|---|
| `qwen2-0.5b-instruct-q4_k_m.gguf` | 397805248 字节 | 当前主测试模型、Qwen2 冒烟 |
| `smollm2-360m-instruct-q4_k_m.gguf` | 270590976 字节 | llama 架构测试，当前延后 |

设备中另有 vocab-only 模型，仅用于解析和拒绝推理加载测试。

## 4. 已完成的测试流程与结果

### 4.1 C++ 状态机回归

```powershell
cmd /c scripts\cpp-run-napi-bridge.bat
```

`m2-napi-bridge` 1/1 通过，用时 68.83 秒。其内部共 11 个用例、59 个断言，0 失败、0 异常、0 跳过。

该组测试曾暴露并推动修复：槽位数量未保存、重复 `EndGenerate` 导致活跃计数下溢、停止或卸载期间仍可进入新请求、`stopAll` 后无法继续生成，以及元数据文件大小错误。

### 4.2 构建与部署

```powershell
hvigorw --mode module -p product=default -p module=entry@ohosTest assembleHap --no-daemon
hdc install -r entry/build/default/outputs/ohosTest/entry-ohosTest-unsigned.hap
hdc file send -b cn.hyshiling.Harmony_gguf <本地模型> /data/storage/el2/base/files/m2-models/<模型文件名>
```

ohosTest HAP 编译和安装已成功，x86_64 Native 库随包安装成功。测试夹具会创建 `filesDir/m2-models/`；该模拟器不支持 HDC root 且无 `run-as`，因此模型必须使用 `hdc file send -b` 写入应用沙箱。

### 4.3 设备基线

```powershell
hdc shell aa test -b cn.hyshiling.Harmony_gguf -m entry_test `
  -s unittest OpenHarmonyTestRunner -s class M2NoModel -s timeout 180000
```

- 无模型 NAPI 契约 7 项全部通过。
- 空路径、文件不存在、未加载生成、重复卸载、未知请求停止和非法标识参数均符合预期。
- vocab-only 模型的元数据解析通过，作为真实推理模型加载时按预期拒绝。

### 4.4 Qwen2 独立冒烟

```powershell
hdc shell aa test -b cn.hyshiling.Harmony_gguf -m entry_test `
  -s unittest OpenHarmonyTestRunner -s class M2ArchQwen2 -s timeout 180000
```

结果为 1/1 通过，用时 39.723 秒。已验证元数据架构为 `qwen2`、模型可加载、ChatML prompt 可执行，并完成 4-token 生成。

### 4.5 尚不能作为最终验收的观察结果

一次完整套件运行中曾观察到以下场景通过：加载后卸载再生成返回 1002；非法参数后仍可生成；单槽满载返回 1005；收到 token 后按 requestId 停止并仅收到一次 `stopped`；`stopAll` 后可再次生成；生成期间卸载后可重新加载。

该轮后半段受到用例超时和残留请求污染，因此这些结果仅用于定位与规划，必须在拆分套件后隔离重跑，不能计入最终通过数。

## 5. 已确认缺陷与风险

### 5.1 `loadModel` 同步阻塞主线程

完整运行加载 Qwen2 时，系统报告 `THREAD_BLOCK_6S`：

```text
Reason: THREAD_BLOCK_6S
App main thread is not response
```

主线程调用栈位于 `llama_vocab::impl::load`、`llama_model_load_from_file`、`EngineState::LoadModel` 和 NAPI `LoadModel`。当时应用 RSS 约 211488 KB，系统 Free 约 1.46 GB、Available 约 2.6 GB，没有 OOM 证据。判定为同步加载阻塞主线程的正式缺陷；原始日志已在提取上述关键证据后清理。

### 5.2 模拟器性能与测试隔离

模拟器 CPU 推理较慢，较长生成可能超过探针 60 秒。套件超时后，残留请求会污染后续用例。后续必须按 suite 分组执行，每组控制重模型加载次数，并在失败后确认进程退出再继续。

### 5.3 SmolLM2 元数据兼容

SmolLM2 的 `general.architecture` 可识别为 `llama`，但当前解析结果中 `contextLength === 0`，而文件包含 `llama.context_length`。该问题随 SmolLM2 独立冒烟一并延后，不在本轮继续诊断。

## 6. 恢复测试后的执行计划

1. 先编译并安装当前 ohosTest HAP，确认 Qwen2 已成为桥接测试主模型；SmolLM2 和模型切换用例保持跳过。
2. 单独运行 `M2Bridge`。若仍因连续同步加载触发 appfreeze，则把桥接用例继续拆成每组 2 至 3 个重模型场景。
3. 优先补齐流式终态、槽位复用、超长输入 1004、并发隔离、requestId 停止、`stopAll` 恢复和卸载恢复的隔离证据。
4. 不运行 `M2ArchLlama`，直到用户恢复 SmolLM2 测试。
5. 获取模型后逐个执行 Gemma2、Mistral、DeepSeek 蒸馏、DeepSeek 原生 MLA 和 ChatGLM；受模拟器空间限制，应逐个部署、测试和清理。
6. 修复或评审同步 `loadModel` 主线程阻塞问题后，重复相关加载场景并保存 appfreeze 对照日志。
7. 全部必需项隔离通过后，再更新 `docs/TEST-PLAN.md` 并判定 M2 是否达到验收门槛。

## 7. 模型矩阵与覆盖边界

| Suite | 文件 | 期望架构 | 状态 |
|---|---|---|---|
| `M2ArchLlama` | `smollm2-360m-instruct-q4_k_m.gguf` | llama | 延后 |
| `M2ArchQwen2` | `qwen2-0.5b-instruct-q4_k_m.gguf` | qwen2 | 已通过 |
| `M2ArchGemma2` | `gemma-2-2b-it-q4_k_m.gguf` | gemma2 | 缺模型 |
| `M2ArchMistral` | `mistral-7b-instruct-v0.3-q4_k_m.gguf` | llama | 缺模型 |
| `M2ArchDeepSeekDistill` | `deepseek-r1-distill-qwen-1.5b-q4_k_m.gguf` | qwen2 | 缺模型 |
| `M2ArchDeepSeekMla` | `deepseek2-mla-q4_k_m.gguf` | deepseek2 | 缺模型 |
| `M2ArchChatGlm` | `chatglm3-6b-q4_k_m.gguf` | chatglm | 缺模型 |

DeepSeek 蒸馏模型不能证明原生 MLA 覆盖。固定家族 prompt 冒烟只证明模型能加载和生成，不等于完整验证聊天模板渲染器或回答质量。

## 8. 验收判定

阶段 2 当前为 **部分通过、继续执行中**。已完成 C++ 层和基础设备契约，Qwen2 真实推理链路已打通；NAPI 桥接完整回归、SmolLM2/模型切换及其余架构尚未完成。同步 `loadModel` 主线程阻塞属于阶段风险，在关闭或接受该缺陷前不得把 M2 标记为完整通过。
