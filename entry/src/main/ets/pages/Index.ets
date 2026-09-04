import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import testNapi from 'libentry.so';
import { GenerateError, GenerateStats, TokenData } from 'libentry.so';

const DOMAIN = 0x0000;
const TAG = 'demo';

@Entry
@Component
struct Index {
  @State status: string = '未加载';
  @State metaText: string = '';
  @State input: string = '你好';
  @State output: string = '';
  @State modelId: number = 0;

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

      // 拷贝到沙箱 models/ 目录（用 fd 方式，uri 需先 open）
      const modelsDir = context.filesDir + '/models';
      try {
        fileIo.mkdirSync(modelsDir);
      } catch (e) {
        // 目录已存在，忽略
      }
      const dstPath = modelsDir + '/model.gguf';
      this.status = '拷贝模型中...';

      const srcFile = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      const dstFile = fileIo.openSync(dstPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.copyFileSync(srcFile.fd, dstFile.fd);
      fileIo.closeSync(srcFile);
      fileIo.closeSync(dstFile);
      hilog.info(DOMAIN, TAG, 'copied to: %{public}s', dstPath);

      // 解析元数据 + 加载
      const meta = testNapi.parseGgufMetadata(dstPath);
      this.metaText = `架构:${meta.architecture} 量化:${meta.quantization} 参数:${meta.parameters} 上下文:${meta.contextLength}`;
      this.modelId = testNapi.loadModel(dstPath, { contextLength: 4096, threads: 4 });
      this.status = `已加载 (modelId=${this.modelId})`;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'selectModel failed: %{public}s', String(e));
      this.status = '加载失败: ' + String(e);
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
