import { hilog } from '@kit.PerformanceAnalysisKit';
import { taskpool } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import testNapi from 'libentry.so';
import { GenerateStats, GenerateError, TokenData, LoadConfig } from 'libentry.so';
import {
  AppState,
  Session,
  SessionMessage,
  SESSION_IDLE,
  SESSION_QUEUED,
  SESSION_RUNNING,
  SESSION_FAILED
} from './AppState';
import { StoredModelInfo } from './ModelStore';
import { loadModelTask } from './ModelTasks';
import { SessionStore, PersistMessage } from './SessionStore';

const DOMAIN = 0x0000;
const TAG = 'InferenceService';

interface SessionPatch {
  title?: string;
  status?: string;
  pinned?: boolean;
  persisted?: boolean;
  requestId?: number;
  messages?: SessionMessage[];
  lastStats?: GenerateStats | null;
}

export class InferenceService {
  private static instance: InferenceService | null = null;
  private state: AppState | null = null;

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
    if (!this.fileExists(model.path)) {
      state.loadFailed = true;
      throw new Error('模型文件不存在');
    }
    state.loading = true;
    state.loadingModelPath = model.path;
    state.loadFailed = false;
    try {
      const modelId = await taskpool.execute(loadModelTask, model.path, config.contextLength ?? 0,
        config.threads ?? 0, config.parallel ?? 8, config.mmprojPath ?? '') as number;
      state.modelId = modelId;
      state.modelInfo = model;
      state.activeModelPath = model.path;
      state.loadedConfig = config;
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
    state.serverRunning = false;
    state.serverInfo = '服务未启动';
  }

  newSession(): number {
    const state = this.state!;
    const id = state.nextSessionId;
    state.nextSessionId += 1;
    const session: Session = {
      id: id,
      title: '新对话',
      messages: [],
      status: SESSION_IDLE,
      updatedAt: Date.now(),
      pinned: false,
      persisted: false,
      lastStats: null,
      requestId: 0,
      pendingPrompt: ''
    };
    state.sessions = state.sessions.concat([session]);
    state.activeSessionId = id;
    return id;
  }

  deleteSession(sessionId: number): void {
    const state = this.state!;
    const target = this.findSession(sessionId);
    if (target !== null && (target.status === SESSION_RUNNING || target.status === SESSION_QUEUED)) {
      if (target.requestId > 0) {
        testNapi.stopGenerate(target.requestId);
      }
    }
    const remaining: Session[] = [];
    for (const s of state.sessions) {
      if (s.id !== sessionId) {
        remaining.push(s);
      }
    }
    state.sessions = remaining;
    if (state.activeSessionId === sessionId) {
      state.activeSessionId = remaining.length > 0 ? remaining[0].id : 0;
    }
    SessionStore.getInstance().deleteSession(sessionId).catch((error: Error) => {
      hilog.error(DOMAIN, TAG, 'delete persisted session failed: %{public}s', String(error));
    });
  }

