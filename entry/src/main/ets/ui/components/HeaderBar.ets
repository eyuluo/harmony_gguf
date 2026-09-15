import { AppState } from '../../service/AppState';

@Component
export struct HeaderBar {
  @ObjectLink appState: AppState;

  build() {
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
        Text(this.appState.modelInfo === null ? '本地离线推理器' : this.appState.modelInfo.name)
          .fontSize(11)
          .fontColor('#5F6068')
          .margin({ left: 32, top: 3 })
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
