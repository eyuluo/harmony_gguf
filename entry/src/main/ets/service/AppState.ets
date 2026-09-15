import { StoredModelInfo } from './ModelStore';
import { GenerateStats, LoadConfig } from 'libentry.so';

export interface ChatMessage {
  role: string;
  content: string;
}

export interface ModelItem {
  info: StoredModelInfo;
  exists: boolean;
}

@Observed
export class AppState {
  loading: boolean = false;
  importing: boolean = false;
  loadingModelPath: string = '';
  loadFailed: boolean = false;
  modelId: number = 0;
  modelInfo: StoredModelInfo | null = null;
  activeModelPath: string = '';
  loadedConfig: LoadConfig | null = null;

  models: ModelItem[] = [];
  returnTab: number = 0;

  messages: ChatMessage[] = [];
  input: string = '';
  generating: boolean = false;
  lastStats: GenerateStats | null = null;

  serverRunning: boolean = false;
  serverInfo: string = '服务未启动';

  contextLength: number = 0;
  threads: number = 0;
  parallel: number = 2;

  temperature: number = 0.8;
  topK: number = 40;
  topP: number = 0.95;
  repeatPenalty: number = 1.0;
  maxTokens: number = 512;

  showParamConfig: boolean = false;
  showParamDetail: boolean = false;
  pendingLoadModel: StoredModelInfo | null = null;
}
