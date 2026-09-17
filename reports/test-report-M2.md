# 阶段 2（M2）测试编写交付与执行结果

> 更新日期：2026-09-17。以下为本轮 C 角色交付；文末旧报告保留为历史记录，当前状态以本节为准。

## 本轮交付

- 重写 `test/harmony/test-napi-bridge.cpp`，11 个用例；分配失败不再 EndGenerate，无局部引用 detach 超时线程；卸载时模拟工作线程响应停止并结束请求。
- 新增设备侧 `NapiIntegration.test.ets`、`M2GenerationProbe.ets`、`M2Fixtures.ets`，合计 20 个用例，覆盖模型管理、错误、流式、并发、停止、卸载和 7 个架构/模型家族冒烟。
- 从本地单测移除真实 NAPI 测试，注册到 ohosTest；清除将 libentry.so 替换为空对象的 mock 映射。
- CTest 120 秒进程超时；修正 Windows M2 脚本的错误码传递；Bash CI 在 M1 后执行 M2。
- 修复槽位生命周期与 NAPI 参数契约问题；运行及模型部署说明见 `docs/M2-TESTING.md`，工作进度同步 `docs/TEST-PLAN.md`。

## 本轮验证

| 检查 | 命令 | 结果与记录 |
|---|---|---|
| C++ 编译 | `cmd /c scripts\cpp-build-only.bat` | 成功，`reports/m2-cpp-build.log` |
| C++ 执行 | `ctest --test-dir test/build -R '^m2-napi-bridge$' --output-on-failure` | 11 用例、59 断言、0 失败、0 异常、0 跳过；`reports/m2-cpp-test.log` |
| 设备测试包 | `hvigorw --mode module -p product=default -p module=entry@ohosTest assembleHap --no-daemon` | 编译成功；`reports/m2-ohos-build.log`；无签名配置，仅生成 unsigned HAP |
| Native ABI | SDK CMake 分别构建 arm64-v8a / x86_64 `entry` | 两个 ABI 均完整编译并链接 `libentry.so` |
| 设备连接 | `hdc list targets` | `[Empty]`，未进行设备执行 |
| 模型集 | 检查 `test/models/inference/` | 只有 `.gitkeep`，缺少设备推理所需权重 |
| lint | `hvigorw codeLinter --mode module -p product=default --no-daemon` | 未注册 codeLinter 任务，退出 1；`reports/m2-lint.log` |

首次设备包编译发现探针重抛异常不符合 ArkTS 类型约束，已改为 Error 类型并重新编译成功。

## 缺陷与验收状态

1. **本地回归通过。** 槽位数量赋值已恢复；重复 EndGenerate 不再递减活跃计数；停止/卸载期间新请求会被拒绝并释放预占槽位；stopAll 后可继续生成。
2. **NAPI 契约已加固。** 加载与生成参数执行类型和值域校验，非法 modelId/requestId 返回 1001；元数据 fileSize 使用实际 GGUF 文件大小。
3. **设备用例待运行。** 当前无 HDC 目标且无权重模型，不能验证真实 TSFN、多 token、停止终态和模型架构推理。
4. **覆盖边界。** DeepSeek 蒸馏不算原生 MLA；模板冒烟验证固定家族 prompt，不证明模板渲染器完整；1006 需要受控故障注入，未通过强行耗尽内存测试；停止按 stopped+stats 验证。

结论：M2 测试编写、本地状态机验证和双 ABI 编译已完成；设备验收尚未通过。准备权重模型并连接设备后，按运行说明执行 20 个 ohosTest 用例，再更新阶段 2 的四项验收勾选。

---

# 历史记录：本轮接手前的 M2 诊断报告

> 日期：2026-09-17  角色 C（质量保障）  里程碑 M2
> 环境：Windows 11 + MSVC 19.44.35217 + CMake(Ninja) + vcvars64
> 测试框架：test/testing.h

---

## 1. 需读取的文件

### 1.1 设计与契约文档

| 文件 | 用途 |
|------|------|
| docs/API.md | NAPI 接口契约（数据结构、错误码 0/1001-1007、接口签名） |
| docs/TDD.md | 技术设计（架构、NAPI 接口、数据流、线程模型） |
| docs/PLAN-35DAY.md | 35 天计划（阶段 2 Day 13-18 任务分工） |
| docs/TEST-PLAN.md | 测试计划（阶段 2 测试任务清单、性能基线、CI 流水线） |

### 1.2 NAPI 实现代码（C++）

