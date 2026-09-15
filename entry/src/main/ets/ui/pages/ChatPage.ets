import { AppState, Session, SessionMessage, SESSION_RUNNING } from '../../service/AppState';
import { InferenceService } from '../../service/InferenceService';
import { GenerateStats } from 'libentry.so';
import { picker } from '@kit.CoreFileKit';
import { SessionList } from '../components/SessionList';

@Component
export struct ChatPage {
  @ObjectLink appState: AppState;
  @Prop isWide: boolean = false;
  onOpenModels: () => void = () => {};
  private inference: InferenceService = InferenceService.getInstance();
  @State input: string = '';
  @State attachments: string[] = [];

  build() {
    if (this.isWide) {
      Row() {
        Column() {
          SessionList({ appState: this.appState, onSelect: (id: number) => this.selectSession(id) })
        }
        .width(260)
        .height('100%')
        .backgroundColor('#18191D')
        .borderWidth({ right: 1 })
        .borderColor('#2C2D33')

        this.detailArea()
      }
      .width('100%')
      .height('100%')
    } else {
      if (this.appState.showSessionList) {
        Column() {
          SessionList({ appState: this.appState, onSelect: (id: number) => this.selectSession(id) })
        }
        .layoutWeight(1)
        .width('100%')
      } else {
        this.detailArea()
      }
    }
  }

  @Builder
  detailArea() {
    Column() {
      this.detailTopBar()
      if (this.appState.loading) {
        this.loadingState()
      } else if (this.appState.loadFailed && this.appState.modelId === 0) {
        this.failedState()
      } else if (this.appState.modelId === 0) {
        this.emptyState()
      } else if (this.currentSession() !== null) {
        this.messagesArea()
      } else {
        this.noSessionState()
      }
      if (this.appState.modelId > 0 && (this.isWide || this.currentSession() !== null)) {
        this.inputBar()
      }
    }
    .layoutWeight(1)
    .width('100%')
    .height('100%')
  }

