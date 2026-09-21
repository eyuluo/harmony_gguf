import { hilog } from '@kit.PerformanceAnalysisKit';
import { LoadConfig } from 'libentry.so';
import { AppState } from '../service/AppState';
import { StoredModelInfo } from '../service/ModelStore';
import { InferenceService } from '../service/InferenceService';
import { ModelService } from '../service/ModelService';
import { ServeService } from '../service/ServeService';
import { SettingsService } from '../service/SettingsService';
import { SessionStore } from '../service/SessionStore';
import { HeaderBar } from '../ui/components/HeaderBar';
import { BottomNav } from '../ui/components/BottomNav';
import { SideNav } from '../ui/components/SideNav';
import { ParamConfigDialog } from '../ui/components/ParamConfigDialog';
import { ChatPage } from '../ui/pages/ChatPage';
import { ModelRegistryPage } from '../ui/pages/ModelRegistryPage';
import { ServePage } from '../ui/pages/ServePage';

const DOMAIN = 0x0000;
const TAG = 'HarmonyGGUF';
const PC_WIDTH = 840;

@Entry
@Component
struct Index {
  @State appState: AppState = new AppState();
  @State activeTab: number = 0;
  @State isWide: boolean = false;
  private inference: InferenceService = InferenceService.getInstance();
  private modelService: ModelService = ModelService.getInstance();
  private serve: ServeService = ServeService.getInstance();
  private settings: SettingsService = SettingsService.getInstance();

  aboutToAppear(): void {
    this.initialize();
  }

  async initialize(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context) {
      return;
    }
    this.inference.init(this.appState);
    this.serve.init(this.appState);
    this.settings.init(this.appState);
    this.modelService.init(this.appState, context);
    try {
      await this.settings.restoreSettings(context);
      await this.modelService.refreshModels();
      await SessionStore.getInstance().init(context);
      await this.inference.restoreSessions();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'initialize failed: %{public}s', String(error));
    }
  }

  build() {
    Stack() {
      if (this.isWide) {
        this.pcLayout()
      } else {
        this.phoneLayout()
      }
      if (this.appState.showParamConfig) {
        ParamConfigDialog({
          appState: this.appState,
          onCancel: () => this.cancelLoad(),
          onConfirm: () => this.confirmLoad()
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#121212')
    .onAreaChange((oldValue: Area, newValue: Area) => {
      this.isWide = newValue.width >= PC_WIDTH;
    })
  }

  @Builder
  phoneLayout() {
    Column() {
      HeaderBar({ appState: this.appState })
      Column() {
        this.pageContent()
      }
      .layoutWeight(1)
      .width('100%')
      BottomNav({ activeTab: $activeTab, appState: this.appState })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  pcLayout() {
    Row() {
      SideNav({ activeTab: $activeTab, appState: this.appState })

      Column() {
        HeaderBar({ appState: this.appState })
        Column() {
          this.pageContent()
        }
        .layoutWeight(1)
        .width('100%')
      }
      .layoutWeight(1)
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  pageContent() {
    if (this.activeTab === 0) {
      ChatPage({
        appState: this.appState,
        isWide: this.isWide,
        onOpenModels: () => this.openModels(0)
      })
    } else if (this.activeTab === 1) {
      ModelRegistryPage({
        appState: this.appState,
        onOpenParamConfig: (model: StoredModelInfo) => this.openParamConfig(model)
      })
    } else if (this.activeTab === 2) {
      ServePage({
        appState: this.appState,
        isWide: this.isWide,
        onOpenModels: () => this.openModels(2)
      })
    }
  }

  openModels(fromTab: number): void {
    this.appState.returnTab = fromTab;
    this.activeTab = 1;
  }

  openParamConfig(model: StoredModelInfo): void {
    this.appState.pendingLoadModel = model;
    this.appState.showParamConfig = true;
  }

  cancelLoad(): void {
    this.appState.showParamConfig = false;
    this.appState.pendingLoadModel = null;
  }

  async confirmLoad(): Promise<void> {
    const model = this.appState.pendingLoadModel;
    this.appState.showParamConfig = false;
    this.appState.pendingLoadModel = null;
    if (model === null) {
      return;
    }
    const context = this.getUIContext().getHostContext();
    if (context) {
      try {
        await this.settings.saveSettings(context);
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'save settings failed: %{public}s', String(error));
      }
    }
    try {
      let mmprojPath = '';
      if (this.modelService.isMmprojSelected(model)) {
        mmprojPath = await this.modelService.resolveMmproj(model);
      }
      const config: LoadConfig = {
        contextLength: this.appState.contextLength,
        threads: this.appState.threads,
        parallel: this.appState.parallel,
        mmprojPath: mmprojPath
      };
      await this.inference.loadModel(model, config);
      if (this.appState.modelId > 0) {
        this.activeTab = this.appState.returnTab;
      }
    } catch (error) {
      this.appState.loadFailed = true;
      const message = (error as Error).message.length > 0 ? (error as Error).message : '加载失败';
      try {
        this.getUIContext().getPromptAction().showToast({ message: message });
      } catch (toastError) {
        hilog.error(DOMAIN, TAG, 'show toast failed: %{public}s', String(toastError));
      }
    }
  }
}
