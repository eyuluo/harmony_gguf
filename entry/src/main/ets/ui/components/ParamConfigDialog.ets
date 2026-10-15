import { AppState } from '../../service/AppState';
import { SettingStepper } from './SettingStepper';

@Component
export struct ParamConfigDialog {
  @ObjectLink appState: AppState;
  onCancel: () => void = () => {};
  onConfirm: () => void = () => {};

  @State localContextLength: number = 0;
  @State localThreads: number = 0;
  @State localParallel: number = 1;
  @State localImageMaxTokens: number = 1024;
  @State localUseNpu: boolean = true;
  @State localMaxTokens: number = 512;
  @State localTemperature: number = 0.8;
  @State localTopK: number = 40;
  @State localTopP: number = 0.95;
  @State localRepeatPenalty: number = 1.0;

  aboutToAppear(): void {
    this.localContextLength = this.appState.contextLength;
    this.localThreads = this.appState.threads;
    this.localParallel = this.appState.parallel;
    this.localImageMaxTokens = this.appState.imageMaxTokens;
    this.localUseNpu = this.appState.useNpu;
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
            SettingStepper({ label: '上下文长度', value: $localContextLength, min: 0, max: 32768, step: 256 })
            Text('控制输入回灌和保留的上下文窗口，不限制回答总长度。回答上限由最大生成长度控制。')
              .fontSize(12).fontColor('#A0A0A0').width('100%')
            SettingStepper({ label: '线程数', value: $localThreads, min: 0, max: 32, step: 1 })
            SettingStepper({ label: '并发数', value: $localParallel, min: 1, max: 8, step: 1 })
            Row() {
              Text('NPU 加速').fontColor('#FFFFFF').layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.localUseNpu })
                .onChange((value: boolean) => { this.localUseNpu = value; })
            }.width('100%')
            Text('优先使用设备支持的 NPU 计算，其余计算使用 CPU。修改后重新加载模型。')
              .fontSize(12).fontColor('#A0A0A0').width('100%')
            if (this.appState.selectedMmprojPath.length > 0) {
              SettingStepper({ label: '图片 token 上限', value: $localImageMaxTokens, min: 0, max: 4096, step: 256 })
              Text('默认 1024；降低可加快图片处理，调高可保留更多细节。0 使用模型默认值，修改后需重新加载。')
                .fontSize(12)
                .fontColor('#A0A0A0')
                .width('100%')
            }
            Text('生成参数')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor('#A0A0A0')
              .alignSelf(ItemAlign.Start)
              .margin({ top: 18, bottom: 4 })
            SettingStepper({ label: '最大生成长度', value: $localMaxTokens, min: 1, max: 8192, step: 64 })
            SettingStepper({ label: '温度', value: $localTemperature, min: 0, max: 2, step: 0.05,
              decimalPlaces: 2 })
            SettingStepper({ label: '候选词数量', value: $localTopK, min: 1, max: 200, step: 1 })
            SettingStepper({ label: '累计概率阈值', value: $localTopP, min: 0.01, max: 1, step: 0.01, decimalPlaces: 2 })
            SettingStepper({ label: '重复惩罚', value: $localRepeatPenalty, min: 0.5, max: 2, step: 0.05,
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
    this.appState.imageMaxTokens = this.localImageMaxTokens;
    this.appState.useNpu = this.localUseNpu;
    this.appState.maxTokens = this.localMaxTokens;
    this.appState.temperature = this.localTemperature;
    this.appState.topK = this.localTopK;
    this.appState.topP = this.localTopP;
    this.appState.repeatPenalty = this.localRepeatPenalty;
  }
}
