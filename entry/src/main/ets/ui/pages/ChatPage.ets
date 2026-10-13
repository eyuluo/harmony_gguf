import { AppState, Session, SessionMessage, SESSION_RUNNING, SESSION_QUEUED } from '../../service/AppState';
import { InferenceService } from '../../service/InferenceService';
import { fileIo, fileUri, picker } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
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
  @State selectingAttachment: boolean = false;
  @State attachmentError: string = '';
  private messageScroller: Scroller = new Scroller();
  private followMessages: boolean = true;

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
          Text(this.currentSession()!.status === SESSION_QUEUED ? '等待推理槽位' : '推理中')
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
      Scroll(this.messageScroller) {
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
          }, (message: SessionMessage) => `${message.id}-${message.content.length}`)
        }
        .width('100%')
        .onAreaChange(() => {
          if (this.followMessages) {
            this.messageScroller.scrollEdge(Edge.Bottom);
          }
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 12 })
      .layoutWeight(1)
      .onDidScroll(() => {
        this.followMessages = this.messageScroller.isAtEnd();
      })
      .onAreaChange(() => {
        if (this.followMessages) {
          this.messageScroller.scrollEdge(Edge.Bottom);
        }
      })
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
              Image(fileUri.getUriFromPath(uri))
                .width(72)
                .height(72)
                .objectFit(ImageFit.Cover)
                .borderRadius(8)
                .margin({ right: 8, bottom: 8 })
            }, (uri: string) => uri)
          }
          .width('100%')
        }
         Text(message.error ?? (message.content.length > 0 ? message.content : '…'))
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
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.attachments, (uri: string) => {
              Column() {
                Image(fileUri.getUriFromPath(uri))
                  .width(64)
                  .height(64)
                  .objectFit(ImageFit.Cover)
                  .borderRadius(8)
                  .onError(() => { this.attachmentError = '图片预览失败，请重新选择图片'; })
                Button('移除')
                  .height(24)
                  .fontSize(11)
                  .padding({ left: 8, right: 8 })
                  .backgroundColor('#2C2D33')
                  .fontColor('#B9B1FF')
                  .margin({ top: 4 })
                  .onClick(() => { this.attachments = this.attachments.filter((path: string) => path !== uri); })
              }
            }, (uri: string) => uri)
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Auto)
        .width('100%')
        .padding({ left: 4, bottom: 10 })
      }
      if (this.attachmentError.length > 0) {
        Text(this.attachmentError)
          .fontSize(12)
          .fontColor('#FF9B9B')
          .width('100%')
          .margin({ bottom: 6 })
      }
      TextInput({ placeholder: this.appState.modelId > 0 ? '输入消息...' : '请先加载模型', text: this.input })
        .width('100%')
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
      Row() {
        Button(this.selectingAttachment ? '读取中' : '添加图片')
          .width(96)
          .height(44)
          .padding({ left: 8, right: 8 })
          .enabled(this.appState.modelId > 0 && !this.appState.loading && !this.selectingAttachment &&
            this.attachments.length < 4)
          .onClick(() => this.selectAttachment())
          .backgroundColor('#1E1F24')
          .fontColor('#B9B1FF')
          .fontSize(14)
          .borderRadius(12)
        Blank()
        Button(this.isGenerating() ? '停止' : '发送')
          .width(64)
          .height(44)
          .margin({ left: 8 })
          .enabled(this.appState.modelId > 0 && (this.isGenerating() || !this.selectingAttachment) &&
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
      .margin({ top: 8 })
    }
    .width('100%')
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
    return s !== null && (s.status === SESSION_RUNNING || s.status === SESSION_QUEUED);
  }

  private send(): void {
    if (this.appState.modelId === 0 || this.selectingAttachment || this.isGenerating() ||
      this.input.trim().length === 0 && this.attachments.length === 0) {
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
    this.attachmentError = '';
    this.inference.generate(session.id, prompt, atts);
  }

  async selectAttachment(): Promise<void> {
    if (this.selectingAttachment || this.attachments.length >= 4) {
      return;
    }
    const context = this.getUIContext().getHostContext();
    if (!context) {
      return;
    }
    this.selectingAttachment = true;
    this.attachmentError = '';
    try {
      const uris = await new picker.DocumentViewPicker(context).select({
        maxSelectNumber: 4 - this.attachments.length,
        fileSuffixFilters: ['.png', '.jpg', '.jpeg', '.gif']
      });
      if (uris.length > 0) {
        const copied: string[] = [];
        const dir = context.filesDir + '/attachments';
        if (!fileIo.accessSync(dir)) {
          fileIo.mkdirSync(dir);
        }
        for (let index = 0; index < uris.length; index++) {
          const source = fileIo.openSync(uris[index], fileIo.OpenMode.READ_ONLY);
          try {
            const suffix = this.imageSuffix(source.name);
            const targetPath = `${dir}/image_${Date.now()}_${index}${suffix}`;
            const target = fileIo.openSync(targetPath,
              fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
            try {
              await fileIo.copyFile(source.fd, target.fd);
              copied.push(targetPath);
            } finally {
              fileIo.closeSync(target);
            }
          } finally {
            fileIo.closeSync(source);
          }
        }
        this.attachments = this.attachments.concat(copied);
      }
    } catch (error) {
      hilog.error(0x0000, 'ChatPage', '图片读取失败：%{public}s', String(error));
      this.attachmentError = '图片读取失败，请选择 PNG、JPEG 或 GIF 图片';
    } finally {
      this.selectingAttachment = false;
    }
  }

  private imageSuffix(name: string): string {
    const dot = name.lastIndexOf('.');
    if (dot < 0) {
      return '.jpg';
    }
    const suffix = name.substring(dot).toLowerCase();
    return suffix === '.png' || suffix === '.jpg' || suffix === '.jpeg' ||
      suffix === '.webp' || suffix === '.gif' ? suffix : '.jpg';
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
