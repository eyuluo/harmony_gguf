# M2 测试运行说明

## 范围与入口

- `test/harmony/test-napi-bridge.cpp`：11 个纯 C++ 用例，验证模型生命周期、槽位池、请求隔离、停止、卸载等待、重复结束保护和异步失败清理。使用已有 vocab 模型，不证明真实推理或 TSFN 行为。
- `entry/src/ohosTest/ets/test/NapiIntegration.test.ets`：20 个设备用例（7 个无模型接口用例、6 个桥接用例、7 个架构冒烟用例）。通过设备测试 `List.test.ets` 注册，直接调用 `libentry.so`。
- `M2GenerationProbe.ets`：记录事件、请求编号、统计和错误；60 秒终态超时，终态后观察 100 ms，检查重复终态与迟到回调。停止调用后允许已经排队的 token，收到终态后不允许事件。
- 本地 `entry/src/test/List.test.ets` 仅注册本地单测。空的 Native mock 映射已移除，避免设备集成测试误用空对象。

## 本地 C++ 测试

在仓库根目录使用 PowerShell：

```powershell
cmd /c scripts\cpp-run-napi-bridge.bat > reports/m2-cpp-test.log 2>&1
$LASTEXITCODE
```

脚本在 vcvars64 环境中使用 Ninja 与显式 cl 配置、构建，然后运行 CTest。退出码非零代表构建失败、断言失败或超时；CTest 为整个进程设置 120 秒超时，不留下引用局部变量的脱离线程。模型路径相对 `test/`，CTest 自动设置工作目录。不要直接使用旧的 `cpp-build-env.bat`（它会删除 build 目录）。

Linux CI 的 `scripts/ci-cpp-test.sh` 在原有 M1 测试后构建并运行 M2 CTest，失败会阻断 CI。

## 设备测试前置条件

1. 连接 HarmonyOS NEXT 真机或兼容模拟器，配置 DevEco 签名并安装应用与测试 HAP。
2. 将模型部署到测试应用上下文的 `filesDir/m2-models/`。用例找不到文件会明确失败，不会默认为通过。实际沙箱路径由 `abilityDelegatorRegistry` 获取。
3. 在开发设备允许访问应用数据目录时，可使用以下示例。用户 ID 非 0 时调整实际路径；普通设备若无法访问该目录，应通过 DevEco 沙箱文件工具部署。

```powershell
hdc shell mkdir -p /data/app/el2/0/base/cn.hyshiling.Harmony_gguf/files/m2-models
hdc file send test/models/inference/tinyllama-1.1b-chat-q4_k_m.gguf /data/app/el2/0/base/cn.hyshiling.Harmony_gguf/files/m2-models/tinyllama-1.1b-chat-q4_k_m.gguf
hdc file send test/models/ggml-vocab-llama-bpe.gguf /data/app/el2/0/base/cn.hyshiling.Harmony_gguf/files/m2-models/ggml-vocab-llama-bpe.gguf
```

基础桥接测试还需 `qwen2-0.5b-instruct-q4_k_m.gguf`（模型切换）。其他架构文件名见 `M2Fixtures.ets`，全部用例需要完整模型集。模型必须包含真实权重；仅 vocab 文件只用于元数据与预期加载失败测试。

| 用例 | 文件 | 必须匹配的 GGUF architecture |
|---|---|---|
| llama | tinyllama-1.1b-chat-q4_k_m.gguf | llama |
| qwen2 | qwen2-0.5b-instruct-q4_k_m.gguf | qwen2 |
| gemma2 | gemma-2-2b-it-q4_k_m.gguf | gemma2 |
| mistral | mistral-7b-instruct-v0.3-q4_k_m.gguf | llama |
| DeepSeek 蒸馏 | deepseek-r1-distill-qwen-1.5b-q4_k_m.gguf | qwen2 |
| DeepSeek 原生 MLA | deepseek2-mla-q4_k_m.gguf | deepseek2 |
| ChatGLM | chatglm3-6b-q4_k_m.gguf | chatglm |

原生 MLA 模型需另行准备并按约定命名，现有下载清单中的 Distill-Qwen 不能替代它。实际模型转换器若输出不同架构名，需先核实对应引擎实现，再更新测试模型与期望值。模板测试使用模型家族的固定 prompt，验证可加载和生成，不等于逐字验证模板渲染器或回答质量。

## 构建与执行

```powershell
hvigorw --mode module -p product=default -p module=entry@ohosTest assembleHap --no-daemon
hdc list targets
hdc shell aa test -b cn.hyshiling.Harmony_gguf -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 180000
```

可直接从 DevEco 的设备测试入口运行。Hypium 用例超时设为 180000 ms，需高于探针的 60000 ms。同步 Native 死锁会阻塞 JS 定时器，必须同时设置设备测试进程的外部超时或通过 DevEco 终止测试；JS 超时不能保证打断 Native 调用。

本项目没有签名配置时只生成 `entry/build/default/outputs/ohosTest/entry-ohosTest-unsigned.hap`，不能把编译成功作为设备执行成功。测试报告需记录设备、模型、每个用例结果、缺失模型与失败日志。

## 契约与质量判定

- 同步错误验证 `[error 1001]`、`[error 1002]`、`[error 1003]`、`[error 1005]`；当前 NAPI 将错误码编码在异常消息中，不能假设 `Error.code` 存在。
- 超过槽位上下文的 prompt 验证异步 `error` 与 `GenerateError.code = 1004`，并验证之后仍可生成。此项记录当前输入长度边界行为，不把它视为长对话自动滑窗的完整验收。
- 主动停止必须返回 `stopped + GenerateStats`，不能把 `done` 或 `error` 当作停止成功；契约虽保留 1007，但当前停止接口不通过 error 事件返回它。
- 1006 内存不足需要受控故障注入，当前没有稳定注入接口，未编写消耗设备内存的破坏性用例；这项不声称已验证。
- 连续生成检查 token 类型、终态次数、统计数值、maxTokens 上限和事件循环调度；模型可能存在不输出文本的 token，因此回调数不得大于 generatedTokens，不强行要求两者相等。
- 两请求停止隔离、满槽 1005、stopAll 后再次生成、生成中卸载后重新加载均为独立用例。长生成使用 4096 上限并立即请求停止；若模型提前自然结束，用例严格失败，应核查日志，不能放宽为 done 也算成功。
- API.md 描述共用槽位池，TDD.md 与当前实现描述 NAPI/Serve 独立池。C++ 独立池用例按 TDD 编写；该文档差异需 A/B 统一。HTTP 调度与 Serve 路由不属于本次 M2 测试。

## 当前状态

2026-09-17 本地 C++ 实测：11 用例、59 断言、0 失败、0 异常、0 跳过。此前槽位数量未保存、重复结束导致计数下溢及停止期间新请求进入的问题均已修复并加入回归测试。

NAPI 参数校验已覆盖加载配置、生成参数、modelId 和 requestId；元数据 `fileSize` 已改为实际文件大小。arm64-v8a 与 x86_64 的 `libentry.so` 均通过 OHOS 工具链完整编译，ohosTest HAP 编译成功。

设备未连接，`test/models/inference/` 仅有 `.gitkeep`。因此真实 TSFN 多 token 回调、按请求停止、stopAll、带权重模型加载以及 DeepSeek/ChatGLM 冒烟仍需按本说明执行，不能根据编译结果标记为运行通过。
