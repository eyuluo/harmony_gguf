# Harmony-GGUF UI 运行与使用说明

本文面向需要查看、联调或验收 UI 的项目成员。即使此前没有使用过 DevEco Studio，也可以按顺序完成构建、模拟器运行和基本功能检查。

> 当前项目仍在开发中。部分模型兼容性、真实设备性能和完整交互尚未最终验证，出现未完成状态不一定代表环境配置错误。

## 1. 最快运行流程

1. 使用 DevEco Studio 打开**项目根目录**，不要只打开 `entry` 文件夹。
2. 等待右下角工程同步完成；首次打开时下载依赖会比较慢。
3. 在 Device Manager 中启动一个 HarmonyOS 手机模拟器。
4. 在顶部运行配置中选择 `entry`，设备选择刚启动的模拟器。
5. 点击顶部三角形 **Run**，等待 HAP 构建、安装并启动。
6. 模拟器出现 Harmony-GGUF 的“聊天 / 模型 / 服务 / 设置”页面即表示运行成功。

如果顶部模块显示 `None` 或模块列表为空，请先看[常见问题](#7-常见问题)。

## 2. 环境准备

### 2.1 必需软件

- DevEco Studio
- 与项目匹配的 HarmonyOS SDK
- OHOS NDK / Native 工具链
- CMake
- Command-line Tools（包含 `hdc`）

本项目会同时编译 ArkTS UI 和 C++ Native 代码，因此只安装基础 SDK Platform 不够。可以在 DevEco Studio 的 SDK Manager 中检查对应版本的 SDK、Native、CMake 和工具链是否已经安装。

项目当前构建配置见根目录的 `build-profile.json5`：

- `targetSdkVersion`: `26.0.0`
- `runtimeOS`: `HarmonyOS`
- Native 编译器：`BiSheng`
- 支持 ABI：`arm64-v8a`、`x86_64`

### 2.2 项目路径要求

项目路径尽量只包含英文字母、数字、空格、连字符和下划线，例如：

```text
D:\Harmony_Project\Harmony_GGUF
```

不要放在包含中文字符的目录中，否则 Hvigor 可能报告 `Invalid project path`。

## 3. 构建与运行

### 3.1 第一次打开项目

DevEco Studio 打开项目后会自动进行工程同步，主要完成以下工作：

- 读取 `build-profile.json5` 和模块配置；
- 检查 SDK、NDK 与构建工具；
- 解析和下载 OHPM 依赖；
- 识别 `entry` 模块及其运行配置。

“工程同步成功”只表示 DevEco 已经理解项目结构，不代表应用已经运行。

### 3.2 只检查能否构建

选择菜单：

```text
Build -> Build Hap(s)/APP(s) -> Build Hap(s)
```

看到以下内容表示 ArkTS、资源和 Native 代码均已通过编译并成功打包：

```text
hvigor BUILD SUCCESSFUL
```

构建生成 HAP，但**不会打开模拟器中的 UI**。

未配置正式签名时可能出现：

```text
Will skip sign 'hos_hap'. No signingConfigs profile is configured
```

这是当前开发阶段的常规提示，不影响本地构建；正式发布或需要签名安装时再配置签名。

### 3.3 在模拟器中运行 UI

1. 打开 `Tools -> Device Manager`，创建或启动手机模拟器。
2. 等待模拟器完整进入桌面，不要停留在启动动画。
3. 打开顶部运行配置；若没有配置，进入 `Run -> Edit Configurations`。
4. 新建或选择 HarmonyOS 应用运行配置，将 Module 设置为 `entry`。
5. 顶部设备下拉框选择正在运行的模拟器。
6. 点击三角形 **Run**，不要选择只执行 `assembleHap` 的配置。

Run 会依次执行：

```text
构建 HAP -> 安装到模拟器 -> 启动 EntryAbility -> 显示应用页面
```

### 3.4 为什么不优先使用 Previewer

本项目依赖 `libentry.so`、文件选择器、GGUF 文件访问和 Native 推理。Previewer 适合检查简单静态布局，但不一定能加载这些设备能力。因此团队验收完整 UI 和交互时，应以模拟器或真机运行结果为准。

## 4. 准备测试模型

### 4.1 推荐模型大小

首次联调建议使用较小的 GGUF，例如约 `300 MB` 到 `500 MB` 的 `0.5B Q4` 模型。这样导入和加载更快，也不容易耗尽模拟器空间。

应用导入 GGUF 时会把源文件复制到应用私有目录。因此设备至少需要：

```text
源 GGUF 大小 + 应用内副本大小 + 约 1 GB 系统和部署余量
```

例如导入一个 `2 GB` 模型，设备上通常需要额外准备超过 `3 GB` 的可用空间。空间不足时可能产生不完整副本，应用不会把它显示为可用模型。

### 4.2 把 GGUF 放入模拟器

可以使用 DevEco Studio 的设备文件管理工具，把 `.gguf` 放入模拟器的“下载”目录。也可以使用 DevEco SDK 自带的 `hdc.exe`：

```powershell
$hdc = '<DevEco SDK目录>\default\openharmony\toolchains\hdc.exe'
& $hdc list targets
& $hdc file send 'D:\Models\qwen-model.gguf' '/data/service/el2/100/hmdfs/account/files/Docs/Download/qwen-model.gguf'
```

`hdc` 未加入系统 `PATH` 时，直接输入 `hdc` 会提示“无法识别为 cmdlet”。此时使用上面这种完整路径调用即可。

## 5. 页面使用方法

### 5.1 模型页

1. 点击底部“模型”。
2. 点击右上角“导入 GGUF”。
3. 在文件选择器中选择准备好的 `.gguf`。
4. 等待复制和元数据解析完成。
5. 新模型卡片出现后，点击“加载模型”。

模型卡片会显示架构、量化类型、参数量、上下文长度、Tokenizer 和文件大小。同一时间只应使用一个已加载模型；切换模型前，当前阶段建议先点“卸载”，再加载另一张卡片。

这里的“卸载”只是把模型从运行内存中释放，模型文件和卡片仍会保留，并不是删除模型。

### 5.2 聊天页

模型加载成功后：

1. 切换到底部“聊天”。
2. 在输入框输入消息。
3. 点击“发送”，回复会逐 Token 显示。
4. 生成过程中可以点击“停止”。

没有加载模型时，聊天页只会显示前往模型管理的引导，这是正常状态。

### 5.3 服务页

服务页用于启动本机 OpenAI 兼容接口：

- “启动服务 / 停止服务”：控制本地 HTTP 服务；
- “健康检查”：请求 `/health`；
- “模型列表”：请求 `/v1/models`；
- “聊天接口”：测试 `/v1/chat/completions`；
- “补全接口”：测试 `/v1/completions`。

当前默认监听 `127.0.0.1:8080`，主要用于应用内和开发调试。使用推理接口前应先加载模型。

### 5.4 设置页

使用 `-` 和 `+` 修改参数，点击“保存设置”持久化：

- `Context length`：一次推理能够使用的上下文容量；
- `Threads`：CPU 推理线程数；
- `Max tokens`：单次最多生成多少 Token；
- `Temperature`：生成随机性；
- `Top-K / Top-P`：候选 Token 的采样范围；
- `Repeat penalty`：重复内容惩罚。

`Context length` 和 `Threads` 属于模型加载配置。修改并保存后，需要卸载并重新加载模型才会应用到新的模型实例。

## 6. 提交前最小检查

目前项目仍在快速开发，建议每次提交前至少完成以下检查：

- 执行一次 `Build Hap(s)`，确认出现 `BUILD SUCCESSFUL`；
- 在模拟器中点击 Run，确认应用能启动；
- 依次切换聊天、模型、服务、设置四个页面；
- 如果改了模型功能，检查导入、加载、卸载；
- 如果改了设置，检查数值变化、保存以及重新进入页面；
- 如果改了聊天，使用小模型发送一条短消息并尝试停止生成。

构建检查能发现语法、类型、资源引用和 Native 编译错误；模拟器冒烟检查能发现页面无法启动、按钮无响应等运行时问题。两者不能互相替代。

## 7. 常见问题

### 构建成功，但没有看到 UI

你执行的是 `Build Hap(s)` 或 `assembleHap`，它只打包。请选择模拟器和 `entry` 后点击 Run。

### 顶部 Module 是 `None` 或列表为空

确认打开的是项目根目录，然后等待工程同步。仍为空时进入 `Run -> Edit Configurations`，新建 HarmonyOS 应用配置并选择 `entry`。

### `Invalid value of DEVECO_SDK_HOME`

环境变量指向了不存在或版本不匹配的 SDK。优先让 DevEco 使用安装目录中的一体化 SDK；修改后停止 Hvigor Daemon，再重新同步项目。

### `Cannot find the corresponding SDK version`

检查 `DEVECO_SDK_HOME` 和 DevEco 自定义 SDK 路径。它们必须指向实际包含项目所需版本的 SDK，不要保留旧的无效路径。

### `No space left on device`

模拟器 `/data` 已满，HAP 无法部署，GGUF 也无法继续复制。删除无用下载文件或失败产生的不完整副本，或者创建存储更大的模拟器。不要反复点击导入，否则旧版本可能留下更多半成品。

查看空间：

```powershell
& $hdc shell df -h /data
```

### `hdc` 无法识别

`hdc.exe` 没有加入 `PATH`。使用 DevEco SDK 下 `toolchains\hdc.exe` 的完整路径，或把该目录加入用户 `PATH` 后重开 PowerShell。

### 模拟器快照启动失败

在 Device Manager 中停止模拟器，然后选择 Cold Boot（冷启动）。快照只是加速启动的缓存，冷启动不会修改项目代码。

### OHPM 为什么又在下载

首次同步、依赖缓存缺失、清理缓存或切换 SDK 后，DevEco 会重新解析和下载依赖。依赖完整后，后续通常会复用缓存。

## 8. 出现问题时提供什么信息

向队友反馈问题时，建议同时提供：

- DevEco Studio 和 HarmonyOS SDK 版本；
- 使用模拟器还是真机；
- 完整错误日志，不要只截最后一行；
- 操作步骤，例如“导入完成后点击加载”；
- GGUF 文件名、大小和量化类型；
- `df -h /data` 的剩余空间（涉及部署或导入时）。

这些信息通常足以区分环境问题、空间问题、UI 状态问题和 Native 模型兼容问题。
