import { AppState, Session, SessionMessage, SESSION_RUNNING } from '../../service/AppState';
import { InferenceService } from '../../service/InferenceService';
import { picker } from '@kit.CoreFileKit';
import { SessionList } from '../components/SessionList';
import { EmptyState, LoadingState, FailedState } from '../components/StateViews';

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
        LoadingState({ subtitle: this.appState.modelInfo !== null ? this.appState.modelInfo.name : '解析元数据并准备推理引擎，请稍候' })
      } else if (this.appState.loadFailed && this.appState.modelId === 0) {
        FailedState({ onAction: () => this.onOpenModels() })
      } else if (this.appState.modelId === 0) {
        EmptyState({
          icon: $r('app.media.ic_model'),
          title: '先选择一个本地模型',
          subtitle: '导入 GGUF 文件后，就可以开始离线对话',
          buttonText: '选择模型',
          onAction: () => this.onOpenModels()
        })
      } else if (this.currentSession() !== null) {
        this.messagesArea()
      } else {
        this.noSessionState()
      }
      this.inputBar()
    }
    .layoutWeight(1)
    .width('100%')
    .height('100%')
  }

  @Builder
  detailTopBar() {
    Column() {
      Row() {
        if (!this.isWide) {
          Row() {
            Image($r('app.media.ic_sessions'))
              .width(16)
              .height(16)
            Text('对话列表')
              .fontSize(12)
              .fontColor('#CFC9FF')
              .margin({ left: 6 })
          }
            .height(32)
            .padding({ left: 10, right: 10 })
            .backgroundColor('#1E1F24')
            .borderRadius(10)
            .onClick(() => { this.appState.showSessionList = true; })
        }
        Blank()
      }
      .width('100%')

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
          .width('100%')
          .justifyContent(FlexAlign.End)
          .margin({ top: 6 })
      } else if (this.currentSession() !== null &&
        (this.currentSession()!.lastStats !== null || this.currentSession()!.totalInputTokens > 0 ||
        this.currentSession()!.totalOutputTokens > 0)) {
        Text(this.statsText(this.currentSession()!))
          .width('100%')
          .fontSize(11)
          .fontColor('#6C6C6C')
          .textAlign(TextAlign.End)
          .margin({ top: 6 })
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 14, bottom: 12 })
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
    Row() {
      Text(message.role === 'user' ? '你' : 'AI')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(message.role === 'user' ? '#B9B1FF' : '#78D891')
        .width(32)
        .margin({ top: 3 })
      Column() {
        if (message.attachments.length > 0) {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(message.attachments, (uri: string) => {
              Image(uri)
                .width(72)
                .height(72)
                .borderRadius(8)
                .margin({ right: 8, bottom: 8 })
            }, (uri: string) => uri)
          }
          .width('100%')
        }
        Text(message.content.length > 0 ? message.content : '…')
          .fontSize(15)
          .fontColor(message.content.length > 0 ? '#E6E6E6' : '#6C6C6C')
          .lineHeight(22)
          .width('100%')
      }
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ top: 4, bottom: 4 })
    .margin({ bottom: 14 })
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
        TextInput({ placeholder: this.appState.modelId > 0 ? '输入消息...' : '请先加载模型', text: this.input })
          .layoutWeight(1)
          .height(44)
          .enabled(this.appState.modelId > 0 && !this.appState.loading)
          .onChange((value: string) => this.input = value)
          .onSubmit(() => this.send())
          .backgroundColor('#1E1F24')
          .fontColor('#F5F5F5')
          .placeholderColor('#66FFFFFF')
          .borderWidth(1)
          .borderColor('#2C2D33')
          .borderRadius(12)
          .padding({ left: 16, right: 16 })
        Button('⊕')
          .width(42)
          .height(44)
          .enabled(this.appState.modelId > 0 && !this.appState.loading)
          .margin({ left: 8 })
          .onClick(() => this.selectAttachment())
          .backgroundColor('#1E1F24')
          .fontColor('#B9B1FF')
          .fontSize(20)
          .borderRadius(12)
        Button(this.isGenerating() ? '停止' : '发送')
          .width(64)
          .height(44)
          .margin({ left: 8 })
          .enabled(this.appState.modelId > 0 &&
            (this.isGenerating() || this.input.trim().length > 0 || this.attachments.length > 0))
          .onClick(() => {
            if (this.isGenerating()) {
              this.inference.stopGeneration(this.currentSession()!.id);
            } else {
              this.send();
            }
          })
          .backgroundColor(this.appState.modelId > 0 &&
            (this.isGenerating() || this.input.trim().length > 0 || this.attachments.length > 0) ? '#8A74FF' : '#35343F')
          .fontColor(this.appState.modelId > 0 &&
            (this.isGenerating() || this.input.trim().length > 0 || this.attachments.length > 0) ? '#FFFFFF' : '#8F8D98')
          .borderRadius(12)
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
    if (this.appState.modelId === 0 || this.input.trim().length === 0 && this.attachments.length === 0) {
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

  private statsText(session: Session): string {
    const s = session.lastStats;
    const totals = `总输入：${session.totalInputTokens} tokens, 总输出：${session.totalOutputTokens} tokens`;
    if (s === null) {
      return totals;
    }
    return `${totals}\n` +
      `输入：${s.promptTokens} tokens, 输出：${s.generatedTokens} tokens\n` +
      `TTFT：${s.ttftMs.toFixed(0)} ms, 吞吐量：${s.tokensPerSecond.toFixed(1)} tokens/s`;
  }
}
