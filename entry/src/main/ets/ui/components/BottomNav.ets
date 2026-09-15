@Component
export struct BottomNav {
  @Link activeTab: number;

  build() {
    Row() {
      this.navItem($r('app.media.ic_chat'), '对话', 0)
      this.navItem($r('app.media.ic_model'), '模型', 1)
      this.navItem($r('app.media.ic_server'), '服务', 2)
    }
    .width('100%')
    .height(72)
    .backgroundColor('#18191D')
    .borderWidth({ top: 1 })
    .borderColor('#2C2D33')
  }

  @Builder
  navItem(icon: Resource, label: string, index: number) {
    Column() {
      Image(icon)
        .width(22)
        .height(22)
        .fillColor(this.activeTab === index ? '#B9B1FF' : '#6C6C6C')
      Text(label)
        .fontSize(14)
        .fontWeight(this.activeTab === index ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.activeTab === index ? '#B9B1FF' : '#A0A0A0')
        .margin({ top: 4 })
      if (this.activeTab === index) {
        Text('●').fontSize(6).fontColor('#7B61FF').margin({ top: 3 })
      }
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => { this.activeTab = index })
  }
}
