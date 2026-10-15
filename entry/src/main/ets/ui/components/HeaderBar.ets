import { AppState } from '../../service/AppState';

@Component
export struct HeaderBar {
  @ObjectLink appState: AppState;

  build() {
    Row() {
      Column() {
        Row() {
          Image($r('app.media.icon'))
            .width(24)
            .height(24)
            .margin({ right: 8 })
          Text('鸿思')
            .fontSize(21)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
        }
        .alignItems(VerticalAlign.Center)
        Text(this.appState.modelInfo === null ? '本地离线推理器' : this.appState.modelInfo.name)
          .fontSize(11)
          .fontColor('#5F6068')
          .margin({ left: 32, top: 3 })
        if (this.appState.modelId > 0 && this.appState.accelerationSummary.length > 0) {
          Text(this.appState.accelerationSummary)
            .fontSize(11)
            .fontColor('#B9B1FF')
            .margin({ left: 32, top: 3 })
            .onClick(() => {
              this.getUIContext().showAlertDialog({
                title: '实际计算设备',
                message: this.appState.accelerationSummary + '\n' + this.appState.accelerationDetail +
                  '\n统计自本次加载起累计，对话结束后更新。NPU 主要尝试长输入处理，单 token 输出使用 CPU。',
                confirm: { value: '知道了', action: () => {} }
              });
            })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Row() {
        Text('●')
          .fontSize(9)
          .fontColor(this.appState.modelId > 0 ? '#78D891' : this.appState.loading ? '#B9B1FF' : '#85858D')
          .margin({ right: 6 })
        Text(this.appState.modelId > 0 ? '已加载' : this.appState.loading ? '加载中' : '未加载')
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
}
