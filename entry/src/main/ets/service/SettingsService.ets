import { common } from '@kit.AbilityKit';
import { AppState } from './AppState';
import { SettingsStore, InferenceSettings } from './SettingsStore';

export class SettingsService {
  private static instance: SettingsService | null = null;
  private state: AppState | null = null;

  static getInstance(): SettingsService {
    if (SettingsService.instance === null) {
      SettingsService.instance = new SettingsService();
    }
    return SettingsService.instance;
  }

  init(state: AppState): void {
    this.state = state;
  }

  async restoreSettings(context: common.Context): Promise<void> {
    const state = this.state!;
    await SettingsStore.getInstance().init(context);
    const saved = SettingsStore.getInstance().getSettings();
    state.contextLength = saved.contextLength;
    state.maxTokens = saved.maxTokens;
    state.threads = saved.threads;
    state.temperature = saved.temperature;
    state.topK = saved.topK;
    state.topP = saved.topP;
    state.repeatPenalty = saved.repeatPenalty;
    state.parallel = saved.parallel;
  }

  async saveSettings(context: common.Context): Promise<void> {
    const state = this.state!;
    if (!context) {
      return;
    }
    const settings: InferenceSettings = {
      contextLength: state.contextLength,
      maxTokens: state.maxTokens,
      threads: state.threads,
      temperature: state.temperature,
      topK: state.topK,
      topP: state.topP,
      repeatPenalty: state.repeatPenalty,
      parallel: state.parallel
    };
    await SettingsStore.getInstance().init(context);
    await SettingsStore.getInstance().saveSettings(settings);
  }
}
