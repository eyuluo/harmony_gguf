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
    state.contextLength = this.clampInteger(saved.contextLength, 0, 32768, 0);
    state.maxTokens = this.clampInteger(saved.maxTokens, 1, 8192, 512);
    state.threads = this.clampInteger(saved.threads, 0, 32, 0);
    state.temperature = this.clampNumber(saved.temperature, 0, 2, 0.8);
    state.topK = this.clampInteger(saved.topK, 1, 200, 40);
    state.topP = this.clampNumber(saved.topP, 0.01, 1, 0.95);
    state.repeatPenalty = this.clampNumber(saved.repeatPenalty, 0.5, 2, 1.0);
    state.parallel = saved.parallel;
  }

  private clampInteger(value: number, min: number, max: number, fallback: number): number {
    if (!Number.isFinite(value)) {
      return fallback;
    }
    return Math.min(max, Math.max(min, Math.trunc(value)));
  }

  private clampNumber(value: number, min: number, max: number, fallback: number): number {
    if (!Number.isFinite(value)) {
      return fallback;
    }
    return Math.min(max, Math.max(min, value));
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
