import { AppState } from '../../service/AppState';
import { SettingStepper } from './SettingStepper';

@Component
export struct ParamConfigDialog {
  @ObjectLink appState: AppState;
  onCancel: () => void = () => {};
  onConfirm: () => void = () => {};

  @State localContextLength: number = 0;
  @State localThreads: number = 0;
  @State localParallel: number = 8;
  @State localMaxTokens: number = 512;
  @State localTemperature: number = 0.8;
  @State localTopK: number = 40;
  @State localTopP: number = 0.95;
  @State localRepeatPenalty: number = 1.0;

  aboutToAppear(): void {
    this.localContextLength = this.appState.contextLength;
    this.localThreads = this.appState.threads;
    this.localParallel = this.appState.parallel;
    this.localMaxTokens = this.appState.maxTokens;
    this.localTemperature = this.appState.temperature;
    this.localTopK = this.appState.topK;
    this.localTopP = this.appState.topP;
    this.localRepeatPenalty = this.appState.repeatPenalty;
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#99000000')
        .onClick(() => this.onCancel())
      Column() {
        Text('参数配置')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .alignSelf(ItemAlign.Start)
          .margin({ bottom: 16 })
        Scroll() {
          Column() {
            Text('加载参数')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor('#A0A0A0')
              .alignSelf(ItemAlign.Start)
              .margin({ bottom: 4 })
            SettingStepper({ label: 'Context length', value: $localContextLength, min: 0, max: 32768, step: 256 })
            SettingStepper({ label: 'Threads', value: $localThreads, min: 0, max: 32, step: 1 })
            SettingStepper({ label: 'Parallel', value: $localParallel, min: 1, max: 8, step: 1 })
            Text('生成参数')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor('#A0A0A0')
              .alignSelf(ItemAlign.Start)
              .margin({ top: 18, bottom: 4 })
            SettingStepper({ label: 'Max tokens', value: $localMaxTokens, min: 1, max: 8192, step: 64 })
            SettingStepper({ label: 'Temperature', value: $localTemperature, min: 0, max: 2, step: 0.05,
              decimalPlaces: 2 })
            SettingStepper({ label: 'Top-K', value: $localTopK, min: 0, max: 200, step: 1 })
            SettingStepper({ label: 'Top-P', value: $localTopP, min: 0, max: 1, step: 0.01, decimalPlaces: 2 })
            SettingStepper({ label: 'Repeat penalty', value: $localRepeatPenalty, min: 0.5, max: 2, step: 0.05,
              decimalPlaces: 2 })
          }
          .width('100%')
        }
        .layoutWeight(1)
        .width('100%')
        Row() {
          Button('取消加载')
            .layoutWeight(1)
            .onClick(() => this.onCancel())
            .backgroundColor('#2C2D33')
            .fontColor('#A0A0A0')
            .borderRadius(12)
          Button('确认加载')
            .layoutWeight(1)
            .onClick(() => {
              this.writeBack();
              this.onConfirm();
            })
            .margin({ left: 12 })
            .backgroundColor('#6C5CE7')
            .fontColor('#FFFFFF')
            .borderRadius(12)
        }
        .width('100%')
        .margin({ top: 16 })
      }
      .width('88%')
      .height('82%')
      .padding(20)
      .backgroundColor('#1E1F24')
      .borderWidth(1)
      .borderColor('#2C2D33')
      .borderRadius(16)
    }
    .width('100%')
    .height('100%')
  }

  private writeBack(): void {
    this.appState.contextLength = this.localContextLength;
    this.appState.threads = this.localThreads;
    this.appState.parallel = this.localParallel;
    this.appState.maxTokens = this.localMaxTokens;
    this.appState.temperature = this.localTemperature;
    this.appState.topK = this.localTopK;
    this.appState.topP = this.localTopP;
    this.appState.repeatPenalty = this.localRepeatPenalty;
  }
}
