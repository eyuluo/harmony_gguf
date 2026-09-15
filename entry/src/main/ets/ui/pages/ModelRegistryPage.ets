import { AppState, ModelItem } from '../../service/AppState';
import { StoredModelInfo } from '../../service/ModelStore';
import { ModelService } from '../../service/ModelService';
import { InferenceService } from '../../service/InferenceService';
import { ConfirmDialog } from '../components/ConfirmDialog';

@Component
export struct ModelRegistryPage {
  @ObjectLink appState: AppState;
  onOpenParamConfig: (model: StoredModelInfo) => void = (model: StoredModelInfo) => {};
  private modelService: ModelService = ModelService.getInstance();
  private inference: InferenceService = InferenceService.getInstance();
  @State pendingDelete: StoredModelInfo | null = null;
  @State showDeleteMissing: boolean = false;

  build() {
    Stack() {
      Column() {
        this.topActions()
        Scroll() {
          Column() {
            ForEach(this.appState.models, (item: ModelItem) => {
              this.modelCard(item)
            }, (item: ModelItem) => item.info.path)
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 8, bottom: 20 })
        }
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%')
      .height('100%')

      if (this.pendingDelete !== null) {
        ConfirmDialog({
          title: '删除注册表',
          message: '仅删除注册表项，不会删除本地文件',
          confirmText: '删除',
          onCancel: () => { this.pendingDelete = null; },
          onConfirm: () => { this.confirmDelete(); }
        })
      }
      if (this.showDeleteMissing) {
        ConfirmDialog({
          title: '删除不存在模型',
          message: '批量删除所有不存在的注册表项，不会删除本地文件',
          confirmText: '删除',
          onCancel: () => { this.showDeleteMissing = false; },
          onConfirm: () => { this.confirmDeleteMissing(); }
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  topActions() {
    Column() {
      Row() {
        Blank()
        Button('删除不存在模型')
          .onClick(() => { this.showDeleteMissing = true; })
          .backgroundColor('#2C2D33')
          .fontColor('#E58C8C')
          .fontSize(12)
          .borderRadius(10)
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 10 })
      Row() {
        Blank()
        Button(this.appState.importing ? '导入中...' : '+  导入模型')
          .onClick(() => { this.modelService.importModel(); })
          .backgroundColor('#6C5CE7')
          .fontColor('#FFFFFF')
          .borderRadius(12)
        Blank()
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 8, bottom: 12 })
    }
  }

  @Builder
  tag(value: string) {
    Text(value)
      .fontSize(11)
      .fontColor('#6C6C6C')
      .backgroundColor('#25262B')
      .borderRadius(8)
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .margin({ right: 6 })
  }

  @Builder
  modelCard(item: ModelItem) {
    Column() {
      Text(item.info.name).fontSize(18).fontColor('#FFFFFF')
      Text(item.info.path).fontSize(11).fontColor('#5F6068').margin({ top: 4 })
      if (item.exists) {
        Row() {
          this.tag(item.info.architecture)
          this.tag(item.info.quantization)
          this.tag(item.info.parameters)
        }
        .margin({ top: 12, bottom: 6 })
        Text(`上下文 ${item.info.contextLength} · 输入类型 ${item.info.tokenizer}`)
          .fontSize(12)
          .fontColor('#6C6C6C')
          .margin({ bottom: 14 })
        Row() {
          if (this.appState.activeModelPath === item.info.path && this.appState.modelId > 0) {
            Button('停止模型')
              .onClick(() => { this.inference.unload(); })
              .backgroundColor('#2C2D33')
              .fontColor('#E58C8C')
              .borderRadius(12)
          } else {
            Button(this.appState.loadingModelPath === item.info.path ? '加载中' : '加载模型')
              .enabled(!this.appState.loading)
              .onClick(() => { this.onOpenParamConfig(item.info); })
              .backgroundColor('#6C5CE7')
              .fontColor('#FFFFFF')
              .borderRadius(12)
          }
          Button('删除注册表')
            .onClick(() => { this.pendingDelete = item.info; })
            .margin({ left: 10 })
            .backgroundColor('#2C2D33')
            .fontColor('#A0A0A0')
            .borderRadius(12)
        }
      } else {
        Text('未在该位置找到该模型')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#E05858')
          .margin({ top: 12, bottom: 14 })
        Row() {
          Button('删除注册表')
            .onClick(() => { this.pendingDelete = item.info; })
            .backgroundColor('#2C2D33')
            .fontColor('#A0A0A0')
            .borderRadius(12)
        }
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#1E1F24')
    .borderWidth(1)
    .borderColor(item.exists ? (this.appState.activeModelPath === item.info.path && this.appState.modelId > 0 ? '#4D465F' : '#2C2D33') : '#3A2C2C')
    .borderRadius(16)
    .margin({ bottom: 12 })
  }

  async confirmDelete(): Promise<void> {
    const target = this.pendingDelete;
    if (target === null) {
      return;
    }
    if (this.appState.activeModelPath === target.path) {
      this.inference.unload();
    }
    await this.modelService.deleteRegistry(target);
    this.pendingDelete = null;
  }

  async confirmDeleteMissing(): Promise<void> {
    this.showDeleteMissing = false;
    await this.modelService.deleteMissingRegistries();
  }
}
