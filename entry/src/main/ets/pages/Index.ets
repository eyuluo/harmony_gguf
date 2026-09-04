import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { taskpool } from '@kit.ArkTS';
import testNapi from 'libentry.so';
import { GenerateError, GenerateStats, TokenData } from 'libentry.so';

const DOMAIN = 0x0000;
const TAG = 'demo';

// 后台并发任务：解析元数据 + 加载模型，返回结果字符串
@Concurrent
function loadModelTask(path: string): string {
  const meta = testNapi.parseGgufMetadata(path);
  const modelId = testNapi.loadModel(path, { contextLength: 4096, threads: 4 });
  return `${modelId}|${meta.architecture}|${meta.quantization}|${meta.parameters}|${meta.contextLength}`;
}

@Entry
@Component
struct Index {
  @State status: string = '未加载';
  @State metaText: string = '';
  @State input: string = '你好';
  @State output: string = '';
  @State modelId: number = 0;
  private loading: boolean = false;

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

      TextInput({ text: this.input })
        .onChange((value: string) => {
          this.input = value;
        })
        .margin({ bottom: 8 })

      Row() {
        Button('发送')
          .onClick(() => this.generate())
        Button('停止')
          .onClick(() => testNapi.stopGenerate())
      }
      .margin({ bottom: 8 })

      Scroll() {
        Text(this.output)
          .fontSize(14)
      }
      .layoutWeight(1)
      .width('100%')
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
      const context = getContext(this);
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
      this.output = '';
    }
  }

  generate() {
    this.output = '';
    testNapi.generate(this.input, { maxTokens: 128, temperature: 0.7 }, (event, data) => {
      if (event === 'token') {
        const d = data as TokenData;
        this.output += d.text;
      } else if (event === 'done') {
        const d = data as GenerateStats;
        this.status = `完成: ${d.generatedTokens} tokens, ${d.tokensPerSecond.toFixed(1)} t/s`;
      } else if (event === 'error') {
        const d = data as GenerateError;
        this.status = `错误(${d.code}): ${d.message}`;
      }
    });
  }
}
