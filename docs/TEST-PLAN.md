# Harmony-GGUF — 测试计划

> 状态同步：2026-10-15。统一进度见 [STATUS.md](STATUS.md)。勾选只对应条目明确写出的范围；历史报告与当前快照结果分别记录。

## 当前验证摘要

本轮双 ABI Release 独立构建、HAP 离线构建与签名通过；Windows CTest 12/12 组通过，共 740 个断言，用时 26.89 秒。原生生命周期组为 16 个用例、137 个断言，包含新增 8 轮词表模型加载、缓存分配与卸载。用例内仍有 4 项真实权重相关跳过。

设备 NAPI、真实权重、多模态、NNRt 与 Serve 网络回归本轮未执行，独立 CodeLinter 工具缺失。当前最高优先级为用户报告的 CPU/NPU 多次加载后卡住、闪退；本地私有内存稳定不构成设备泄漏已解决的证据。

## 1. 测试策略总览

采用**双轨测试**体系，覆盖 ArkTS 应用层与 C++ 引擎层：

| 轨道 | 框架 | 位置 | 运行环境 | 覆盖阶段 |
|------|------|------|----------|----------|
| ArkTS 单元测试 | `@ohos/hypium` | `entry/src/test/` | DevEco / 模拟器 / 真机 | 全阶段 |
| ArkTS 设备测试 | `@ohos/hypium` | `entry/src/ohosTest/` | 模拟器 / 真机 | 阶段 2+ |
| C++ 引擎测试 | `test/testing.h` | `test/test-*.cpp` | 本地 shell / 真机 shell | 阶段 1+ |

## 2. 测试分层

```
┌─────────────────────────────────────────────────┐
│  L4  端到端测试（E2E）     阶段 3+  真机          │
├─────────────────────────────────────────────────┤
│  L3  Serve API 自动化测试  阶段 5   curl/脚本     │
├─────────────────────────────────────────────────┤
│  L2  NAPI 集成测试         阶段 2   ohosTest     │
├─────────────────────────────────────────────────┤
│  L1  单元测试              阶段 0+  hypium/C++  │
└─────────────────────────────────────────────────┘
```

## 3. 各阶段测试任务

### 阶段 0 — 准备（Day 1–2）
- [x] 确认 hypium 框架可用（`oh-package.json5` 已声明 `@ohos/hypium` 1.0.25）
- [x] 搭建 CI 流水线（`.gitlab-ci.yml` + `scripts/ci-*.sh`）
- [x] 准备测试模型集清单（`test/models/MANIFEST.md`）
- [x] 编写模型准备脚本（当前为 `scripts/fetch-test-models.ps1`，由用户手动执行）

### 阶段 1 — 引擎移植（Day 3–12）
- [x] ggml 基础算子单测（与 CPU 参考实现比对数值）
- [x] GGUF 解析单测（校验元数据字段）
- [x] llama/qwen2 词表模型加载冒烟测试；真实权重覆盖见设备历史报告与待办
- [x] tokenizer 编码/解码往返测试（token→id→token 一致性）
- [x] 词表模型加载卸载与缓存生命周期本地回归；真实推理 KV/设备泄漏验证尚未完成
- [x] 定义性能基线指标（首字延迟 < 5s、tokens/s 目标值）

### 阶段 2 — NAPI 桥接（Day 13–18）
- [x] 原生生命周期回归当前 16 个用例、137 个断言通过；2026-09-17 设备记录摘要见第 10 节
- [x] C++ 测试接入 CTest 超时与 CI；真实 NAPI 测试迁移至 ohosTest，移除空 Native mock 映射
- [x] 设备测试 HAP 编译、模拟器安装与沙箱模型部署流程验证
- [x] 无模型 NAPI 契约 7 项及 vocab-only 边界通过
- [x] Qwen2 真实模型独立冒烟历史通过（2026-09-17，1/1，39.723 秒）；更新快照后待重跑
- [ ] NAPI 接口集成测试（parseGgufMetadata / loadModel / unloadModel）完整隔离回归
- [ ] 流式回调稳定性测试（onToken / onDone / onError）完整隔离回归
- [ ] 停止生成按 requestId 验证（stopGenerate / stopAllGenerations）完整隔离回归
- [ ] SmolLM2 / llama 独立冒烟与模型切换（按用户要求延后）
- [ ] 特殊架构（deepseek / chatglm）冒烟补齐

### 阶段 3 — 模型+对话（Day 19–23）
- [ ] 端到端测试：导入→加载→对话闭环
- [ ] 断网验证（全程无网络请求）
- [ ] 多轮对话上下文保持验证

