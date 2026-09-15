@Component
export struct SettingStepper {
  @Link value: number;
  label: string = '';
  min: number = 0;
  max: number = 100;
  step: number = 1;
  decimalPlaces: number = 0;

  private adjust(delta: number): void {
    const boundedValue = Math.min(this.max, Math.max(this.min, this.value + delta));
    this.value = Number(boundedValue.toFixed(this.decimalPlaces));
  }

  private displayValue(): string {
    return this.decimalPlaces > 0 ? this.value.toFixed(this.decimalPlaces) : String(this.value);
  }

  build() {
    Row() {
      Text(this.label)
        .fontSize(14)
        .fontColor('#A0A0A0')
        .layoutWeight(1)
      Row() {
        Button('−')
          .width(40)
          .height(36)
          .fontSize(19)
          .enabled(this.value > this.min)
          .onClick(() => { this.adjust(-this.step); })
          .backgroundColor('#2C2D33')
          .fontColor('#B9B1FF')
          .borderRadius(8)
        Text(this.displayValue())
          .width(68)
          .textAlign(TextAlign.Center)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontFeature('"tnum" 1')
          .fontColor('#FFFFFF')
        Button('+')
          .width(40)
          .height(36)
          .fontSize(19)
          .enabled(this.value < this.max)
          .onClick(() => { this.adjust(this.step); })
          .backgroundColor('#2C2D33')
          .fontColor('#B9B1FF')
          .borderRadius(8)
      }
      .padding(3)
      .backgroundColor('#1A1B20')
      .borderRadius(8)
      .borderWidth(1)
      .borderColor('#2C2D33')
    }
    .width('100%')
    .padding({ left: 16, right: 12, top: 9, bottom: 9 })
  }
}
