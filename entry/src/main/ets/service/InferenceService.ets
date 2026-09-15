import { hilog } from '@kit.PerformanceAnalysisKit';
import { taskpool } from '@kit.ArkTS';
import testNapi from 'libentry.so';
import { GenerateStats, GenerateError, TokenData, LoadConfig } from 'libentry.so';
import { AppState } from './AppState';
import { StoredModelInfo } from './ModelStore';
import { loadModelTask } from './ModelTasks';

const DOMAIN = 0x0000;
const TAG = 'InferenceService';

export class InferenceService {
  private static instance: InferenceService | null = null;
  private state: AppState | null = null;
  private activeRequestId: number = 0;

  static getInstance(): InferenceService {
    if (InferenceService.instance === null) {
      InferenceService.instance = new InferenceService();
    }
    return InferenceService.instance;
  }

  init(state: AppState): void {
    this.state = state;
  }

  async loadModel(model: StoredModelInfo, config: LoadConfig): Promise<void> {
    const state = this.state!;
    if (state.loading || state.activeModelPath === model.path && state.modelId > 0) {
      return;
    }
    state.loading = true;
    state.loadingModelPath = model.path;
    state.loadFailed = false;
    try {
      const modelId = await taskpool.execute(loadModelTask, model.path, config.contextLength ?? 0,
        config.threads ?? 0, config.parallel ?? 2) as number;
      state.modelId = modelId;
      state.modelInfo = model;
      state.activeModelPath = model.path;
      state.loadedConfig = config;
      state.messages = [];
      state.lastStats = null;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'load model failed: %{public}s', String(error));
      state.modelId = 0;
      state.modelInfo = null;
      state.activeModelPath = '';
      state.loadedConfig = null;
      state.loadFailed = true;
    } finally {
      state.loading = false;
      state.loadingModelPath = '';
    }
  }

  unload(): void {
    const state = this.state!;
    if (state.modelId <= 0) {
      return;
    }
    testNapi.stopAllGenerations();
    testNapi.stopServer();
    testNapi.unloadModel(state.modelId);
    state.modelId = 0;
    state.modelInfo = null;
    state.activeModelPath = '';
    state.loadedConfig = null;
    state.messages = [];
    state.generating = false;
    state.lastStats = null;
    state.serverRunning = false;
    state.serverInfo = '服务未启动';
  }

  generate(): void {
    const state = this.state!;
    if (state.modelId === 0 || state.generating || state.input.trim().length === 0) {
      return;
    }
    const prompt = state.input.trim();
    state.input = '';
    state.messages = state.messages.concat([{ role: 'user', content: prompt }, { role: 'assistant', content: '' }]);
    state.generating = true;
    try {
      this.activeRequestId = testNapi.generate(prompt, {
        maxTokens: state.maxTokens,
        temperature: state.temperature,
        topK: state.topK,
        topP: state.topP,
        repeatPenalty: state.repeatPenalty,
        threads: state.threads
      }, (event: string, data: object) => {
        if (event === 'token') {
          const last = state.messages.length - 1;
          const next = state.messages.slice();
          next[last] = { role: 'assistant', content: next[last].content + (data as TokenData).text };
          state.messages = next;
        } else if (event === 'done' || event === 'stopped') {
          state.lastStats = data as GenerateStats;
          state.generating = false;
        } else if (event === 'error') {
          state.lastStats = null;
          state.generating = false;
        }
      });
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'generate failed: %{public}s', String(e));
      state.generating = false;
    }
  }

  stopGeneration(): void {
    if (this.activeRequestId > 0) {
      testNapi.stopGenerate(this.activeRequestId);
    }
  }
}