### 阶段 4 — 完善（Day 24–28）
- [ ] 性能基线测试（首字延迟、tokens/s 实测记录）
- [ ] 崩溃/内存监控（长对话 20 轮压力测试）
- [ ] 复现 CPU/NPU 多次加载后卡住、闪退；采集加载前、推理后、卸载后的内存、线程和崩溃记录
- [ ] 参数生效验证（temperature / context length 调整后效果变化）
- [ ] MVP 验收标准 1–5 项验证

### 阶段 5 — Serve（Day 29–35）
- [ ] Serve API 自动化测试（curl 调用 /health、/v1/models、流式补全）
- [ ] SSE 流式响应校验（逐 token 格式校验）
- [ ] 鉴权测试（401 无效/缺失 API Key）
- [ ] 并发调度测试（多槽位并发、满负载排队、按请求停止）
- [ ] 长运行压力测试与并发稳定性
- [ ] 全量回归（构建 + lint + 单测 + 真机测试）

## 4. 性能基线指标

参考 PRD 非功能需求，定义以下基线（以 llama Q4_K_M 为基准模型）：

| 指标 | 目标值 | 测量方法 | 阶段 |
|------|--------|----------|------|
| 首字延迟 (TTFT) | < 5s | 首次 generate 到 onToken 回调的时间差 | M1 起记录 |
| 生成速度 | 稳定无卡顿 | tokens/s 实测记录 | M1 起记录 |
| 崩溃率 | < 0.5% | 长对话 20 轮以上统计 | M4 |
| 模型加载成功率 | ≥ 95% | 多次加载统计 | M3 |
| 导入到首对话完成率 | ≥ 80% | 端到端统计 | M3 |

## 5. CI 流水线

流水线定义于 `.gitlab-ci.yml`，包含三个阶段：

| 阶段 | 任务 | Runner 要求 | 触发条件 |
|------|------|-------------|----------|
| lint | `codeLinter` | 标准 Node.js | main / MR / phase* 分支 |
| build | `assembleHap` | OHOS SDK 自托管 | main / MR / phase* 分支 |
| test | `hvigorw test` | OHOS SDK 自托管 | main / MR / phase* 分支 |

辅助脚本位于 `scripts/`：
- `ci-lint.sh` — 代码检查
- `ci-build.sh` — 构建 HAP
- `ci-test.sh` — ArkTS 单元测试
- `ci-cpp-test.sh` — C++ 引擎测试（阶段 1 启用）
- `fetch-test-models.ps1` — 模型准备脚本；由用户手动执行，代理不得下载或安装

## 6. 测试模型集

详见 `test/models/MANIFEST.md`，其中列出计划模型，不代表权重全部已就绪。本轮本地 inference 目录仅有占位文件，使用已有词表 GGUF 执行回归。

## 7. 崩溃与内存监控策略

| 手段 | 工具/方法 | 阶段 |
|------|-----------|------|
| C++ 内存泄漏 | Valgrind / AddressSanitizer（本地） | 阶段 1+ |
| 真机内存监控 | `hdc shell hidumper` / `hidisk` | 阶段 3+ |
| 长对话压力 | 20 轮连续对话，检查内存泄漏与稳定性 | 阶段 4 |
| 崩溃日志 | `hdc shell hilog` + crash 日志抓取 | 阶段 3+ |

## 8. 验收标准映射

### MVP 验收（M4）
1. 用户能导入一个 GGUF 文件并看到模型元数据 → L2 NAPI 集成测试
2. 模型能成功加载并进入可对话状态 → L4 端到端测试
3. 输入文本后，模型能流式返回回答 → L4 端到端测试
4. 调整 temperature / context 等参数后效果生效 → L4 参数验证
5. 全程无网络请求（可断网验证） → L4 断网验证

### Serve 验收（M5）
1. 启动 Serve 后，本机可通过 curl 获取模型列表 → L3 API 测试
2. 可通过 POST 获取流式回答（SSE） → L3 SSE 测试
3. 开启局域网监听后，同网段设备可访问 → L3 局域网测试

## 9. 阶段 1 (M1) C++ 引擎测试执行报告

本节为 2026-09-04 历史记录。命令、环境与缺陷描述仅反映当时状态；本轮结果见文首及第 10 节。旧测试名称“无泄漏”只表示执行完成，未测量真实权重或设备泄漏。

> 日期：2026-09-04 · 角色 C（质量保障）· 里程碑 M1
> 环境：Windows 11 + MSVC 19.44 + CMake 3.31.6
> 测试框架：`test/testing.h`

### 9.1 测试结果总览

| 测试 | 测试数 | 断言数 | 失败 | 跳过 | 状态 |
|------|--------|--------|------|------|------|
| `test-ggml-ops` | 8 | 23 | 0 | 0 | ✅ PASS |
| `test-gguf-parse` | 8 | 18 | 0 | 0 | ✅ PASS |
| `test-model-load` | 6 | 10 | 0 | 0 | ✅ PASS |
| `test-tokenizer-roundtrip` | 7 | 72 | 0 | 0 | ✅ PASS |
| `test-smoke-generate` | 5 | 8 | 0 | 2 | ✅ PASS |
| `test-memory-check` | 4 | 11 | 0 | 2 | ✅ PASS |
| **合计** | **38** | **142** | **0** | **4** | **✅ ALL PASS** |

