@Component
export struct ConfirmDialog {
  title: string = '';
  message: string = '';
  confirmText: string = '确认';
  onCancel: () => void = () => {};
  onConfirm: () => void = () => {};

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#99000000')
        .onClick(() => this.onCancel())
      Column() {
        Text(this.title)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .alignSelf(ItemAlign.Start)
        Text(this.message)
          .fontSize(14)
          .fontColor('#A0A0A0')
          .margin({ top: 10, bottom: 20 })
          .alignSelf(ItemAlign.Start)
        Row() {
          Button('取消')
            .layoutWeight(1)
            .onClick(() => this.onCancel())
            .backgroundColor('#2C2D33')
            .fontColor('#A0A0A0')
            .borderRadius(12)
          Button(this.confirmText)
            .layoutWeight(1)
            .onClick(() => this.onConfirm())
            .margin({ left: 12 })
            .backgroundColor('#E05858')
            .fontColor('#FFFFFF')
            .borderRadius(12)
        }
        .width('100%')
      }
      .width('80%')
      .padding(20)
      .backgroundColor('#1E1F24')
      .borderWidth(1)
      .borderColor('#2C2D33')
      .borderRadius(16)
    }
    .width('100%')
    .height('100%')
  }
}
