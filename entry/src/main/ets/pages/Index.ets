import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { taskpool } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import testNapi from 'libentry.so';
import { ServerInfo, GenerateStats, GenerateError, TokenData } from 'libentry.so';
import { SettingsStore, InferenceSettings } from '../service/SettingsStore';
import { ModelStore, StoredModelInfo } from '../service/ModelStore';

const DOMAIN = 0x0000;
const TAG = 'HarmonyGGUF';
const BASE_URL = 'http://127.0.0.1:8080';

interface ChatMessage { role: string; content: string; }

@Concurrent
function parseModelTask(path: string): string {
  const meta = testNapi.parseGgufMetadata(path);
  return `${meta.architecture}|${meta.quantization}|${meta.parameters}|${meta.contextLength}|${meta.tokenizer}|${meta.fileSize}`;
}

@Concurrent
function loadModelTask(path: string, contextLength: number, threads: number): string {
  const meta = testNapi.parseGgufMetadata(path);
  const modelId = testNapi.loadModel(path, { contextLength: contextLength, threads: threads, parallel: 2 });
  return `${modelId}|${meta.architecture}|${meta.quantization}|${meta.parameters}|${meta.contextLength}|${meta.tokenizer}|${meta.fileSize}`;
}

@Component
struct SettingStepper {
  @Link value: number;
  label: string = '';
  min: number = 0;
  max: number = 100;
  step: number = 1;
  decimalPlaces: number = 0;

  private adjust(delta: number): void {
    const boundedValue = Math.min(this.max, Math.max(this.min, this.value + delta));
    this.value = Number(boundedValue.toFixed(this.decimalPlaces));
  }

  private displayValue(): string {
    return this.decimalPlaces > 0 ? this.value.toFixed(this.decimalPlaces) : String(this.value);
  }

  build() {
    Row() {
      Text(this.label)
        .fontSize(14)
        .fontColor('#A0A0A0')
        .layoutWeight(1)
      Row() {
        Button('−')
          .width(40)
          .height(36)
          .fontSize(19)
          .enabled(this.value > this.min)
          .onClick(() => { this.adjust(-this.step); })
          .backgroundColor('#2C2D33')
          .fontColor('#B9B1FF')
          .borderRadius(8)
        Text(this.displayValue())
          .width(68)
          .textAlign(TextAlign.Center)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontFeature('"tnum" 1')
          .fontColor('#FFFFFF')
        Button('+')
          .width(40)
          .height(36)
          .fontSize(19)
          .enabled(this.value < this.max)
          .onClick(() => { this.adjust(this.step); })
          .backgroundColor('#2C2D33')
          .fontColor('#B9B1FF')
          .borderRadius(8)
      }
      .padding(3)
      .backgroundColor('#1A1B20')
      .borderRadius(8)
      .borderWidth(1)
      .borderColor('#2C2D33')
    }
    .width('100%')
    .padding({ left: 16, right: 12, top: 9, bottom: 9 })
  }
}

@Entry
@Component
struct Index {
  @State activeTab: number = 0;
  @State status: string = '未选择模型';
  @State loading: boolean = false;
  @State modelId: number = 0;
  @State modelInfo: StoredModelInfo | null = null;
  @State models: StoredModelInfo[] = [];
  @State activeModelPath: string = '';
  @State loadingModelPath: string = '';
  @State input: string = '';
  @State messages: ChatMessage[] = [];
  @State generating: boolean = false;
  @State statsText: string = '';
  @State serverInfo: string = '服务未启动';
  @State serverRunning: boolean = false;
  @State serverLog: string[] = [];
  @State contextLength: number = 0;
  @State maxTokens: number = 512;
  @State threads: number = 0;
  @State temperature: number = 0.8;
  @State topK: number = 40;
  @State topP: number = 0.95;
  @State repeatPenalty: number = 1.0;
  @State settingsStatus: string = '';
  private activeRequestId: number = 0;
  private httpRequest: http.HttpRequest = http.createHttp();

  aboutToAppear(): void {
    this.restoreAppState();
  }

