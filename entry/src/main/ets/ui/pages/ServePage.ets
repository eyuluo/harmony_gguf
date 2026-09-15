import { AppState } from '../../service/AppState';
import { ServeService } from '../../service/ServeService';

@Component
export struct ServePage {
  @ObjectLink appState: AppState;
  onOpenModels: () => void = () => {};
  onOpenParamDetail: () => void = () => {};
  private serve: ServeService = ServeService.getInstance();

  aboutToAppear(): void {
    this.serve.startAutoCheck();
  }

  aboutToDisappear(): void {
    this.serve.stopAutoCheck();
  }

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
        this.serveContent()
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
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12, bottom: 12 })
  }

  @Builder
  emptyState() {
    Column() {
      Image($r('app.media.ic_server'))
        .width(64)
        .height(64)
        .fillColor('#7B61FF')
        .margin({ bottom: 22 })
      Text('先选择一个本地模型')
        .fontSize(22)
        .fontColor('#FFFFFF')
      Text('加载模型后即可启动本地 API 服务')
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
  serveContent() {
    Scroll() {
      Column() {
        Text('本地服务').fontSize(24).fontWeight(FontWeight.Bold).fontColor('#FFFFFF').alignSelf(ItemAlign.Start)
        Text('OpenAI 兼容 API，默认仅监听本机').fontSize(13).fontColor('#6C6C6C').margin({ top: 6, bottom: 18 })
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
        .margin({ bottom: 22 })
        Text('服务调用列表').fontSize(16).fontColor('#FFFFFF').alignSelf(ItemAlign.Start).margin({ bottom: 10 })
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
      .width('100%')
      .padding({ left: 20, right: 20, top: 22, bottom: 20 })
    }
    .layoutWeight(1)
    .width('100%')
  }
}
