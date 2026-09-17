import { AppState, SESSION_RUNNING } from '../../service/AppState';

@Component
export struct SideNav {
  @Link activeTab: number;
  @ObjectLink appState: AppState;

  build() {
    Column() {
      Blank().height(24)
      this.navItem($r('app.media.ic_chat'), this.chatLabel(), 0)
      this.navItem($r('app.media.ic_model'), '模型', 1)
      this.navItem($r('app.media.ic_server'), '服务', 2)
      Blank()
    }
    .width(188)
    .height('100%')
    .backgroundColor('#18191D')
    .borderWidth({ right: 1 })
    .borderColor('#2C2D33')
  }

  private chatLabel(): string {
    let count = 0;
    for (const s of this.appState.sessions) {
      if (s.status === SESSION_RUNNING) {
        count += 1;
      }
    }
    return count > 0 ? `对话 (${count})` : '对话';
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
