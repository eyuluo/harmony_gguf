import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { taskpool } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import testNapi from 'libentry.so';
import { ServerInfo, GenerateStats, GenerateError } from 'libentry.so';

const DOMAIN = 0x0000;
const TAG = 'demo';
const BASE_URL = 'http://127.0.0.1:8080';

interface GenerationUsage {
  prompt_tokens: number;
  completion_tokens: number;
  total_tokens: number;
  time_to_first_token_ms: number;
  tokens_per_second: number;
}

interface GenerationResponse {
  usage: GenerationUsage;
}

interface ChatMessage {
  role: string;
  content: string;
}

// 后台并发任务：解析元数据 + 加载模型，返回结果字符串
@Concurrent
function loadModelTask(path: string): string {
  const meta = testNapi.parseGgufMetadata(path);
  const modelId = testNapi.loadModel(path, { contextLength: 4096, threads: 4, parallel: 2 });
  return `${modelId}|${meta.architecture}|${meta.quantization}|${meta.parameters}|${meta.contextLength}`;
}

@Entry
@Component
struct Index {
  @State status: string = '未加载';
  @State metaText: string = '';
  @State modelId: number = 0;
  @State input: string = '你好';
  @State genStatsText: string = '';
  @State serverInfo: string = '服务未启动';
  @State serveStatsText: string = '';
  @State log: string = '';
  private loading: boolean = false;
  private httpRequest: http.HttpRequest = http.createHttp();
  private activeRequestId: number = 0;

  build() {
    Column() {
      Text('Harmony-GGUF Demo')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 8 })

      Text(this.status)
        .fontSize(14)
        .margin({ bottom: 4 })

      Text(this.metaText)
        .fontSize(12)
        .margin({ bottom: 8 })

      Row() {
        Button('选择模型')
          .enabled(!this.loading)
          .onClick(() => this.selectModel())
        Button('卸载')
          .onClick(() => this.unload())
      }
      .margin({ bottom: 8 })

