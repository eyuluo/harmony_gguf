import { AppState } from '../../service/AppState';

@Component
export struct ParamDetailDialog {
  @ObjectLink appState: AppState;
  onClose: () => void = () => {};

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#99000000')
        .onClick(() => this.onClose())
      Column() {
        Text('参数详情')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .alignSelf(ItemAlign.Start)
          .margin({ bottom: 16 })
        Scroll() {
          Column() {
            if (this.appState.modelInfo !== null) {
              Text('模型参数')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor('#A0A0A0')
                .alignSelf(ItemAlign.Start)
                .margin({ bottom: 4 })
              this.detailRow('架构', this.appState.modelInfo.architecture)
              this.detailRow('参数量', this.appState.modelInfo.parameters)
              this.detailRow('量化等级', this.appState.modelInfo.quantization)
              this.detailRow('训练上下文', String(this.appState.modelInfo.contextLength))
              this.detailRow('分词器', this.appState.modelInfo.tokenizer)
              this.detailRow('文件大小', this.formatSize(this.appState.modelInfo.fileSize))
            }
            Text('加载配置')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor('#A0A0A0')
              .alignSelf(ItemAlign.Start)
              .margin({ top: 18, bottom: 4 })
            this.detailRow('Context length', this.configValue(this.appState.loadedConfig?.contextLength ?? 0))
            this.detailRow('Threads', this.configValue(this.appState.loadedConfig?.threads ?? 0))
            this.detailRow('Parallel', this.configValue(this.appState.loadedConfig?.parallel ?? 2))
          }
          .width('100%')
        }
        .layoutWeight(1)
        .width('100%')
        Button('关闭')
          .width('100%')
          .onClick(() => this.onClose())
          .backgroundColor('#6C5CE7')
          .fontColor('#FFFFFF')
          .borderRadius(12)
          .margin({ top: 16 })
      }
      .width('86%')
      .height('70%')
      .padding(20)
      .backgroundColor('#1E1F24')
      .borderWidth(1)
      .borderColor('#2C2D33')
      .borderRadius(16)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  detailRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor('#A0A0A0')
        .layoutWeight(1)
      Text(value)
        .fontSize(14)
        .fontColor('#FFFFFF')
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor('#25262B')
    .borderRadius(8)
    .margin({ bottom: 8 })
  }

  private formatSize(bytes: number): string {
    return bytes < 1024 * 1024 ? `${(bytes / 1024).toFixed(1)} KB` : `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  }

  private configValue(value: number): string {
    return value <= 0 ? '默认' : String(value);
  }
}
