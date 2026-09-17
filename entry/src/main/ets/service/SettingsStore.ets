import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

// 推理参数配置（对应 NAPI GenerateParams + LoadConfig）
export interface InferenceSettings {
  contextLength: number;
  maxTokens: number;
  threads: number;
  temperature: number;
  topK: number;
  topP: number;
  repeatPenalty: number;
  parallel: number;
}

// 默认值（与 C++ 侧 GenerateParams / LoadConfig 默认值一致）
const DEFAULT_SETTINGS: InferenceSettings = {
  contextLength: 0,
  maxTokens: 512,
  threads: 0,
  temperature: 0.8,
  topK: 40,
  topP: 0.95,
  repeatPenalty: 1.0,
  parallel: 8
};

const PREF_NAME = 'settings';
const DOMAIN = 0x0000;
const TAG = 'SettingsStore';

// 参数配置持久化数据层（Preferences）
export class SettingsStore {
  private static instance: SettingsStore | null = null;
  private prefs: preferences.Preferences | null = null;
  private initialized: boolean = false;

  static getInstance(): SettingsStore {
    if (SettingsStore.instance === null) {
      SettingsStore.instance = new SettingsStore();
    }
    return SettingsStore.instance;
  }

  async init(context: common.Context): Promise<void> {
    if (this.initialized) {
      return;
    }
    const options: preferences.Options = { name: PREF_NAME };
    try {
      this.prefs = await preferences.getPreferences(context, options);
      this.initialized = true;
    } catch (error) {
      hilog.error(DOMAIN, TAG, '初始化设置失败: %{public}s', String(error));
      throw new Error('初始化设置失败: ' + String(error));
    }
  }

  // 读取全部参数（未保存的字段回退默认值）
  getSettings(): InferenceSettings {
    if (this.prefs === null) {
      return DEFAULT_SETTINGS;
    }
    try {
      return {
        contextLength: this.prefs.getSync('contextLength', DEFAULT_SETTINGS.contextLength) as number,
        maxTokens: this.prefs.getSync('maxTokens', DEFAULT_SETTINGS.maxTokens) as number,
        threads: this.prefs.getSync('threads', DEFAULT_SETTINGS.threads) as number,
        temperature: this.prefs.getSync('temperature', DEFAULT_SETTINGS.temperature) as number,
        topK: this.prefs.getSync('topK', DEFAULT_SETTINGS.topK) as number,
        topP: this.prefs.getSync('topP', DEFAULT_SETTINGS.topP) as number,
        repeatPenalty: this.prefs.getSync('repeatPenalty', DEFAULT_SETTINGS.repeatPenalty) as number,
        parallel: this.prefs.getSync('parallel', DEFAULT_SETTINGS.parallel) as number
      };
    } catch (error) {
      hilog.error(DOMAIN, TAG, '读取设置失败: %{public}s', String(error));
      return DEFAULT_SETTINGS;
    }
  }

  // 保存全部参数并落盘
  async saveSettings(settings: InferenceSettings): Promise<void> {
    if (this.prefs === null) {
      throw new Error('SettingsStore 尚未初始化');
    }
    try {
      await this.prefs.put('contextLength', settings.contextLength);
      await this.prefs.put('maxTokens', settings.maxTokens);
      await this.prefs.put('threads', settings.threads);
      await this.prefs.put('temperature', settings.temperature);
      await this.prefs.put('topK', settings.topK);
      await this.prefs.put('topP', settings.topP);
      await this.prefs.put('repeatPenalty', settings.repeatPenalty);
      await this.prefs.put('parallel', settings.parallel);
      await this.prefs.flush();
    } catch (error) {
      hilog.error(DOMAIN, TAG, '保存设置失败: %{public}s', String(error));
      throw new Error('保存设置失败: ' + String(error));
    }
  }

  // 恢复默认参数
  async resetSettings(): Promise<void> {
    await this.saveSettings(DEFAULT_SETTINGS);
  }
}
