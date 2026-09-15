import { AppState } from '../../service/AppState';
import { SettingsService } from '../../service/SettingsService';
import { SettingStepper } from '../components/SettingStepper';

@Component
export struct SettingsPage {
  @ObjectLink appState: AppState;
  private settings: SettingsService = SettingsService.getInstance();

  @State contextLength: number = 0;
  @State threads: number = 0;
  @State parallel: number = 2;
  @State maxTokens: number = 512;
  @State temperature: number = 0.8;
  @State topK: number = 40;
  @State topP: number = 0.95;
  @State repeatPenalty: number = 1.0;
  @State saveStatus: string = '';

  aboutToAppear(): void {
    this.contextLength = this.appState.contextLength;
    this.threads = this.appState.threads;
    this.parallel = this.appState.parallel;
    this.maxTokens = this.appState.maxTokens;
    this.temperature = this.appState.temperature;
    this.topK = this.appState.topK;
    this.topP = this.appState.topP;
    this.repeatPenalty = this.appState.repeatPenalty;
  }

  build() {
    Scroll() {
      Column() {
        Text('设置')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .alignSelf(ItemAlign.Start)
        Text('调整本地模型的加载与生成参数')
          .fontSize(13)
          .fontColor('#6C6C6C')
          .alignSelf(ItemAlign.Start)
          .margin({ top: 6, bottom: 22 })

        this.sectionTitle('模型参数')
        Column() {
          SettingStepper({ label: 'Context length', value: $contextLength, min: 0, max: 32768, step: 256 })
          SettingStepper({ label: 'Threads', value: $threads, min: 0, max: 32, step: 1 })
          SettingStepper({ label: 'Parallel', value: $parallel, min: 1, max: 8, step: 1 })
        }
        .width('100%')
        .backgroundColor('#1E1F24')
        .borderWidth(1)
        .borderColor('#2C2D33')
        .borderRadius(16)

        this.sectionTitle('生成参数')
        Column() {
          SettingStepper({ label: 'Max tokens', value: $maxTokens, min: 1, max: 8192, step: 64 })
          SettingStepper({ label: 'Temperature', value: $temperature, min: 0, max: 2, step: 0.05,
            decimalPlaces: 2 })
          SettingStepper({ label: 'Top-K', value: $topK, min: 0, max: 200, step: 1 })
          SettingStepper({ label: 'Top-P', value: $topP, min: 0, max: 1, step: 0.01, decimalPlaces: 2 })
          SettingStepper({ label: 'Repeat penalty', value: $repeatPenalty, min: 0.5, max: 2, step: 0.05,
            decimalPlaces: 2 })
        }
        .width('100%')
        .backgroundColor('#1E1F24')
        .borderWidth(1)
        .borderColor('#2C2D33')
        .borderRadius(16)

        Text('Context length、Threads 和 Parallel 会在下次加载模型时生效，其余参数会在下次生成时生效。')
          .fontSize(12)
          .fontColor('#6C6C6C')
          .lineHeight(18)
          .margin({ top: 14 })

        Button('保存设置')
          .onClick(() => this.save())
          .width('100%')
          .height(46)
          .backgroundColor('#6C5CE7')
          .fontColor('#FFFFFF')
          .fontSize(15)
          .borderRadius(12)
          .margin({ top: 18 })
        if (this.saveStatus.length > 0) {
          Text(this.saveStatus)
            .fontSize(12)
            .fontColor(this.saveStatus === '设置已保存' ? '#78D891' : '#E58C8C')
            .margin({ top: 10 })
        }
        Blank().height(24)
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 22, bottom: 20 })
    }
    .layoutWeight(1)
    .width('100%')
    .scrollBar(BarState.Auto)
  }

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor('#A0A0A0')
      .alignSelf(ItemAlign.Start)
      .margin({ top: 18, bottom: 8 })
  }

  async save(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context) {
      this.saveStatus = '无法获取应用上下文';
      return;
    }
    this.appState.contextLength = this.contextLength;
    this.appState.threads = this.threads;
    this.appState.parallel = this.parallel;
    this.appState.maxTokens = this.maxTokens;
    this.appState.temperature = this.temperature;
    this.appState.topK = this.topK;
    this.appState.topP = this.topP;
    this.appState.repeatPenalty = this.repeatPenalty;
    try {
      await this.settings.saveSettings(context);
      this.saveStatus = '设置已保存';
    } catch (error) {
      this.saveStatus = '保存失败：' + String(error);
    }
  }
}