### 9.2 跳过项说明

以下测试需要 Q4 量化推理模型（含权重），当前仅有 vocab-only 测试模型，自动 SKIP：

| 测试 | 跳过原因 | 获取方式 |
|------|----------|----------|
| tinyllama 推理冒烟 | 需要 Q4 量化模型 | 用户手动按 test/models/MANIFEST.md 准备 |
| qwen2 推理冒烟 | 需要 Q4 量化模型 | 用户手动按 test/models/MANIFEST.md 准备 |
| KV Cache 多轮 decode 递增 | 需要 Q4 量化模型 | 同上 |
| KV Cache 清除后归零 | 需要 Q4 量化模型 | 同上 |

### 9.3 测试覆盖明细

**test-ggml-ops（ggml 基础算子单测）**
- `ggml_add` 逐元素加法 ✅
- `ggml_mul` 逐元素乘法 ✅
- `ggml_mul_mat` 矩阵乘法 ✅
- `ggml_soft_max` 归一化指数 ✅
- `ggml_rms_norm` RMS 归一化 ✅
- `ggml_silu` SiLU 激活函数 ✅
- `ggml_rope` 旋转位置编码 ✅

**test-gguf-parse（GGUF 解析单测）**
- GGUF 文件头解析 ✅
- llama-bpe 元数据解析 ✅
- qwen2 元数据解析 ✅
- gemma4 元数据解析 ✅
- deepseek(llama arch) 元数据解析 ✅
- GGUF tensor 信息解析 ✅
- 不存在的 key 返回 -1 ✅

**test-model-load（模型加载冒烟）**
- llama-bpe 模型加载 ✅
- qwen2 模型加载 ✅
- gemma 模型加载 ✅
- deepseek-coder 模型加载 ✅
- 不存在的文件返回空 ✅

**test-tokenizer-roundtrip（tokenizer 往返测试）**
- llama-bpe tokenizer 往返 ✅
- qwen2 tokenizer 往返 ✅
- gemma tokenizer 往返 ✅
- gpt-2 tokenizer 往返 ✅
- 空文本 tokenize ✅
- token id 范围有效 ✅

**test-smoke-generate（主路径生成冒烟）**
- llama-bpe vocab 冒烟（加载 + tokenize + token_to_piece）✅
- qwen2 vocab 冒烟 ✅
- tinyllama 推理冒烟（decode + sample）⏭️ SKIP
- qwen2 推理冒烟 ⏭️ SKIP

**test-memory-check（生成循环内存检查）**
- 多次加载/卸载无泄漏（5 轮）✅
- KV Cache 多轮 decode 递增 ⏭️ SKIP
- KV Cache 清除后归零 ⏭️ SKIP

### 9.4 构建系统修复记录

测试从"写了从未跑过"到"全部通过"，过程中修复以下构建与 API 兼容问题：

| 问题 | 文件 | 修复 |
|------|------|------|
| MSVC 不识别 GCC 编译选项 | `test/CMakeLists.txt` | 添加 `if(MSVC)` 分支 |
| MSVC 代码页 936 无法解析 UTF-8 源文件 | `test/CMakeLists.txt` | 添加 `/utf-8` 选项 |
| C++20 下 `u8` 字面量为 `char8_t` 与引擎 `LU8` 宏冲突 | `test/CMakeLists.txt` | 添加 `/Zc:char8_t-` 选项 |
| 指定初始化器需 C++20 | `test/CMakeLists.txt` | `CMAKE_CXX_STANDARD` 改为 20 |
| `testing.h` 不在 include 路径 | `test/CMakeLists.txt` | 添加 `test/` 根目录 |
| `ggml_softmax` 函数名不存在 | `test-ggml-ops.cpp` | 改为 `ggml_soft_max` |
| `ggml_rope` 参数数量不匹配 | `test-ggml-ops.cpp` | 改为 5 参数版本 |
| `ggml_mul_mat` 张量维度错误 | `test-ggml-ops.cpp` | 修正 b 张量维度 |
| `ggml_rope` 位置张量维度不匹配 | `test-ggml-ops.cpp` | 位置张量改为 1 元素 |
| vocab-only 模型无权重导致加载失败 | `test-model-load.cpp` | 添加 `vocab_only=true` |
| vocab-only 模型无权重导致加载失败 | `test-tokenizer-roundtrip.cpp` | 添加 `vocab_only=true` |
| vocab-only 模型无法创建 context | `test-smoke-generate.cpp` | 拆分 vocab 冒烟 + 推理冒烟 |
| vocab-only 模型无法创建 context | `test-memory-check.cpp` | 拆分加载/卸载 + KV Cache 测试 |
| `llama_new_context_with_model` 已弃用 | `test-smoke-generate.cpp` | 改为 `llama_init_from_model` |
| `llama_token_to_piece` 参数数量不匹配 | `test-smoke-generate.cpp` | 移除多余的 `nullptr` 参数 |
| gemma 架构名实际为 gemma4 | `test-gguf-parse.cpp` | 修正断言 |
| deepseek 架构名实际为 llama | `test-gguf-parse.cpp` | 修正断言 |
| `n_tensors > 0` 对 vocab-only 模型不成立 | `test-gguf-parse.cpp` | 改为 `>= 0` |

