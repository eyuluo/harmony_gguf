@Component
export struct SideNav {
  @Link activeTab: number;

  build() {
    Column() {
      Row() {
        Image($r('app.media.ic_ai_chip'))
          .width(28)
          .height(28)
          .margin({ right: 10 })
        Text('Harmony-GGUF')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
      }
      .width('100%')
      .padding({ left: 20, top: 24, bottom: 28 })
      .alignItems(VerticalAlign.Center)

      this.navItem($r('app.media.ic_chat'), '对话', 0)
      this.navItem($r('app.media.ic_model'), '模型', 1)
      this.navItem($r('app.media.ic_server'), '服务', 2)
      Blank()
    }
    .width(200)
    .height('100%')
    .backgroundColor('#18191D')
    .borderWidth({ right: 1 })
    .borderColor('#2C2D33')
  }

  @Builder
  navItem(icon: Resource, label: string, index: number) {
    Row() {
      Image(icon)
        .width(20)
        .height(20)
        .fillColor(this.activeTab === index ? '#B9B1FF' : '#6C6C6C')
      Text(label)
        .fontSize(15)
        .fontWeight(this.activeTab === index ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.activeTab === index ? '#B9B1FF' : '#A0A0A0')
        .margin({ left: 12 })
    }
    .width('100%')
    .padding({ left: 20, top: 14, bottom: 14 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.activeTab === index ? '#25262B' : '#00000000')
    .onClick(() => { this.activeTab = index })
  }
}
