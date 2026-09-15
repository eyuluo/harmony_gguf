import { StoredModelInfo } from './ModelStore';
import { GenerateStats, LoadConfig } from 'libentry.so';

export interface SessionMessage {
  role: string;
  content: string;
  attachments: string[];
}

export interface Session {
  id: number;
  title: string;
  messages: SessionMessage[];
  status: string;
  updatedAt: number;
  pinned: boolean;
  lastStats: GenerateStats | null;
  requestId: number;
  pendingPrompt: string;
}

export interface ModelItem {
  info: StoredModelInfo;
  exists: boolean;
}

export interface ServeSource {
  id: string;
  method: string;
  sourcePort: number;
  totalInputTokens: number;
  totalOutputTokens: number;
  lastInputTokens: number;
  lastOutputTokens: number;
  lastTtftMs: number;
  lastTps: number;
}

export const SESSION_IDLE = 'idle';
export const SESSION_QUEUED = 'queued';
export const SESSION_RUNNING = 'running';
export const SESSION_FAILED = 'failed';
export const SESSION_STOPPED = 'stopped';

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

  sessions: Session[] = [];
  activeSessionId: number = 0;
  showSessionList: boolean = false;
  nextSessionId: number = 1;

  serverRunning: boolean = false;
  serverInfo: string = '服务未启动';
  healthStatus: string = '';
  serveSources: ServeSource[] = [];
  activeSourceId: string = '';

  contextLength: number = 0;
  threads: number = 0;
  parallel: number = 2;

  temperature: number = 0.8;
  topK: number = 40;
  topP: number = 0.95;
  repeatPenalty: number = 1.0;
  maxTokens: number = 512;

  showParamConfig: boolean = false;
  pendingLoadModel: StoredModelInfo | null = null;
}