  @Builder
  detailTopBar() {
    Row() {
      if (!this.isWide) {
        Text('← 返回')
          .fontSize(14)
          .fontColor('#B9B1FF')
          .onClick(() => { this.appState.showSessionList = true; })
      }
      Blank()
      if (this.currentSession() !== null && this.isGenerating()) {
        Row() {
          Text('●')
            .fontSize(8)
            .fontColor('#B9B1FF')
            .margin({ right: 5 })
          Text('推理中')
            .fontSize(12)
            .fontColor('#B9B1FF')
        }
      } else if (this.currentSession() !== null && this.currentSession()!.lastStats !== null) {
        Text(this.statsText(this.currentSession()!.lastStats))
          .fontSize(11)
          .fontColor('#6C6C6C')
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 14, bottom: 12 })
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
  noSessionState() {
    Column() {
      Image($r('app.media.ic_ai_chip'))
        .width(48)
        .height(48)
        .fillColor('#7B61FF')
        .margin({ bottom: 16 })
      Text('今天想聊些什么？')
        .fontSize(18)
        .fontColor('#FFFFFF')
      Text('与本地模型开始离线对话')
        .fontSize(13)
        .fontColor('#6C6C6C')
        .margin({ top: 8 })
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  messagesArea() {
    Column() {
      Scroll() {
        Column() {
          if (this.currentSession()!.messages.length === 0) {
            Column() {
              Image($r('app.media.ic_ai_chip'))
                .width(48)
                .height(48)
                .fillColor('#7B61FF')
                .margin({ bottom: 16 })
              Text('今天想聊些什么？')
                .fontSize(18)
                .fontColor('#FFFFFF')
              Text('与本地模型开始离线对话')
                .fontSize(13)
                .fontColor('#6C6C6C')
                .margin({ top: 8 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
            .margin({ top: 80 })
          }
          ForEach(this.currentSession()!.messages, (message: SessionMessage) => {
            this.messageBubble(message)
          }, (message: SessionMessage) => message.role + message.content)
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 12 })
      .layoutWeight(1)
    }
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  messageBubble(message: SessionMessage) {
    if (message.role === 'user') {
      Row() {
        Blank()
        Text(message.content)
          .fontSize(15)
          .fontColor('#FFFFFF')
          .backgroundColor('#6C5CE7')
          .borderRadius({ topLeft: 16, topRight: 16, bottomLeft: 16, bottomRight: 4 })
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .constraintSize({ maxWidth: '78%' })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .margin({ bottom: 14 })
    } else {
      Row() {
        if (message.content.length > 0) {
          Text(message.content)
            .fontSize(15)
            .fontColor('#E6E6E6')
            .backgroundColor('#1E1F24')
            .borderRadius({ topLeft: 16, topRight: 16, bottomRight: 16, bottomLeft: 4 })
            .padding({ left: 14, right: 14, top: 10, bottom: 10 })
            .constraintSize({ maxWidth: '82%' })
        } else {
          Text('…')
            .fontSize(15)
            .fontColor('#6C6C6C')
            .backgroundColor('#1E1F24')
            .borderRadius(16)
            .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .margin({ bottom: 14 })
    }
  }

  @Builder
  inputBar() {
    Column() {
      if (this.attachments.length > 0) {
        Row() {
          ForEach(this.attachments, (uri: string) => {
            Image(uri)
              .width(52)
              .height(52)
              .borderRadius(8)
              .margin({ right: 8 })
          }, (uri: string) => uri)
        }
        .width('100%')
        .padding({ left: 4, bottom: 10 })
      }
      Row() {
        TextInput({ placeholder: '输入消息...', text: this.input })
          .layoutWeight(1)
          .height(44)
          .onChange((value: string) => this.input = value)
          .onSubmit(() => this.send())
          .backgroundColor('#1E1F24')
          .fontColor('#F5F5F5')
          .placeholderColor('#66FFFFFF')
          .borderWidth(1)
          .borderColor('#2C2D33')
          .borderRadius(22)
          .padding({ left: 16, right: 16 })
        Button('⊕')
          .width(44)
          .height(44)
          .margin({ left: 8 })
          .onClick(() => this.selectAttachment())
          .backgroundColor('#1E1F24')
          .fontColor('#B9B1FF')
          .fontSize(20)
          .borderRadius(22)
        Button(this.isGenerating() ? '停止' : '发送')
          .width(64)
          .height(44)
          .margin({ left: 8 })
          .enabled(this.isGenerating() || this.input.trim().length > 0 || this.attachments.length > 0)
          .onClick(() => {
            if (this.isGenerating()) {
              this.inference.stopGeneration(this.currentSession()!.id);
            } else {
              this.send();
            }
          })
          .backgroundColor(this.isGenerating() || this.input.trim().length > 0 || this.attachments.length > 0 ? '#6C5CE7' : '#35343F')
          .fontColor(this.isGenerating() || this.input.trim().length > 0 || this.attachments.length > 0 ? '#FFFFFF' : '#8F8D98')
          .borderRadius(22)
      }
      .width('100%')
    }
    .padding({ left: 16, right: 16, top: 10, bottom: 14 })
    .backgroundColor('#18191D')
  }

  private selectSession(id: number): void {
    this.appState.activeSessionId = id;
    this.appState.showSessionList = false;
  }

  private currentSession(): Session | null {
    for (const s of this.appState.sessions) {
      if (s.id === this.appState.activeSessionId) {
        return s;
      }
    }
    return null;
  }

  private isGenerating(): boolean {
    const s = this.currentSession();
    return s !== null && s.status === SESSION_RUNNING;
  }

  private send(): void {
    if (this.input.trim().length === 0 && this.attachments.length === 0) {
      return;
    }
    let session = this.currentSession();
    if (session === null) {
      const id = this.inference.newSession();
      this.appState.activeSessionId = id;
      session = this.currentSession();
    }
    if (session === null) {
      return;
    }
    const prompt = this.input.trim();
    const atts = this.attachments.slice();
    this.input = '';
    this.attachments = [];
    this.inference.generate(session.id, prompt, atts);
  }

  async selectAttachment(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context) {
      return;
    }
    try {
      const uris = await new picker.DocumentViewPicker(context).select({
        maxSelectNumber: 1,
        fileSuffixFilters: ['.png', '.jpg', '.jpeg', '.webp', '.gif']
      });
      if (uris.length > 0) {
        this.attachments = this.attachments.concat(uris);
      }
    } catch (error) {
      return;
    }
  }

  private statsText(s: GenerateStats | null): string {
    if (s === null) {
      return '';
    }
    return `输入 ${s.promptTokens} · 输出 ${s.generatedTokens} · TTFT ${s.ttftMs.toFixed(0)} ms · ${s.tokensPerSecond.toFixed(1)} t/s`;
  }
}
