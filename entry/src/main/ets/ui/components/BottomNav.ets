import { AppState, SESSION_RUNNING } from '../../service/AppState';

@Component
export struct BottomNav {
  @Link activeTab: number;
  @ObjectLink appState: AppState;

  build() {
    Row() {
      this.navItem($r('app.media.ic_chat'), this.chatLabel(), 0)
      this.navItem($r('app.media.ic_model'), '模型', 1)
      this.navItem($r('app.media.ic_server'), '服务', 2)
      this.navItem($r('app.media.ic_settings'), '设置', 3)
    }
    .width('100%')
    .height(72)
    .backgroundColor('#18191D')
    .borderWidth({ top: 1 })
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
    Column() {
      Image(icon)
        .width(22)
        .height(22)
        .fillColor(this.activeTab === index ? '#B9B1FF' : '#77777F')
      Text(label)
        .fontSize(14)
        .fontWeight(this.activeTab === index ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.activeTab === index ? '#D7D3FF' : '#A0A0A0')
        .margin({ top: 4 })
      if (this.activeTab === index) {
        Text('●').fontSize(6).fontColor('#7B61FF').margin({ top: 3 })
      }
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      if (index === 0 && this.activeTab === 0 && !this.appState.showSessionList) {
        this.appState.showSessionList = true;
      } else {
        this.activeTab = index;
      }
    })
  }
}
