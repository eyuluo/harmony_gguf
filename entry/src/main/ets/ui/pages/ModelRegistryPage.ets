import { AppState, ModelItem } from '../../service/AppState';
import { StoredModelInfo } from '../../service/ModelStore';
import { ModelService } from '../../service/ModelService';
import { InferenceService } from '../../service/InferenceService';
import { ConfirmDialog } from '../components/ConfirmDialog';
import { formatSize } from '../common/Utils';

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
            if (this.appState.models.length === 0) {
              Column() {
                Image($r('app.media.ic_model'))
                  .width(48)
                  .height(48)
                  .fillColor('#7B61FF')
                  .margin({ bottom: 16 })
                Text(this.appState.importing ? '正在导入模型' : '还没有导入模型')
                  .fontSize(18)
                  .fontColor('#FFFFFF')
                Text(this.appState.importing ? '正在读取模型信息，请稍候' : '选择一个本地 .gguf 文件开始')
                  .fontSize(13)
                  .fontColor('#6C6C6C')
                  .margin({ top: 8 })
              }
              .width('100%')
              .padding({ top: 72, bottom: 32 })
            } else {
              ForEach(this.appState.models, (item: ModelItem) => {
                this.modelCard(item)
              }, (item: ModelItem) => item.info.path + ':' +
                (item.info.mmproj === null ? '' : item.info.mmproj.path) + ':' +
                String(item.exists) + ':' + String(item.mmprojExists))
            }
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
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  topActions() {
    Column() {
      Row() {
        Column() {
          Text('模型')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
          Text(`${this.appState.models.length} 个本地模型`)
            .fontSize(12)
            .fontColor('#6C6C6C')
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Button(this.appState.importing ? '导入中...' : '+  导入 GGUF')
          .enabled(!this.appState.importing)
          .onClick(() => { this.modelService.importModel(); })
          .height(42)
          .fontSize(14)
          .backgroundColor(this.appState.importing ? '#35343F' : '#6C5CE7')
          .fontColor(this.appState.importing ? '#8F8D98' : '#FFFFFF')
          .borderRadius(12)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.hasMissingModels()) {
        Row() {
          Text('部分模型的本地文件已不存在')
            .fontSize(12)
            .fontColor('#E58C8C')
            .layoutWeight(1)
          Button('清理失效项')
            .onClick(() => { this.showDeleteMissing = true; })
            .height(32)
            .fontSize(12)
            .backgroundColor('#25262B')
            .fontColor('#E58C8C')
            .borderRadius(10)
        }
        .width('100%')
        .margin({ top: 12 })
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 22, bottom: 12 })
  }

  @Builder
  tag(value: string) {
    Text(value)
      .fontSize(12)
      .fontColor('#C9C9CF')
      .backgroundColor('#25262B')
      .borderRadius(8)
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .margin({ right: 6, bottom: 6 })
  }

  @Builder
  modelCard(item: ModelItem) {
    Column() {
      Row() {
        Text(item.info.name)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(item.info.path)
          .fontSize(11)
          .fontColor('#6C6C6C')
          .width('42%')
          .maxLines(1)
          .textAlign(TextAlign.End)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: 12 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      if (item.exists && item.mmprojExists) {
        Flex({ wrap: FlexWrap.Wrap }) {
          this.tag(`架构 ${item.info.architecture}`)
          this.tag(`参数量 ${item.info.parameters}`)
          this.tag(`量化 ${item.info.quantization}`)
          this.tag(`大小 ${formatSize(item.info.fileSize)}`)
          this.tag(`上下文 ${item.info.contextLength}`)
        }
        .width('100%')
        .margin({ top: 12, bottom: 6 })
      } else {
        Text('模型未找到')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor('#E05858')
          .margin({ top: 12, bottom: 6 })
      }
      Flex({ wrap: FlexWrap.Wrap }) {
        if (this.appState.activeModelPath === item.info.path && this.appState.modelId > 0) {
          Row() {
            Text('●').fontSize(9).fontColor('#78D891').margin({ right: 6 })
            Text('已加载').fontSize(12).fontWeight(FontWeight.Medium).fontColor('#A8DDB5')
          }
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor('#25352A')
          .borderRadius(12)
          Button('卸载')
            .onClick(() => { this.inference.unload(); })
            .margin({ right: 10, bottom: 6 })
            .backgroundColor('#2C2D33')
            .fontColor('#A0A0A0')
            .borderRadius(12)
        } else {
          Button(this.appState.loadingModelPath === item.info.path ? '加载中' : '加载模型')
            .enabled(!this.appState.loading)
            .onClick(() => { this.onOpenParamConfig(item.info); })
            .margin({ right: 10, bottom: 6 })
            .backgroundColor('#6C5CE7')
            .fontColor('#FFFFFF')
            .borderRadius(12)
        }
        if (item.info.mmproj === null) {
          Button('导入投影器')
            .onClick(() => { this.modelService.importMmproj(item.info); })
            .margin({ right: 10, bottom: 6 })
            .backgroundColor('#2C2D33')
            .fontColor('#A0A0A0')
            .borderRadius(12)
        }
        Button('删除注册表')
          .onClick(() => { this.pendingDelete = item.info; })
          .margin({ right: 10, bottom: 6 })
          .backgroundColor('#25262B')
          .fontColor('#A0A0A0')
          .borderRadius(12)
      }
      .width('100%')
      if (item.info.mmproj !== null) {
        this.mmprojLayer(item)
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#1E1F24')
    .borderWidth(1)
    .borderColor(item.exists && item.mmprojExists ?
      (this.appState.activeModelPath === item.info.path && this.appState.modelId > 0 ? '#4D465F' : '#2C2D33') : '#3A2C2C')
    .borderRadius(16)
    .margin({ bottom: 12 })
  }

  @Builder
  mmprojLayer(item: ModelItem) {
    if (item.info.mmproj !== null) {
      Column() {
        Divider().color('#2C2D33').margin({ top: 14, bottom: 12 })
        Row() {
          Text(item.info.mmproj.name)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(item.info.mmproj.path)
            .fontSize(11)
            .fontColor('#6C6C6C')
            .width('42%')
            .maxLines(1)
            .textAlign(TextAlign.End)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ left: 12 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        if (item.mmprojExists) {
          Flex({ wrap: FlexWrap.Wrap }) {
            this.tag(`类型 ${item.info.mmproj.projectorType}`)
            this.tag(`维度 ${item.info.mmproj.embdDim}`)
            this.tag(`大小 ${formatSize(item.info.mmproj.fileSize)}`)
          }
          .width('100%')
          .margin({ top: 12, bottom: 6 })
        } else {
          Text('模型未找到')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor('#E05858')
            .width('100%')
            .margin({ top: 12, bottom: 6 })
        }
        Flex({ wrap: FlexWrap.Wrap }) {
          Button(this.appState.selectedMmprojPath === item.info.mmproj.path ? '已选择投影器' : '选择投影器')
            .onClick(() => { this.modelService.toggleMmprojSelection(item.info); })
            .margin({ right: 10, bottom: 6 })
            .backgroundColor(this.appState.selectedMmprojPath === item.info.mmproj.path ? '#25352A' : '#25262B')
            .fontColor(this.appState.selectedMmprojPath === item.info.mmproj.path ? '#A8DDB5' : '#A0A0A0')
            .borderRadius(10)
          Button('删除投影器')
            .onClick(() => { this.modelService.deleteMmproj(item.info); })
            .margin({ right: 10, bottom: 6 })
            .backgroundColor('#2C2D33')
            .fontColor('#A0A0A0')
            .borderRadius(10)
        }
        .width('100%')
      }
      .width('100%')
      .padding({ top: 2, bottom: 4 })
    }
  }

  private hasMissingModels(): boolean {
    for (const item of this.appState.models) {
      if (!item.exists || !item.mmprojExists) {
        return true;
      }
    }
    return false;
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
