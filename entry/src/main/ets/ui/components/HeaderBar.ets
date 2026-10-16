import { AppState } from '../../service/AppState';

@Component
export struct HeaderBar {
  @ObjectLink appState: AppState;

  build() {
    Column() {
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
      if (this.appState.modelId > 0 && this.appState.accelerationSummary.length > 0) {
        Row({ space: 12 }) {
          Text(this.appState.accelerationSummary)
            .layoutWeight(1)
            .fontSize(12)
            .fontColor('#B9B1FF')
            .onClick(() => {
              this.getUIContext().showAlertDialog({
                title: 'CPU / NPU 使用情况',
                message: this.appState.accelerationDetail +
                  '\n\nCPU 负责逐字生成，并处理未交给 NPU 的计算。' +
                  'NPU 仅尝试支持的部分计算，例如较长输入或图片的处理；开启开关、检测到设备，都不代表已使用 NPU 或整体更快。' +
                  '\n\n统计从本次模型加载开始累计，重新加载后清零。次数按计算部分计数，不是回复条数或 token 数。' +
                  '\n\n页面在模型加载及应用生成任务结束后更新，生成中或 Serve 请求执行期间可能不是最新状态。',
                confirm: { value: '知道了', action: () => {} }
              });
            })
          Text('内容均由AI生成')
            .fontSize(12)
            .fontColor('#A5A5AE')
            .textAlign(TextAlign.End)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .margin({ top: 6 })
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12, bottom: 8 })
    .backgroundColor('#18191D')
    .borderWidth({ bottom: 1 })
    .borderColor('#2C2D33')
  }
}