| 文件 | 内容 |
|------|------|
| entry/src/main/cpp/napi/engine_state.h | EngineState 单例：槽位池（Napi/Serve 独立）、LoadConfig、BeginGenerate/EndGenerate/RequestStop/RequestStopAll/WaitGenerateEnd |
| entry/src/main/cpp/napi/engine_state.cpp | 上述方法实现：模型加载/卸载、槽位分配/释放、停止标志、decode_mutex_ 保护 |
| entry/src/main/cpp/napi/llama_inference.h | inference::RunGeneration / RunGenerationAsync：推理循环 |
| entry/src/main/cpp/napi/llama_inference.cpp | 推理循环实现：采样链、context shift、KV cache 管理、停止检查 |
| entry/src/main/cpp/napi/model_napi.cpp | NAPI 导出：parseGgufMetadata / loadModel / unloadModel |
| entry/src/main/cpp/napi/generate_napi.cpp | NAPI 导出：generate / stopGenerate / stopAllGenerations，TSFN 回调 |
| entry/src/main/cpp/napi/napi_util.h | NAPI 工具函数（字符串/数值/对象读写、错误抛出） |
| entry/src/main/cpp/common/error_code.h | 错误码枚举（Ok/InvalidArgument/ModelNotLoaded/.../GenerationAborted） |
| entry/src/main/cpp/common/ts_fn.h / ts_fn.cpp | napi_threadsafe_function 封装（依赖 NAPI 运行时，不可在纯 C++ 测试中使用） |
| entry/src/main/cpp/napi_init.cpp | 模块注册入口 |
| entry/src/main/cpp/CMakeLists.txt | HAP 构建配置 |

### 1.3 ArkTS 类型声明与测试

| 文件 | 内容 |
|------|------|
| entry/src/main/cpp/types/libentry/Index.d.ts | 全部 NAPI 接口的 ArkTS 类型声明 |
| entry/src/test/NapiIntegration.test.ets | 现有 ArkTS NAPI 集成测试（hypium，需真机/模拟器） |
| entry/src/test/LocalUnit.test.ets | 现有 ArkTS 本地单元测试 |
| entry/src/test/List.test.ets | 测试套件注册 |
| entry/src/mock/Libentry.mock.ets | NAPI mock（当前为空） |

### 1.4 C++ 测试

| 文件 | 内容 |
|------|------|
| test/testing.h | 轻量测试框架（test/assert_true/assert_equal/skip/summary） |
| test/CMakeLists.txt | C++ 测试构建系统（engine_test_lib 静态库 + 7 个测试目标） |
| test/harmony/test-napi-bridge.cpp | 本次新增：EngineState 槽位管理测试 |
| test/harmony/test-*.cpp | M1 已有 6 个测试 |

---

## 2. 目前的进度

### 2.1 已完成

1. 环境验证与基线确认
   - 解决了 CMake 找不到 MSVC 编译器的问题：需在 vcvars64 环境下使用 Ninja 生成器 + 显式指定 cl 编译器
   - 命令：cmake -B build -S . -G Ninja -DCMAKE_C_COMPILER=cl -DCMAKE_CXX_COMPILER=cl -DCMAKE_BUILD_TYPE=Debug
   - M1 基线全部通过：6 个测试 / 38 测试用例 / 142 断言 / 0 失败 / 4 跳过

2. 新增 C++ 测试 test-napi-bridge.cpp
   - 测试 EngineState 槽位管理逻辑（不依赖 NAPI 运行时）
   - 覆盖：模型生命周期、Napi/Serve 池独立分配、槽位上限、释放后重分配、RequestStop/RequestStopAll、卸载时停止生成、slot_context 配置
   - 更新 test/CMakeLists.txt：将 napi/engine_state.cpp + napi/llama_inference.cpp 加入 engine_test_lib

3. 给 LoadConfig 增加 vocab_only 字段
   - engine_state.h：LoadConfig 新增 bool vocab_only = false
   - engine_state.cpp：LoadModel 中传递 model_params.vocab_only = config.vocab_only，vocab_only 模式下跳过 context 创建
   - IsLoaded() 改为只检查 model_ != nullptr（vocab_only 模式下 ctx_ 为 null）
   - 目的：让 vocab-only 测试模型（无权重）能用于槽位管理测试

### 2.2 当前卡点

test-napi-bridge.exe 在 BeginGenerate + EndGenerate 之后调用 UnloadModel 时死锁。

通过 stderr trace 精确定位：
- test_model_lifecycle 中的 UnloadModel（无活跃生成）正常通过
- test_slot_allocation 中 BeginGenerate -> EndGenerate（trace 确认完成）-> UnloadModel 超时（5s）卡死
- UnloadModel 的 gen_cv_.wait(active_count_ == 0) 永远等不到

诊断测试 1 确认：BeginGenerate + EndGenerate 后直接 UnloadModel -> 超时。
诊断测试 2（不调 EndGenerate，直接 UnloadModel）尚未执行到（被诊断测试 1 的残留线程阻塞）。

