import { AppState, ServeSource } from '../../service/AppState';
import { ServeService } from '../../service/ServeService';
import { EmptyState, LoadingState, FailedState } from '../components/StateViews';
import { formatSize, configValue } from '../common/Utils';

@Component
export struct ServePage {
  @ObjectLink appState: AppState;
  @Prop isWide: boolean = false;
  onOpenModels: () => void = () => {};
  private serve: ServeService = ServeService.getInstance();

  aboutToAppear(): void {
    this.serve.startAutoCheck();
  }

  aboutToDisappear(): void {
    this.serve.stopAutoCheck();
  }

  build() {
    if (this.isWide) {
      Row() {
        this.serveNav()
        if (this.appState.activeSourceId === '') {
          this.homeArea()
        } else {
          this.sourceDetail()
        }
      }
      .width('100%')
      .height('100%')
    } else {
      if (this.appState.activeSourceId === '') {
        this.homeArea()
      } else {
        this.sourceDetail()
      }
    }
  }

  @Builder
  serveNav() {
    Column() {
      Row() {
        Button('服务主页')
          .onClick(() => { this.appState.activeSourceId = ''; })
          .layoutWeight(1)
          .backgroundColor('#6C5CE7')
          .fontColor('#FFFFFF')
          .borderRadius(12)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 12 })

      Text('调用来源')
        .fontSize(12)
        .fontColor('#5F6068')
        .width('100%')
        .padding({ left: 16, top: 8, bottom: 8 })

      Scroll() {
        Column() {
          if (this.appState.serveSources.length === 0) {
            Column() {
              Text('暂无调用来源')
                .fontSize(12)
                .fontColor('#6C6C6C')
                .margin({ top: 16 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
          }
          ForEach(this.appState.serveSources, (src: ServeSource) => {
            Row() {
              Text(src.method)
                .fontSize(13)
                .fontColor(this.appState.activeSourceId === src.id ? '#FFFFFF' : '#C2C2C8')
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(`:${src.sourcePort}`)
                .fontSize(11)
                .fontColor('#6C6C6C')
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 10, bottom: 10 })
            .backgroundColor(this.appState.activeSourceId === src.id ? '#25262B' : '#00000000')
            .borderRadius(8)
            .onClick(() => { this.appState.activeSourceId = src.id; })
          }, (src: ServeSource) => src.id)
        }
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      Blank()
    }
    .width(240)
    .height('100%')
    .backgroundColor('#18191D')
    .borderWidth({ right: 1 })
    .borderColor('#2C2D33')
  }

  @Builder
  homeArea() {
    Column() {
      this.pageHeading()
      if (this.appState.loading) {
        LoadingState({ subtitle: this.appState.modelInfo !== null ? this.appState.modelInfo.name : '解析元数据并准备推理引擎，请稍候' })
      } else if (this.appState.loadFailed && this.appState.modelId === 0) {
        FailedState({ onAction: () => this.onOpenModels() })
      } else if (this.appState.modelId === 0) {
        EmptyState({
          icon: $r('app.media.ic_server'),
          title: '先选择一个本地模型',
          subtitle: '加载模型后即可启动本地 API 服务',
          buttonText: '选择模型',
          onAction: () => this.onOpenModels()
        })
      } else {
        Scroll() {
          Column() {
            Column() {
              Row() {
                Row() {
                  Text('●')
                    .fontSize(10)
                    .fontColor(this.appState.serverRunning ? '#78D891' : '#6C6C6C')
                    .margin({ right: 8 })
                  Text(this.appState.serverRunning ? '运行中' : '未运行')
                    .fontSize(18)
                    .fontColor(this.appState.serverRunning ? '#78D891' : '#A0A0A0')
                }
                .layoutWeight(1)
                Button(this.appState.serverRunning ? '停止服务' : '启动服务')
                  .enabled(!this.appState.loading || this.appState.serverRunning)
                  .onClick(() => this.appState.serverRunning ? this.serve.stopServe() : this.serve.startServe())
                  .backgroundColor(this.appState.serverRunning ? '#2C2D33' : '#6C5CE7')
                  .fontColor('#FFFFFF')
                  .borderRadius(12)
              }
              Text(this.appState.serverInfo).fontSize(13).fontColor('#A0A0A0').margin({ top: 12 })
            }
            .width('100%')
            .padding(16)
            .backgroundColor('#1E1F24')
            .borderWidth(1)
            .borderColor('#2C2D33')
            .borderRadius(16)
            .margin({ bottom: 12 })

            Row() {
              Text(this.appState.healthStatus.length > 0 ? this.appState.healthStatus : '未检查')
                .fontSize(13)
                .fontColor('#A0A0A0')
                .layoutWeight(1)
              Button('检查服务状态')
                .onClick(() => this.serve.checkHealth())
                .backgroundColor('#2C2D33')
                .fontColor('#B9B1FF')
                .fontSize(12)
                .borderRadius(10)
            }
            .width('100%')
            .padding(16)
            .backgroundColor('#1E1F24')
            .borderWidth(1)
            .borderColor('#2C2D33')
            .borderRadius(16)
            .margin({ bottom: 12 })

            this.paramDetail()

            if (!this.isWide) {
              Text('服务调用').fontSize(16).fontColor('#FFFFFF').alignSelf(ItemAlign.Start).margin({ top: 22, bottom: 10 })
              if (this.appState.serveSources.length === 0) {
                Text('暂无服务调用记录')
                  .fontSize(13)
                  .fontColor('#6C6C6C')
                  .width('100%')
                  .padding(16)
                  .backgroundColor('#1E1F24')
                  .borderWidth(1)
                  .borderColor('#2C2D33')
                  .borderRadius(16)
              }
              ForEach(this.appState.serveSources, (src: ServeSource) => {
                this.sourceRow(src)
              }, (src: ServeSource) => src.id)
            }
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 18, bottom: 20 })
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Auto)
      }
    }
    .layoutWeight(1)
    .width('100%')
    .height('100%')
  }

  @Builder
  pageHeading() {
    Column() {
      Text('本地服务')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
      Text('OpenAI 兼容 API，默认仅监听本机')
        .fontSize(13)
        .fontColor('#6C6C6C')
        .margin({ top: 6 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 20, right: 20, top: 22, bottom: 4 })
  }

  @Builder
  paramDetail() {
    Column() {
      Text('参数详情')
        .fontSize(16)
        .fontColor('#FFFFFF')
        .alignSelf(ItemAlign.Start)
        .margin({ bottom: 10 })
      if (this.appState.modelInfo !== null) {
        this.paramRow('架构', this.appState.modelInfo.architecture)
        this.paramRow('参数量', this.appState.modelInfo.parameters)
        this.paramRow('量化等级', this.appState.modelInfo.quantization)
        this.paramRow('训练上下文', String(this.appState.modelInfo.contextLength))
        this.paramRow('分词器', this.appState.modelInfo.tokenizer)
        this.paramRow('文件大小', formatSize(this.appState.modelInfo.fileSize))
      }
      this.paramRow('加载 Context', configValue(this.appState.loadedConfig?.contextLength ?? 0))
      this.paramRow('加载 Threads', configValue(this.appState.loadedConfig?.threads ?? 0))
      this.paramRow('加载 Parallel', configValue(this.appState.loadedConfig?.parallel ?? 8))
      this.paramRow('Max tokens', String(this.appState.maxTokens))
      this.paramRow('Temperature', String(this.appState.temperature))
      this.paramRow('Top-K', String(this.appState.topK))
      this.paramRow('Top-P', String(this.appState.topP))
      this.paramRow('Repeat penalty', String(this.appState.repeatPenalty))
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#1E1F24')
    .borderWidth(1)
    .borderColor('#2C2D33')
    .borderRadius(16)
  }

  @Builder
  paramRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(13)
        .fontColor('#A0A0A0')
        .layoutWeight(1)
      Text(value)
        .fontSize(13)
        .fontColor('#FFFFFF')
    }
    .width('100%')
    .padding({ top: 5, bottom: 5 })
  }

  @Builder
  sourceRow(src: ServeSource) {
    Column() {
      Row() {
        Text(src.method)
          .fontSize(14)
          .fontColor('#FFFFFF')
          .layoutWeight(1)
        Text(`来源 :${src.sourcePort}`)
          .fontSize(11)
          .fontColor('#6C6C6C')
      }
      Text(`总输入 ${src.totalInputTokens} · 总输出 ${src.totalOutputTokens}`)
        .fontSize(12)
        .fontColor('#A0A0A0')
        .margin({ top: 6 })
    }
    .width('100%')
    .padding(14)
    .backgroundColor('#1E1F24')
    .borderWidth(1)
    .borderColor('#2C2D33')
    .borderRadius(12)
    .margin({ bottom: 10 })
    .onClick(() => { this.appState.activeSourceId = src.id; })
  }

  @Builder
  sourceDetail() {
    Column() {
      Row() {
        if (!this.isWide) {
          Text('← 返回')
            .fontSize(14)
            .fontColor('#B9B1FF')
            .onClick(() => { this.appState.activeSourceId = ''; })
        }
        Blank()
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 12, bottom: 12 })

      Scroll() {
        Column() {
          Text('服务调用详情').fontSize(22).fontWeight(FontWeight.Bold).fontColor('#FFFFFF').alignSelf(ItemAlign.Start)
          if (this.currentSource() !== null) {
            Column() {
              this.detailRow('调用方式', this.currentSource()!.method)
              this.detailRow('调用来源端口', String(this.currentSource()!.sourcePort))
              this.detailRow('总输入 token', String(this.currentSource()!.totalInputTokens))
              this.detailRow('总输出 token', String(this.currentSource()!.totalOutputTokens))
              this.detailRow('最后输入 token', String(this.currentSource()!.lastInputTokens))
              this.detailRow('最后输出 token', String(this.currentSource()!.lastOutputTokens))
              this.detailRow('最后 ttft', `${this.currentSource()!.lastTtftMs.toFixed(0)} ms`)
              this.detailRow('最后 tps', this.currentSource()!.lastTps.toFixed(1))
            }
            .width('100%')
            .margin({ top: 16 })
          }
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 10, bottom: 20 })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .layoutWeight(1)
    .width('100%')
    .height('100%')
  }

  @Builder
  detailRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor('#A0A0A0')
        .layoutWeight(1)
      Text(value)
        .fontSize(14)
        .fontColor('#FFFFFF')
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor('#25262B')
    .borderRadius(8)
    .margin({ bottom: 8 })
  }

  private currentSource(): ServeSource | null {
    for (const src of this.appState.serveSources) {
      if (src.id === this.appState.activeSourceId) {
        return src;
      }
    }
    return null;
  }
}