      Text('直接生成（NAPI）')
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 4 })

      TextInput({ text: this.input })
        .onChange((value: string) => {
          this.input = value;
        })
        .margin({ bottom: 4 })

      Row() {
        Button('发送')
          .onClick(() => this.generate())
        Button('停止')
          .onClick(() => this.stopGeneration())
      }
      .margin({ bottom: 4 })

      Text(this.genStatsText)
        .fontSize(12)
        .fontColor('#1F6B3E')
        .margin({ bottom: 8 })

      Text('Serve 服务')
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 4 })

      Text(this.serverInfo)
        .fontSize(12)
        .margin({ bottom: 4 })

      Row() {
        Button('启动服务')
          .onClick(() => this.startServe())
        Button('停止服务')
          .onClick(() => this.stopServe())
      }
      .margin({ bottom: 4 })

      Row() {
        Button('GET /health')
          .onClick(() => this.testHealth())
        Button('GET /v1/models')
          .onClick(() => this.testModels())
      }
      .margin({ bottom: 4 })

      Row() {
        Button('POST /v1/chat')
          .onClick(() => this.testChat())
        Button('POST /v1/completions')
          .onClick(() => this.testCompletions())
      }
      .margin({ bottom: 4 })

      Text(this.serveStatsText)
        .fontSize(12)
        .fontColor('#1F6B3E')
        .margin({ bottom: 4 })

      Row() {
        Button('清空日志')
          .onClick(() => {
            this.log = '';
          })
      }
      .margin({ bottom: 8 })

      Scroll() {
        Text(this.log)
          .fontSize(12)
          .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .backgroundColor('#F1F3F5')
      .padding(8)
    }
    .width('100%')
    .height('100%')
    .padding(16)
  }

  async selectModel() {
    if (this.loading) {
      return;
    }
    this.loading = true;
    try {
      const context = this.getUIContext().getHostContext()!;
      const documentPicker = new picker.DocumentViewPicker(context);
      const uris = await documentPicker.select({
        maxSelectNumber: 1,
        fileSuffixFilters: ['.gguf']
      });
      if (uris.length === 0) {
        return;
      }
      const uri = uris[0];
      hilog.info(DOMAIN, TAG, 'selected uri: %{public}s', uri);

      const modelsDir = context.filesDir + '/models';
      try {
        fileIo.mkdirSync(modelsDir);
      } catch (e) {
        // 目录已存在，忽略
      }
      const dstPath = modelsDir + '/model.gguf';
      this.status = '拷贝模型中...';

      // 异步拷贝（fd 方式，不阻塞主线程）
      const srcFile = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      const dstFile = fileIo.openSync(dstPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      await fileIo.copyFile(srcFile.fd, dstFile.fd);
      fileIo.closeSync(srcFile);
      fileIo.closeSync(dstFile);
      hilog.info(DOMAIN, TAG, 'copied to: %{public}s', dstPath);

      // 后台并发加载模型（不阻塞主线程）
      this.status = '加载模型中...';
      const result = await taskpool.execute(loadModelTask, dstPath) as string;
      const parts = result.split('|');
      this.modelId = Number(parts[0]);
      this.metaText = `架构:${parts[1]} 量化:${parts[2]} 参数:${parts[3]} 上下文:${parts[4]}`;
      this.status = `已加载 (modelId=${this.modelId})`;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'selectModel failed: %{public}s', String(e));
      this.status = '加载失败: ' + String(e);
    } finally {
      this.loading = false;
    }
  }

  unload() {
    if (this.modelId > 0) {
      testNapi.unloadModel(this.modelId);
      this.modelId = 0;
      this.status = '已卸载';
    }
  }

  generate() {
    this.genStatsText = '';
    try {
      this.activeRequestId = testNapi.generate(this.input, { maxTokens: 128, temperature: 0.7 }, (event, data) => {
        if (event === 'done' || event === 'stopped') {
          const d = data as GenerateStats;
          this.genStatsText = `prompt_tokens: ${d.promptTokens}  completion_tokens: ${d.generatedTokens}  ttft: ${d.ttftMs.toFixed(0)} ms  tps: ${d.tokensPerSecond.toFixed(1)}`;
          this.appendLog(`<<< ${event} ${this.genStatsText}`);
        } else if (event === 'error') {
          const d = data as GenerateError;
          this.appendLog(`<<< error(${d.code}): ${d.message}`);
        }
      });
      this.appendLog(`>>> NAPI generate (id=${this.activeRequestId})`);
    } catch (e) {
      this.appendLog('生成失败: ' + String(e));
    }
  }

  stopGeneration() {
    if (this.activeRequestId > 0) {
      testNapi.stopGenerate(this.activeRequestId);
      this.appendLog(`>>> stopGenerate (id=${this.activeRequestId})`);
    }
  }

  startServe() {
    try {
      testNapi.startServer({ host: '0.0.0.0', port: 8080 });
      this.refreshServerStatus();
      this.appendLog('>>> 启动服务');
      this.appendLog(this.serverInfo);
    } catch (e) {
      this.appendLog('>>> 启动失败: ' + String(e));
    }
  }

  stopServe() {
    try {
      testNapi.stopServer();
    } catch (e) {
      this.appendLog('>>> 停止失败: ' + String(e));
    }
    this.refreshServerStatus();
    this.appendLog('>>> 停止服务');
    this.appendLog(this.serverInfo);
  }

  refreshServerStatus() {
    const info = testNapi.getServerStatus() as ServerInfo;
    if (info.running) {
      this.serverInfo = `运行中: http://${info.host}:${info.port}`;
      if (info.lanAddress.length > 0) {
        this.serverInfo += `  局域网: ${info.lanAddress}`;
      }
    } else {
      this.serverInfo = '服务未启动';
    }
  }

  testHealth() {
    this.appendLog('>>> GET /health');
    this.httpRequest.request(`${BASE_URL}/health`, {
      method: http.RequestMethod.GET,
      connectTimeout: 3000,
      readTimeout: 5000,
    }, (err: BusinessError, data: http.HttpResponse) => {
      if (err) {
        this.appendLog(`<<< 错误(${err.code}): ${err.message}`);
      } else {
        this.appendLog(`<<< ${data.responseCode} ${data.result as string}`);
      }
    });
  }

  testModels() {
    this.appendLog('>>> GET /v1/models');
    this.httpRequest.request(`${BASE_URL}/v1/models`, {
      method: http.RequestMethod.GET,
      connectTimeout: 3000,
      readTimeout: 5000,
    }, (err: BusinessError, data: http.HttpResponse) => {
      if (err) {
        this.appendLog(`<<< 错误(${err.code}): ${err.message}`);
      } else {
        this.appendLog(`<<< ${data.responseCode} ${data.result as string}`);
      }
    });
  }

  testChat() {
    const messages: ChatMessage[] = [{ role: 'user', content: '用一句话介绍你自己' }];
    const body = JSON.stringify({ messages: messages, max_tokens: 64, stream: false });
    this.appendLog('>>> POST /v1/chat/completions');
    this.httpRequest.request(`${BASE_URL}/v1/chat/completions`, {
      method: http.RequestMethod.POST,
      header: { 'Content-Type': 'application/json' },
      extraData: body,
      connectTimeout: 3000,
      readTimeout: 60000,
    }, (err: BusinessError, data: http.HttpResponse) => {
      if (err) {
        this.appendLog(`<<< 错误(${err.code}): ${err.message}`);
      } else {
        const result = data.result as string;
        this.appendLog(`<<< ${data.responseCode} ${result}`);
        this.parseServeStats(result);
      }
    });
  }

  testCompletions() {
    const body = JSON.stringify({
      prompt: '用一句话介绍你自己',
      max_tokens: 64,
      stream: false
    });
    this.appendLog('>>> POST /v1/completions');
    this.httpRequest.request(`${BASE_URL}/v1/completions`, {
      method: http.RequestMethod.POST,
      header: { 'Content-Type': 'application/json' },
      extraData: body,
      connectTimeout: 3000,
      readTimeout: 60000,
    }, (err: BusinessError, data: http.HttpResponse) => {
      if (err) {
        this.appendLog(`<<< 错误(${err.code}): ${err.message}`);
      } else {
        const result = data.result as string;
        this.appendLog(`<<< ${data.responseCode} ${result}`);
        this.parseServeStats(result);
      }
    });
  }

  parseServeStats(result: string) {
    try {
      const resp = JSON.parse(result) as GenerationResponse;
      const u = resp.usage;
      this.serveStatsText = `prompt_tokens: ${u.prompt_tokens}  completion_tokens: ${u.completion_tokens}  ttft: ${u.time_to_first_token_ms.toFixed(0)} ms  tps: ${u.tokens_per_second.toFixed(1)}`;
    } catch (e) {
      this.serveStatsText = '统计解析失败';
    }
  }

  appendLog(line: string) {
    this.log = this.log + line + '\n';
  }
}
