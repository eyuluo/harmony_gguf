import { COLOR_TEXT, COLOR_TEXT_FAINT, COLOR_PRIMARY, COLOR_ACCENT_DEEP, COLOR_DANGER_SOFT } from '../common/Theme';

@Component
export struct EmptyState {
  icon: Resource = $r('app.media.ic_model');
  title: string = '';
  subtitle: string = '';
  buttonText: string = '选择模型';
  onAction: () => void = () => {};

  build() {
    Column() {
      Image(this.icon)
        .width(64)
        .height(64)
        .fillColor(COLOR_ACCENT_DEEP)
        .margin({ bottom: 22 })
      Text(this.title)
        .fontSize(22)
        .fontColor(COLOR_TEXT)
      Text(this.subtitle)
        .fontSize(14)
        .fontColor(COLOR_TEXT_FAINT)
        .margin({ top: 8, bottom: 20 })
      Button(this.buttonText)
        .onClick(() => this.onAction())
        .backgroundColor(COLOR_PRIMARY)
        .fontColor(COLOR_TEXT)
        .borderRadius(12)
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }
}

@Component
export struct LoadingState {
  subtitle: string = '解析元数据并准备推理引擎，请稍候';

  build() {
    Column() {
      Text('正在加载模型')
        .fontSize(18)
        .fontColor(COLOR_TEXT)
      Text(this.subtitle)
        .fontSize(14)
        .fontColor(COLOR_TEXT_FAINT)
        .margin({ top: 8 })
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }
}

@Component
export struct FailedState {
  buttonText: string = '选择模型';
  onAction: () => void = () => {};

  build() {
    Column() {
      Text('加载失败，请重新加载')
        .fontSize(18)
        .fontColor(COLOR_DANGER_SOFT)
      Button(this.buttonText)
        .onClick(() => this.onAction())
        .margin({ top: 16 })
        .backgroundColor(COLOR_PRIMARY)
        .fontColor(COLOR_TEXT)
        .borderRadius(12)
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }
}