  async restoreSessions(): Promise<void> {
    const store = SessionStore.getInstance();
    try {
      const records = await store.listSessions();
      const sessions: Session[] = [];
      let maxId = 0;
      for (const rec of records) {
        const messageRecords = await store.listMessages(rec.id);
        const messages: SessionMessage[] = [];
        for (const m of messageRecords) {
          messages.push({ role: m.role, content: m.content, attachments: [] });
        }
        sessions.push({
          id: rec.id,
          title: rec.title,
          messages: messages,
          status: SESSION_IDLE,
          updatedAt: rec.updatedAt,
          pinned: rec.pinned,
          persisted: true,
          lastStats: null,
          requestId: 0,
          pendingPrompt: ''
        });
        if (rec.id > maxId) {
          maxId = rec.id;
        }
      }
      const state = this.state!;
      state.sessions = sessions;
      state.nextSessionId = maxId + 1;
      state.activeSessionId = sessions.length > 0 ? sessions[0].id : 0;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'restore sessions failed: %{public}s', String(error));
    }
  }

  async persistSession(sessionId: number): Promise<void> {
    const session = this.findSession(sessionId);
    if (session === null) {
      return;
    }
    await this.writeSessionToStore(session);
    this.replaceSession(this.copyWith(session, { persisted: true }));
  }

  private async syncPersistedSession(sessionId: number): Promise<void> {
    const session = this.findSession(sessionId);
    if (session === null) {
      return;
    }
    await this.writeSessionToStore(session);
  }

  private async writeSessionToStore(session: Session): Promise<void> {
    const messages: PersistMessage[] = [];
    for (const m of session.messages) {
      messages.push({ role: m.role, content: m.content });
    }
    try {
      await SessionStore.getInstance().persistSession(session.id, session.title, messages, session.pinned);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'persist session failed: %{public}s', String(error));
    }
  }

  renameSession(sessionId: number, title: string): void {
    const session = this.findSession(sessionId);
    if (session === null) {
      return;
    }
    this.replaceSession(this.copyWith(session, { title: title }));
    if (session.persisted) {
      this.syncPersistedSession(sessionId);
    }
  }

  togglePin(sessionId: number): void {
    const session = this.findSession(sessionId);
    if (session === null) {
      return;
    }
    this.replaceSession(this.copyWith(session, { pinned: !session.pinned }));
    if (session.persisted) {
      this.syncPersistedSession(sessionId);
    }
  }

  generate(sessionId: number, prompt: string, attachments: string[]): void {
    const state = this.state!;
    if (state.modelId === 0 || (prompt.trim().length === 0 && attachments.length === 0)) {
      return;
    }
    const session = this.findSession(sessionId);
    if (session === null) {
      return;
    }
    if (session.status === SESSION_RUNNING || session.status === SESSION_QUEUED) {
      return;
    }
    const userMessage: SessionMessage = { role: 'user', content: prompt, attachments: attachments };
    const assistantMessage: SessionMessage = { role: 'assistant', content: '', attachments: [] };
    const messages = session.messages.concat([userMessage, assistantMessage]);
    let title = session.title;
    if (title === '新对话' && session.messages.length === 0) {
      if (prompt.length > 0) {
        title = prompt.length > 20 ? prompt.substring(0, 20) : prompt;
      } else {
        title = '发送了图片';
      }
    }
    this.replaceSession({
      id: session.id,
      title: title,
      messages: messages,
      status: SESSION_RUNNING,
      updatedAt: Date.now(),
      pinned: session.pinned,
      persisted: session.persisted,
      lastStats: session.lastStats,
      requestId: 0,
      pendingPrompt: prompt
    });

    if (this.runningCount() >= state.parallel) {
      this.updateStatus(sessionId, SESSION_QUEUED);
      return;
    }
    this.startGenerate(sessionId, prompt);
  }

  stopGeneration(sessionId: number): void {
    const session = this.findSession(sessionId);
    if (session === null) {
      return;
    }
    if (session.status === SESSION_QUEUED) {
      this.updateStatus(sessionId, SESSION_IDLE);
      return;
    }
    if (session.requestId > 0) {
      testNapi.stopGenerate(session.requestId);
    }
  }

  private startGenerate(sessionId: number, prompt: string): void {
    const state = this.state!;
    let images: string[] = [];
    const session = this.findSession(sessionId);
    if (session !== null) {
      for (let i = session.messages.length - 1; i >= 0; i--) {
        if (session.messages[i].role === 'user') {
          images = session.messages[i].attachments;
          break;
        }
      }
    }
    try {
      const requestId = testNapi.generate(prompt, {
        maxTokens: state.maxTokens,
        temperature: state.temperature,
        topK: state.topK,
        topP: state.topP,
        repeatPenalty: state.repeatPenalty,
        threads: state.threads,
        images: images
      }, (event: string, data: object) => {
        this.onGenerateEvent(sessionId, event, data);
      });
      this.updateRequestId(sessionId, requestId);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'generate failed: %{public}s', String(error));
      this.updateStatus(sessionId, SESSION_FAILED);
      this.dequeueNext();
    }
  }

  private onGenerateEvent(sessionId: number, event: string, data: object): void {
    const session = this.findSession(sessionId);
    if (session === null) {
      return;
    }
    const updated: Session = {
      id: session.id,
      title: session.title,
      messages: session.messages,
      status: session.status,
      updatedAt: Date.now(),
      pinned: session.pinned,
      persisted: session.persisted,
      lastStats: session.lastStats,
      requestId: session.requestId,
      pendingPrompt: session.pendingPrompt
    };
    if (event === 'token') {
      const last = updated.messages.length - 1;
      if (last >= 0) {
        const nextMessages = updated.messages.slice();
        nextMessages[last] = {
          role: 'assistant',
          content: nextMessages[last].content + (data as TokenData).text,
          attachments: nextMessages[last].attachments
        };
        updated.messages = nextMessages;
      }
    } else if (event === 'done' || event === 'stopped') {
      updated.lastStats = data as GenerateStats;
      updated.status = SESSION_IDLE;
      updated.requestId = 0;
      updated.pendingPrompt = '';
    } else if (event === 'error') {
      updated.status = SESSION_FAILED;
      updated.requestId = 0;
      updated.pendingPrompt = '';
    }
    this.replaceSession(updated);
    if (event === 'done' || event === 'stopped' || event === 'error') {
      if (session.persisted) {
        this.syncPersistedSession(sessionId);
      }
      this.dequeueNext();
    }
  }

  private dequeueNext(): void {
    const state = this.state!;
    const queued = this.findQueued();
    if (queued === null) {
      return;
    }
    this.updateStatus(queued.id, SESSION_RUNNING);
    this.startGenerate(queued.id, queued.pendingPrompt);
  }

  private runningCount(): number {
    const state = this.state!;
    let count = 0;
    for (const s of state.sessions) {
      if (s.status === SESSION_RUNNING) {
        count += 1;
      }
    }
    return count;
  }

  private findQueued(): Session | null {
    const state = this.state!;
    for (const s of state.sessions) {
      if (s.status === SESSION_QUEUED) {
        return s;
      }
    }
    return null;
  }

  private findSession(sessionId: number): Session | null {
    const state = this.state!;
    for (const s of state.sessions) {
      if (s.id === sessionId) {
        return s;
      }
    }
    return null;
  }

  private updateStatus(sessionId: number, status: string): void {
    const session = this.findSession(sessionId);
    if (session === null) {
      return;
    }
    this.replaceSession(this.copyWith(session, { status: status }));
  }

  private updateRequestId(sessionId: number, requestId: number): void {
    const session = this.findSession(sessionId);
    if (session === null) {
      return;
    }
    this.replaceSession(this.copyWith(session, { requestId: requestId }));
  }

  private copyWith(session: Session, patch: SessionPatch): Session {
    const result: Session = {
      id: session.id,
      title: session.title,
      messages: session.messages,
      status: session.status,
      updatedAt: session.updatedAt,
      pinned: session.pinned,
      persisted: session.persisted,
      lastStats: session.lastStats,
      requestId: session.requestId,
      pendingPrompt: session.pendingPrompt
    };
    if (patch.title !== undefined) {
      result.title = patch.title;
    }
    if (patch.status !== undefined) {
      result.status = patch.status;
    }
    if (patch.pinned !== undefined) {
      result.pinned = patch.pinned;
    }
    if (patch.persisted !== undefined) {
      result.persisted = patch.persisted;
    }
    if (patch.requestId !== undefined) {
      result.requestId = patch.requestId;
    }
    if (patch.messages !== undefined) {
      result.messages = patch.messages;
    }
    if (patch.lastStats !== undefined) {
      result.lastStats = patch.lastStats;
    }
    return result;
  }

  private replaceSession(session: Session): void {
    const state = this.state!;
    const next: Session[] = [];
    for (const s of state.sessions) {
      next.push(s.id === session.id ? session : s);
    }
    state.sessions = next;
  }

  private fileExists(path: string): boolean {
    try {
      return fileIo.accessSync(path);
    } catch (error) {
      return false;
    }
  }
}