### 2.3 待完成

- [ ] 定位死锁根因（EndGenerate 留下不一致状态 vs UnloadModel 锁顺序问题）
- [ ] 修复后跑通 test-napi-bridge
- [ ] 修正 NapiIntegration.test.ets（stopGenerate 缺 requestId、vocab-only 模型无法推理等）
- [ ] 补充 ArkTS 侧并发槽位/stopAllGenerations/错误码测试
- [ ] 更新 docs/TEST-PLAN.md 阶段 2 勾选项
- [ ] 按小单元改动提交（feat: / fix: 前缀）

---

## 3. 尝试过的方式

### 3.1 CMake 编译器探测失败

| 尝试 | 结果 |
|------|------|
| cmake -B build -S .（默认） | 找不到 C/CXX 编译器 |
| cmake -G Visual Studio 17 2022 -A x64 | VS 生成器自身探测编译器失败 |
| cmd 中 call vcvars64.bat 后 cmake | vcvars 环境未传递给 cmake 子进程 |
| 批处理文件 cpp-build-env.bat（vcvars + cmake 同一 cmd） | VS 生成器仍失败 |
| Ninja 生成器 + 显式 cl | 成功 |

最终方案：cmake -G Ninja -DCMAKE_C_COMPILER=cl -DCMAKE_CXX_COMPILER=cl，在 vcvars64 环境中运行。

### 3.2 vocab-only 模型加载失败

| 尝试 | 结果 |
|------|------|
| 直接用 EngineState::LoadModel 加载 vocab-only 模型 | llama_init_from_model 失败（无权重张量 token_embd.weight） |
| 给 LoadConfig 加 vocab_only 字段，跳过 context 创建 | 模型加载成功，但 UnloadModel 死锁（见 2.2） |

### 3.3 死锁定位

| 尝试 | 结果 |
|------|------|
| 直接运行测试，观察输出 | 卡住无输出，无法定位 |
| 在测试中加 fprintf(stderr, trace) + fflush | 定位到卡在 UnloadModel |
| unload_with_timeout()（独立线程 + 5s 超时） | 确认 UnloadModel 超时，不阻塞后续 trace |
| 诊断测试 1（BeginGenerate+EndGenerate 后 UnloadModel） | 超时，确认 EndGenerate+UnloadModel 组合有问题 |
| 诊断测试 2（不调 EndGenerate 直接 UnloadModel） | 尚未执行到（被诊断 1 拖留线程阻塞） |

---

## 4. 执行规范（用户要求）

### 4.1 提交规范

- 按小单元改动提交，conventional commit 格式：
  - feat: add NAPI integration testing
  - fix: ...
- 不 git commit 除非用户明确要求

### 4.2 测试记录规范

- 测试记录写入 reports/ 目录
- 包含：测试内容、测试方法（命令使用）、测试结果
- 用于用户后续自行验证

### 4.3 文档维护规范

- 工作记录与总结写入 docs/TEST-PLAN.md，持续更新

### 4.4 调试规范

- 不通过修改正式代码来猜测原因
- 先通过测试中的调试输出（trace）或超时机制定位具体卡在哪一步
- 确认是模型加载、BeginGenerate、EndGenerate 还是 UnloadModel 的 WaitGenerateEnd，再决定修改

### 4.5 环境确认规范

- MSVC 已确认正常，where cl 可找到编译器
- 不再检查 VS 是否安装或 cl 是否存在

### 4.6 代码规范（AGENTS.md）

- 所有输出（代码注释、文档、回复）使用简体中文
- 默认不写注释，除非用户明确要求
- 遵循现有代码风格
- NAPI 统一使用错误码 0 / 1001-1007

---

## 5. 测试运行方法

### 5.1 编译 C++ 测试

在 vcvars64 环境中：

    cd test
    cmake -B build -S . -G Ninja -DCMAKE_C_COMPILER=cl -DCMAKE_CXX_COMPILER=cl -DCMAKE_BUILD_TYPE=Debug
    cmake --build build --target test-napi-bridge

或使用辅助脚本：

    # 编译
    cmd /c scripts\cpp-build-only.bat

    # 运行（带超时 trace）
    cmd /c scripts\cpp-run-napi-bridge.bat > reports/napi-bridge-run.log 2>&1

### 5.2 运行全部 C++ 测试

    .\scripts
un-tests.ps1 -CppTest

### 5.3 查看测试结果

    # trace 输出（定位卡住位置）
    Get-Content reports/napi-bridge-run.log | Select-String trace

    # 测试汇总
    Get-Content reports/napi-bridge-run.log | Select-String PASS|FAIL|tests|assertions|EXIT