  async restoreAppState(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context) {
      return;
    }
    try {
      await SettingsStore.getInstance().init(context);
      const savedSettings = SettingsStore.getInstance().getSettings();
      this.contextLength = savedSettings.contextLength;
      this.maxTokens = savedSettings.maxTokens;
      this.threads = savedSettings.threads;
      this.temperature = savedSettings.temperature;
      this.topK = savedSettings.topK;
      this.topP = savedSettings.topP;
      this.repeatPenalty = savedSettings.repeatPenalty;
      await ModelStore.getInstance().init(context);
      const storedModels = ModelStore.getInstance().getModels();
      const availableModels: StoredModelInfo[] = [];
      for (const storedModel of storedModels) {
        if (this.isCompleteModelFile(storedModel.path, storedModel.fileSize)) {
          availableModels.push(storedModel);
        }
      }

      // 找回已复制成功、但因加载或索引写入失败而没有显示的模型。
      const modelsDir = context.filesDir + '/models';
      if (fileIo.accessSync(modelsDir)) {
        const fileNames = fileIo.listFileSync(modelsDir);
        for (const fileName of fileNames) {
          if (!fileName.toLowerCase().endsWith('.gguf')) {
            continue;
          }
          const path = modelsDir + '/' + fileName;
          if (this.containsModelPath(availableModels, path)) {
            continue;
          }
          try {
            const parts = (await taskpool.execute(parseModelTask, path) as string).split('|');
            const expectedSize = Number(parts[5]);
            if (!this.isCompleteModelFile(path, expectedSize)) {
              hilog.warn(DOMAIN, TAG, 'skip incomplete model file: %{public}s', path);
              continue;
            }
            const recoveredModel: StoredModelInfo = {
              path: path,
              name: fileName === 'model.gguf' ? '本地 GGUF 模型' : `已恢复模型 ${availableModels.length + 1}`,
              architecture: parts[0],
              quantization: parts[1],
              parameters: parts[2],
              contextLength: Number(parts[3]),
              tokenizer: parts[4],
              fileSize: expectedSize
            };
            availableModels.push(recoveredModel);
            await ModelStore.getInstance().saveModel(recoveredModel);
          } catch (error) {
            hilog.warn(DOMAIN, TAG, 'skip unreadable model file %{public}s: %{public}s', path, String(error));
          }
        }
      }

      this.models = availableModels;
      if (availableModels.length > 0) {
        this.status = availableModels.length > storedModels.length ? '已恢复本地模型，尚未加载' : '模型已保存，尚未加载';
      } else if (storedModels.length > 0) {
        await ModelStore.getInstance().clearModel();
        this.status = '未选择模型';
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, '恢复应用状态失败: %{public}s', String(error));
      this.status = '读取本地数据失败';
    }
  }

  build() {
    Column() {
      this.header()
      if (this.activeTab === 0) this.chatPage();
      else if (this.activeTab === 1) this.modelsPage();
      else if (this.activeTab === 2) this.servePage();
      else this.settingsPage();
      this.bottomNav()
    }.width('100%').height('100%').backgroundColor('#121212')
  }

  @Builder header() {
    Row() {
      Column() {
        Row() {
          Image($r('app.media.ic_ai_chip'))
            .width(24)
            .height(24)
            .margin({ right: 8 })
          Text('Harmony-GGUF')
            .fontSize(21)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
        }
        .alignItems(VerticalAlign.Center)
        Text(this.modelInfo === null ? '本地离线推理器' : this.modelInfo.name)
          .fontSize(11)
          .fontColor('#5F6068')
          .margin({ left: 32, top: 3 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Row() {
        Text('●')
          .fontSize(9)
          .fontColor(this.modelId > 0 ? '#78D891' : this.loading ? '#B9B1FF' : '#85858D')
          .margin({ right: 6 })
        Text(this.modelId > 0 ? '已加载' : this.loading ? '加载中' : '未加载')
          .fontSize(12)
          .fontColor('#C2C2C8')
      }
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .backgroundColor('#2C2D33')
      .borderRadius(12)
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 24, bottom: 16 })
    .backgroundColor('#18191D')
    .borderWidth({ bottom: 1 })
    .borderColor('#2C2D33')
  }

  @Builder chatPage() {
    Column() {
      if (this.modelId === 0) {
        Column() {
          Image($r('app.media.ic_model'))
            .width(64)
            .height(64)
            .fillColor('#7B61FF')
            .margin({ bottom: 22 })
          Text('先选择一个本地模型')
            .fontSize(22)
            .fontColor('#FFFFFF')
          Text('导入 GGUF 文件后，就可以开始离线对话')
            .fontSize(14)
            .fontColor('#6C6C6C')
            .margin({ top: 8, bottom: 20 })
          Button('打开模型管理')
            .onClick(() => this.activeTab = 1)
            .backgroundColor('#6C5CE7')
            .fontColor('#FFFFFF')
            .borderRadius(12)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column() {
            if (this.messages.length === 0) {
              Text('今天想聊些什么？')
                .fontSize(18)
                .fontColor('#A0A0A0')
                .margin({ top: 36, bottom: 20 })
            }
            ForEach(this.messages, (message: ChatMessage) => {
              Row() {
                Text(message.role === 'user' ? '你' : 'AI')
                  .fontSize(12)
                  .fontColor(message.role === 'user' ? '#B9B1FF' : '#78D891')
                  .width(30)
                Text(message.content)
                  .fontSize(15)
                  .fontColor('#E6E6E6')
                  .layoutWeight(1)
              }
              .alignItems(VerticalAlign.Top)
              .margin({ bottom: 18 })
            }, (message: ChatMessage) => message.role + message.content)
          }
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 8, bottom: 12 })
        .layoutWeight(1)
      }
      if (this.statsText.length > 0) {
        Text(this.statsText)
          .fontSize(11)
          .fontColor('#6C6C6C')
          .padding({ left: 20, right: 20, bottom: 8 })
      }
      Row() {
        TextInput({ placeholder: '输入消息...', text: this.input })
          .layoutWeight(1)
          .onChange((value: string) => this.input = value)
          .backgroundColor('#1E1F24')
          .fontColor('#F5F5F5')
          .placeholderColor('#99FFFFFF')
          .borderWidth(1)
          .borderColor('#2C2D33')
          .borderRadius(12)
        Button(this.generating ? '停止' : '发送')
          .enabled(this.generating || this.input.trim().length > 0)
          .onClick(() => this.generating ? this.stopGeneration() : this.generate())
          .margin({ left: 8 })
          .backgroundColor(this.generating || this.input.trim().length > 0 ? '#8A74FF' : '#35343F')
          .fontColor(this.generating || this.input.trim().length > 0 ? '#FFFFFF' : '#8F8D98')
          .borderRadius(12)
      }
      .padding({ left: 16, right: 16, top: 10, bottom: 14 })
      .backgroundColor('#18191D')
    }.layoutWeight(1).width('100%')
  }

  @Builder modelsPage() {
    Scroll() { Column() {
      Row() {
        Text('模型').fontSize(24).fontWeight(FontWeight.Bold).fontColor('#FFFFFF').layoutWeight(1)
        Button('+  导入 GGUF')
          .onClick(() => this.selectModel())
          .backgroundColor('#6C5CE7')
          .fontColor('#FFFFFF')
          .borderRadius(12)
      }
      .width('100%')
      .margin({ bottom: 16 })
      if (this.loading && this.models.length === 0) this.infoBlock('正在加载模型', '解析元数据并准备推理引擎，请稍候');
      else if (this.models.length === 0) this.infoBlock('还没有导入模型', '选择一个本地 .gguf 文件开始');
      else {
        ForEach(this.models, (model: StoredModelInfo) => {
          this.modelCard(model)
        }, (model: StoredModelInfo) => model.path)
      }
    }.width('100%').padding({ left: 20, right: 20, top: 22, bottom: 20 }) }.layoutWeight(1).width('100%')
  }

  @Builder servePage() {
    Scroll() {
      Column() {
        Text('本地服务').fontSize(24).fontWeight(FontWeight.Bold).fontColor('#FFFFFF').alignSelf(ItemAlign.Start)
        Text('OpenAI 兼容 API，默认仅监听本机').fontSize(13).fontColor('#6C6C6C').margin({ top: 6, bottom: 18 })
        Column() {
          Row() {
            Row() {
              Text('●')
                .fontSize(10)
                .fontColor(this.serverRunning ? '#78D891' : '#6C6C6C')
                .margin({ right: 8 })
              Text(this.serverRunning ? '运行中' : '未运行')
                .fontSize(18)
                .fontColor(this.serverRunning ? '#78D891' : '#A0A0A0')
            }
            .layoutWeight(1)
            Button(this.serverRunning ? '停止服务' : '启动服务')
              .onClick(() => this.serverRunning ? this.stopServe() : this.startServe())
              .backgroundColor(this.serverRunning ? '#2C2D33' : '#6C5CE7')
              .fontColor('#FFFFFF')
              .borderRadius(12)
          }
          Text(this.serverInfo).fontSize(13).fontColor('#A0A0A0').margin({ top: 12 })
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#1E1F24')
        .borderWidth(1)
        .borderColor('#2C2D33')
        .borderRadius(16)
        .margin({ bottom: 22 })
        Text('开发者调试').fontSize(16).fontColor('#FFFFFF').alignSelf(ItemAlign.Start).margin({ bottom: 10 })
        Row() {
          this.debugButton('健康检查', () => { this.testHealth(); })
          this.debugButton('模型列表', () => { this.testModels(); })
        }
        Row() {
          this.debugButton('聊天接口', () => { this.testChat(); })
          this.debugButton('补全接口', () => { this.testCompletions(); })
        }
        .margin({ top: 8 })
        Text('最近调用').fontSize(16).fontColor('#FFFFFF').alignSelf(ItemAlign.Start).margin({ top: 22, bottom: 8 })
        ForEach(this.serverLog, (line: string) => Text(line).fontSize(12).fontColor('#6C6C6C').margin({ bottom: 5 }))
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 22, bottom: 20 })
    }
    .layoutWeight(1)
    .width('100%')
  }

  @Builder settingsPage() {
    Scroll() {
      Column() {
        Text('设置')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .alignSelf(ItemAlign.Start)
          .margin({ bottom: 18 })
        Text('Context length 和 Threads 在下次加载模型时生效，其余参数在下次生成时生效。')
          .fontSize(12)
          .fontColor('#6C6C6C')
          .margin({ bottom: 18 })
        Text('模型参数')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor('#A0A0A0')
          .alignSelf(ItemAlign.Start)
          .margin({ bottom: 4 })
        SettingStepper({ label: 'Context length', value: $contextLength, min: 0, max: 32768, step: 256 })
        SettingStepper({ label: 'Threads', value: $threads, min: 0, max: 32, step: 1 })
        Text('生成参数')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor('#A0A0A0')
          .alignSelf(ItemAlign.Start)
          .margin({ top: 18, bottom: 4 })
        SettingStepper({ label: 'Max tokens', value: $maxTokens, min: 1, max: 8192, step: 64 })
        SettingStepper({ label: 'Temperature', value: $temperature, min: 0, max: 2, step: 0.05,
          decimalPlaces: 2 })
        SettingStepper({ label: 'Top-K', value: $topK, min: 0, max: 200, step: 1 })
        SettingStepper({ label: 'Top-P', value: $topP, min: 0, max: 1, step: 0.01, decimalPlaces: 2 })
        SettingStepper({ label: 'Repeat penalty', value: $repeatPenalty, min: 0.5, max: 2, step: 0.05,
          decimalPlaces: 2 })
        Button('保存设置')
          .onClick(() => this.saveSettings())
          .width('100%')
          .backgroundColor('#6C5CE7')
          .fontColor('#FFFFFF')
          .borderRadius(12)
          .margin({ top: 18 })
        if (this.settingsStatus.length > 0) {
          Text(this.settingsStatus)
            .fontSize(12)
            .fontColor(this.settingsStatus === '设置已保存' ? '#8ED081' : '#E58C8C')
            .margin({ top: 8 })
        }
        Blank().height(24)
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 22, bottom: 20 })
    }
    .layoutWeight(1)
    .width('100%')
  }

  @Builder infoBlock(title: string, subtitle: string) {
    Column() {
      Text(title).fontSize(17).fontColor('#FFFFFF')
      Text(subtitle).fontSize(13).fontColor('#6C6C6C').margin({ top: 7 })
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#1E1F24')
    .borderWidth(1)
    .borderColor('#2C2D33')
    .borderRadius(16)
  }

  @Builder modelTag(value: string) {
    Text(value)
      .fontSize(11)
      .fontColor('#6C6C6C')
      .backgroundColor('#25262B')
      .borderRadius(8)
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .margin({ right: 6 })
  }

  @Builder modelCard(model: StoredModelInfo) {
    Column() {
      Text(model.name).fontSize(18).fontColor('#FFFFFF')
      Row() {
        this.modelTag(model.architecture)
        this.modelTag(model.quantization)
        this.modelTag(model.parameters)
      }
      .margin({ top: 12, bottom: 12 })
      Text(`上下文 ${model.contextLength} · tokenizer ${model.tokenizer} · ${this.formatSize(model.fileSize)}`)
        .fontSize(12)
        .fontColor('#6C6C6C')
        .margin({ bottom: 16 })
      Row() {
        if (this.activeModelPath === model.path && this.modelId > 0) {
          Row() {
            Text('●').fontSize(9).fontColor('#78D891').margin({ right: 6 })
            Text('已加载').fontSize(12).fontWeight(FontWeight.Medium).fontColor('#A8DDB5')
          }
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor('#25352A')
          .borderRadius(12)
        } else {
          Button(this.loadingModelPath === model.path ? '加载中' : '加载模型')
            .enabled(!this.loading)
            .onClick(() => { this.loadModel(model); })
            .backgroundColor('#6C5CE7')
            .fontColor('#FFFFFF')
            .borderRadius(12)
        }
        Button('卸载')
          .enabled(this.activeModelPath === model.path && this.modelId > 0 && !this.loading)
          .onClick(() => { this.unload(); })
          .margin({ left: 10 })
          .backgroundColor('#2C2D33')
          .fontColor('#A0A0A0')
          .borderRadius(12)
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#1E1F24')
    .borderWidth(1)
    .borderColor(this.activeModelPath === model.path && this.modelId > 0 ? '#4D465F' : '#2C2D33')
    .borderRadius(16)
    .margin({ bottom: 12 })
  }

  @Builder debugButton(label: string, action: () => void) {
    Button(label)
      .layoutWeight(1)
      .onClick(action)
      .backgroundColor('#1E1F24')
      .fontColor('#B9B1FF')
      .borderWidth(1)
      .borderColor('#2C2D33')
      .borderRadius(12)
  }

  @Builder bottomNav() {
    Row() {
      this.navItem($r('app.media.ic_chat'), '聊天', 0)
      this.navItem($r('app.media.ic_model'), '模型', 1)
      this.navItem($r('app.media.ic_server'), '服务', 2)
      this.navItem($r('app.media.ic_settings'), '设置', 3)
    }
    .width('100%')
    .height(72)
    .backgroundColor('#18191D')
    .borderWidth({ top: 1 })
    .borderColor('#2C2D33')
  }

  @Builder navItem(icon: Resource, label: string, index: number) {
    Column() {
      Image(icon)
        .width(22)
        .height(22)
        .fillColor(this.activeTab === index ? '#B9B1FF' : '#6C6C6C')
      Text(label)
        .fontSize(14)
        .fontWeight(this.activeTab === index ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.activeTab === index ? '#B9B1FF' : '#A0A0A0')
        .margin({ top: 4 })
      if (this.activeTab === index) {
        Text('●').fontSize(6).fontColor('#7B61FF').margin({ top: 3 })
      }
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => { this.activeTab = index })
  }

  async selectModel(): Promise<void> {
    if (this.loading) {
      return;
    }
    let importedPath = '';
    let sourceFd = -1;
    let targetFd = -1;
    let importCommitted = false;
    this.loading = true;
    this.status = '正在导入模型';
    try {
      const context = this.getUIContext().getHostContext()!;
      const uris = await new picker.DocumentViewPicker(context).select({
        maxSelectNumber: 1,
        fileSuffixFilters: ['.gguf']
      });
      if (uris.length === 0) {
        this.status = this.modelId > 0 ? '模型已加载' : this.models.length > 0 ? '未加载' : '未选择模型';
        return;
      }
      const dir = context.filesDir + '/models';
      try {
        fileIo.mkdirSync(dir);
      } catch (error) {
        hilog.info(DOMAIN, TAG, 'models directory is ready: %{public}s', String(error));
      }

      const sourceFile = fileIo.openSync(uris[0], fileIo.OpenMode.READ_ONLY);
      sourceFd = sourceFile.fd;
      const originalName = sourceFile.name.length > 0 ? sourceFile.name : `本地模型 ${this.models.length + 1}.gguf`;
      const sourceSize = fileIo.statSync(sourceFd).size;
      if (this.containsSameImportedFile(originalName, sourceSize)) {
        this.status = '该模型已经导入';
        this.activeTab = 1;
        return;
      }

      const pathStem = `${dir}/model_${Date.now()}_${this.models.length + 1}`;
      const temporaryPath = pathStem + '.part';
      const path = pathStem + '.gguf';
      importedPath = temporaryPath;
      const targetFile = fileIo.openSync(temporaryPath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      targetFd = targetFile.fd;
      await fileIo.copyFile(sourceFile.fd, targetFile.fd);
      fileIo.closeSync(sourceFile);
      sourceFd = -1;
      fileIo.closeSync(targetFile);
      targetFd = -1;
      fileIo.renameSync(temporaryPath, path);
      importedPath = path;

      this.status = '正在读取模型信息';
      const parts = (await taskpool.execute(parseModelTask, path) as string).split('|');
      const importedModel: StoredModelInfo = {
        path: path,
        name: originalName,
        architecture: parts[0],
        quantization: parts[1],
        parameters: parts[2],
        contextLength: Number(parts[3]),
        tokenizer: parts[4],
        fileSize: Number(parts[5])
      };
      if (!this.isCompleteModelFile(path, importedModel.fileSize)) {
        throw new Error('模型文件复制不完整');
      }
      await ModelStore.getInstance().init(context);
      await ModelStore.getInstance().saveModel(importedModel);
      importCommitted = true;
      this.models = this.models.concat([importedModel]);
      this.status = '模型已导入，点击“加载模型”后使用';
      this.activeTab = 1;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'select model failed: %{public}s', String(error));
      this.status = '模型导入失败：' + String(error);
    } finally {
      if (sourceFd >= 0) {
        try {
          fileIo.closeSync(sourceFd);
        } catch (closeError) {
          hilog.error(DOMAIN, TAG, 'close source failed: %{public}s', String(closeError));
        }
      }
      if (targetFd >= 0) {
        try {
          fileIo.closeSync(targetFd);
        } catch (closeError) {
          hilog.error(DOMAIN, TAG, 'close target failed: %{public}s', String(closeError));
        }
      }
      if (!importCommitted && importedPath.length > 0) {
        try {
          if (fileIo.accessSync(importedPath)) {
            fileIo.unlinkSync(importedPath);
          }
        } catch (removeError) {
          hilog.error(DOMAIN, TAG, 'remove incomplete model failed: %{public}s', String(removeError));
        }
      }
      this.loading = false;
      this.loadingModelPath = '';
    }
  }

  private containsModelPath(models: StoredModelInfo[], path: string): boolean {
    for (const model of models) {
      if (model.path === path) {
        return true;
      }
    }
    return false;
  }

  private containsSameImportedFile(name: string, size: number): boolean {
    for (const model of this.models) {
      try {
        if (model.name === name && fileIo.accessSync(model.path) && fileIo.statSync(model.path).size === size) {
          return true;
        }
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'check duplicate model failed: %{public}s', String(error));
      }
    }
    return false;
  }

  private isCompleteModelFile(path: string, expectedModelSize: number): boolean {
    try {
      if (!fileIo.accessSync(path)) {
        return false;
      }
      return expectedModelSize <= 0 || fileIo.statSync(path).size >= expectedModelSize;
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'check model file failed: %{public}s', String(error));
      return false;
    }
  }

  async loadModel(model: StoredModelInfo): Promise<void> {
    if (this.loading || this.activeModelPath === model.path && this.modelId > 0) {
      return;
    }
    this.loading = true;
    this.loadingModelPath = model.path;
    this.status = '正在加载模型';
    try {
      const parts = (await taskpool.execute(loadModelTask, model.path, this.contextLength, this.threads) as string).split('|');
      this.modelId = Number(parts[0]);
      this.modelInfo = model;
      this.activeModelPath = model.path;
      this.messages = [];
      this.statsText = '';
      this.status = '模型已加载';
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'load model failed: %{public}s', String(error));
      this.modelId = 0;
      this.modelInfo = null;
      this.activeModelPath = '';
      this.status = '模型加载失败';
    } finally {
      this.loading = false;
      this.loadingModelPath = '';
    }
  }

  unload(): void {
    if (this.modelId > 0) {
      testNapi.unloadModel(this.modelId);
      this.modelId = 0;
      this.modelInfo = null;
      this.activeModelPath = '';
      this.status = '模型已卸载';
      this.messages = [];
      this.statsText = '';
    }
  }
  generate() { if (this.modelId === 0 || this.generating || this.input.trim().length === 0) return; const prompt = this.input.trim(); this.input = ''; this.messages = this.messages.concat([{ role: 'user', content: prompt }, { role: 'assistant', content: '' }]); this.generating = true; try { this.activeRequestId = testNapi.generate(prompt, { maxTokens: this.maxTokens, temperature: this.temperature, topK: this.topK, topP: this.topP, repeatPenalty: this.repeatPenalty, threads: this.threads }, (event: string, data: object) => { if (event === 'token') { const last = this.messages.length - 1; const next = this.messages.slice(); next[last] = { role: 'assistant', content: next[last].content + (data as TokenData).text }; this.messages = next; } else if (event === 'done' || event === 'stopped') { const s = data as GenerateStats; this.statsText = `输入 ${s.promptTokens} tokens · 输出 ${s.generatedTokens} tokens · TTFT ${s.ttftMs.toFixed(0)} ms · ${s.tokensPerSecond.toFixed(1)} tokens/s`; this.generating = false; } else if (event === 'error') { const error = data as GenerateError; this.statsText = `推理失败 (${error.code})：${error.message}`; this.generating = false; } }); } catch (e) { this.statsText = '无法开始生成：' + String(e); this.generating = false; } }
  stopGeneration() { if (this.activeRequestId > 0) testNapi.stopGenerate(this.activeRequestId); }
  startServe() { try { testNapi.startServer({ host: '127.0.0.1', port: 8080 }); this.refreshServerStatus(); this.logServer('服务已启动'); } catch (e) { this.logServer('启动失败：' + String(e)); } }
  stopServe() { testNapi.stopServer(); this.refreshServerStatus(); this.logServer('服务已停止'); }
  refreshServerStatus() { const info = testNapi.getServerStatus() as ServerInfo; this.serverRunning = info.running; this.serverInfo = info.running ? `http://${info.host}:${info.port}` : '服务未启动'; }
  testHealth() { this.requestServer('GET /health', `${BASE_URL}/health`, http.RequestMethod.GET); }
  testModels() { this.requestServer('GET /v1/models', `${BASE_URL}/v1/models`, http.RequestMethod.GET); }
  testChat() { this.requestServer('POST /v1/chat/completions', `${BASE_URL}/v1/chat/completions`, http.RequestMethod.POST, '{"messages":[{"role":"user","content":"hello"}],"max_tokens":64,"stream":false}'); }
  testCompletions() { this.requestServer('POST /v1/completions', `${BASE_URL}/v1/completions`, http.RequestMethod.POST, '{"prompt":"hello","max_tokens":64,"stream":false}'); }
  requestServer(label: string, url: string, method: http.RequestMethod, body?: string) {
    this.logServer('请求 ' + label);
    this.httpRequest.request(url, { method: method, header: { 'Content-Type': 'application/json' }, extraData: body, connectTimeout: 3000, readTimeout: 60000 }, (err: BusinessError, data: http.HttpResponse) => {
      if (err) this.logServer(`${label} 失败：${err.message}`);
      else this.logServer(`${label} → ${data.responseCode}`);
    });
  }
  logServer(line: string) { this.serverLog = this.serverLog.concat([line]).slice(-12); }
  async saveSettings(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context) {
      this.settingsStatus = '无法获取应用上下文';
      return;
    }
    try {
      await SettingsStore.getInstance().init(context);
      const settingsToSave: InferenceSettings = {
        contextLength: this.contextLength,
        maxTokens: this.maxTokens,
        threads: this.threads,
        temperature: this.temperature,
        topK: this.topK,
        topP: this.topP,
        repeatPenalty: this.repeatPenalty
      };
      await SettingsStore.getInstance().saveSettings(settingsToSave);
      this.settingsStatus = '设置已保存';
    } catch (error) {
      this.settingsStatus = '保存失败：' + String(error);
    }
  }
  formatSize(bytes: number): string { return bytes < 1024 * 1024 ? `${(bytes / 1024).toFixed(1)} KB` : `${(bytes / (1024 * 1024)).toFixed(1)} MB`; }
}