### 9.5 CI 接入状态

| 变更 | 文件 | 说明 |
|------|------|------|
| `cpp-test` 正式卡点 | `.gitlab-ci.yml` | `allow_failure` 从 `true` 改为 `false` |
| 全量测试脚本 | `scripts/ci-cpp-test.sh` | 编译运行全部 6 个测试目标，逐个报告 PASS/FAIL |
| PowerShell 一键测试 | `scripts/run-tests.ps1` | 新增 `-CppTest` 参数，自动查找 cmake 并运行 |

### 9.6 运行方式

```powershell
# PowerShell（Windows 本地）
.\scripts\run-tests.ps1 -CppTest

# Bash（CI / Linux）
bash scripts/ci-cpp-test.sh

# 手动编译运行单个测试
cd test
cmake -B build -S .
cmake --build build --target test-ggml-ops --config Debug
.\build\Debug\test-ggml-ops.exe
```

### 9.7 后续待办

- [ ] 用户手动准备 Q4 量化推理模型，补齐本地 4 个 SKIP 项
- [ ] 推理冒烟通过后，记录首字延迟 (TTFT) 与 tokens/s 性能基线数据
- [ ] KV Cache 测试通过后，确认无内存泄漏
- [ ] 历史 `mul_mat` SIGSEGV 在当前版本的设备复测；原始记录未附有效当前日志，不能与本轮 MinGW 栈对齐问题混为一谈

## 10. 阶段 2（M2）当前记录

> 更新日期：2026-10-15；2026-09-17 设备报告作为历史证据保留。
>
> 阶段状态：**进行中，尚未完成验收**
>
> 原详细报告位于 `reports/test-report-M2.md`，当前工作区已删除；以下保留历史摘要，不作为本轮设备验证。

当前已完成更新快照的双 ABI Release 构建、HAP 构建和本地全量 CTest；设备 NAPI 分组回归仍未完成。历史 Qwen2 冒烟不自动继承为当前快照通过结果，SmolLM2 与模型切换的历史延后状态也不代表已完成。

| 范围 | 当前状态 | 结果 |
|---|---|---|
| C++ EngineState | 本轮通过 | 16 用例、137 断言；本轮 m2-napi-bridge 15.57 秒 |
| Native ABI | 本轮通过 | 独立干净目录 Release arm64-v8a、x86_64 编译链接通过 |
| 模拟器环境 | 历史记录 | 2026-09-17：HarmonyOS 6.1.0.126、API 24、x86_64，已部署；本轮未部署 |
| 无模型契约 | 历史通过 | 2026-09-17 的 7 项通过；当前快照待重跑 |
| vocab-only 边界 | 本地通过/设备待回归 | 本地词表解析、加载通过；设备拒绝推理加载为历史证据 |
| Qwen2 冒烟 | 历史通过 | 2026-09-17：1/1，39.723 秒；本轮未执行真实权重推理 |
| NAPI 桥接回归 | 进行中 | 部分场景仅在受超时污染的整轮运行中观察通过，需拆分后重跑 |
| SmolLM2 / llama | 延后 | `contextLength` 解析为 0；当前不继续独立冒烟 |
| 模型切换 | 延后 | 现有场景依赖 SmolLM2 |
| 其他架构 | 未开始 | 缺少 Gemma2、Mistral、DeepSeek、ChatGLM 权重文件 |

历史缺陷为同步 `loadModel` 在模拟器主线程加载 Qwen2 时触发 `THREAD_BLOCK_6S`。当前应用已通过 taskpool 执行加载与卸载，仍需设备确认；直接 NAPI 调用仍是同步接口。当前另有用户报告的重复加载卡住、闪退，尚无充分证据确认泄漏或其他根因。

后续顺序：优先复现重复加载闪退并采集内存证据；使用用户准备的权重执行流式、并发、停止、卸载恢复和模型切换的隔离回归；再补齐各架构、视觉、NNRt 与 Serve。M2 必需设备项未完成前保持“待验收”。详细同步范围与构建修复见 [UPSTREAM-UPDATE.md](UPSTREAM-UPDATE.md)。
