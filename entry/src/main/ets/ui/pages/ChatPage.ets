import { AppState, ChatMessage } from '../../service/AppState';
import { InferenceService } from '../../service/InferenceService';
import { GenerateStats } from 'libentry.so';

@Component
export struct ChatPage {
  @ObjectLink appState: AppState;
  onOpenModels: () => void = () => {};
  onOpenParamDetail: () => void = () => {};
  private inference: InferenceService = InferenceService.getInstance();

  build() {
    Column() {
      this.topBar()
      if (this.appState.loading) {
        this.loadingState()
      } else if (this.appState.loadFailed && this.appState.modelId === 0) {
        this.failedState()
      } else if (this.appState.modelId === 0) {
        this.emptyState()
      } else {
        this.chatContent()
      }
    }
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  topBar() {
    Row() {
      if (this.appState.modelId > 0) {
        Text('参数详情')
          .fontSize(13)
          .fontColor('#B9B1FF')
          .onClick(() => this.onOpenParamDetail())
      }
      Blank()
      if (this.appState.generating) {
        Text('推理中')
          .fontSize(12)
          .fontColor('#B9B1FF')
      } else if (this.appState.lastStats !== null) {
        Text(this.statsText(this.appState.lastStats))
          .fontSize(12)
          .fontColor('#6C6C6C')
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  emptyState() {
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
      Button('选择模型')
        .onClick(() => this.onOpenModels())
        .backgroundColor('#6C5CE7')
        .fontColor('#FFFFFF')
        .borderRadius(12)
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  loadingState() {
    Column() {
      Text('正在加载模型')
        .fontSize(18)
        .fontColor('#FFFFFF')
      Text(this.appState.modelInfo !== null ? this.appState.modelInfo.name : '解析元数据并准备推理引擎，请稍候')
        .fontSize(14)
        .fontColor('#6C6C6C')
        .margin({ top: 8 })
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  failedState() {
    Column() {
      Text('加载失败，请重新加载')
        .fontSize(18)
        .fontColor('#E58C8C')
      Button('选择模型')
        .onClick(() => this.onOpenModels())
        .margin({ top: 16 })
        .backgroundColor('#6C5CE7')
        .fontColor('#FFFFFF')
        .borderRadius(12)
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  chatContent() {
    Column() {
      Scroll() {
        Column() {
          if (this.appState.messages.length === 0) {
            Text('今天想聊些什么？')
              .fontSize(18)
              .fontColor('#A0A0A0')
              .margin({ top: 36, bottom: 20 })
          }
          ForEach(this.appState.messages, (message: ChatMessage) => {
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
        .width('100%')
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 8, bottom: 12 })
      .layoutWeight(1)

      Row() {
        TextInput({ placeholder: '输入消息...', text: this.appState.input })
          .layoutWeight(1)
          .onChange((value: string) => this.appState.input = value)
          .backgroundColor('#1E1F24')
          .fontColor('#F5F5F5')
          .placeholderColor('#99FFFFFF')
          .borderWidth(1)
          .borderColor('#2C2D33')
          .borderRadius(12)
        Button(this.appState.generating ? '停止' : '发送')
          .enabled(this.appState.generating || this.appState.input.trim().length > 0)
          .onClick(() => this.appState.generating ? this.inference.stopGeneration() : this.inference.generate())
          .margin({ left: 8 })
          .backgroundColor(this.appState.generating || this.appState.input.trim().length > 0 ? '#8A74FF' : '#35343F')
          .fontColor(this.appState.generating || this.appState.input.trim().length > 0 ? '#FFFFFF' : '#8F8D98')
          .borderRadius(12)
      }
      .padding({ left: 16, right: 16, top: 10, bottom: 14 })
      .backgroundColor('#18191D')
    }
    .layoutWeight(1)
  }

  private statsText(s: GenerateStats): string {
    return `输入 ${s.promptTokens} · 输出 ${s.generatedTokens} · TTFT ${s.ttftMs.toFixed(0)} ms · ${s.tokensPerSecond.toFixed(1)} t/s`;
  }
}
