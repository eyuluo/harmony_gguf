import { hilog } from '@kit.PerformanceAnalysisKit';
import { taskpool } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
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
import { loadModelTask, unloadModelTask } from './ModelTasks';
import { MessageRecord, SessionStore } from './SessionStore';

const DOMAIN = 0x0000;
const TAG = 'InferenceService';

interface SessionPatch {
  title?: string;
  status?: string;
  pinned?: boolean;
  persistent?: boolean;
  requestId?: number;
  messages?: SessionMessage[];
  lastStats?: GenerateStats | null;
  pendingPrompt?: string;
}

interface ChatPromptMessage {
  role: string;
  content: string;
}

export class InferenceService {
  private static instance: InferenceService | null = null;
  private state: AppState | null = null;
  private context: common.Context | null = null;
  private persistChain: Promise<void> = Promise.resolve();
  private nextMessageId: number = 1;
  private slotRetryCounts: Map<number, number> = new Map();
  private slotRetryTimer: number = -1;
  private generationQueue: number[] = [];

  static getInstance(): InferenceService {
    if (InferenceService.instance === null) {
      InferenceService.instance = new InferenceService();
    }
    return InferenceService.instance;
  }

  init(state: AppState, context: common.Context): void {
    this.state = state;
    this.context = context;
  }

  async restoreSessions(): Promise<void> {
    if (this.context === null) {
      return;
    }
    const store = SessionStore.getInstance();
    await store.init(this.context);
    const records = await store.listSessions();
    const restored: Session[] = [];
    let nextId = 1;
    for (const record of records) {
      const messages = await store.listMessages(record.id);
      const restoredMessages: SessionMessage[] = [];
      for (const message of messages) {
        restoredMessages.push({
          id: this.nextMessageId++,
          role: message.role,
          content: message.content,
          attachments: message.attachments,
          contentParts: []
        });
      }
      restored.push({
        id: record.id,
        title: record.title,
        messages: restoredMessages,
        status: SESSION_IDLE,
        createdAt: record.createdAt,
        updatedAt: record.updatedAt,
        pinned: record.pinned,
        persistent: true,
        lastStats: null,
        totalInputTokens: record.totalInputTokens,
        totalOutputTokens: record.totalOutputTokens,
        requestId: 0,
        pendingPrompt: ''
      });
      nextId = Math.max(nextId, record.id + 1);
    }
    const state = this.state!;
    state.sessions = restored;
    state.activeSessionId = restored.length > 0 ? restored[0].id : 0;
    state.nextSessionId = nextId;
  }

  async loadModel(model: StoredModelInfo, config: LoadConfig): Promise<void> {
    const state = this.state!;
    if (state.loading) {
      return;
    }
    if (state.activeModelPath === model.path && state.modelId > 0 && this.sameLoadConfig(state.loadedConfig, config)) {
      return;
    }
    state.loading = true;
    this.cancelQueuedGenerations();
    state.loadingModelPath = model.path;
    state.loadFailed = false;
    try {
      const modelId = await taskpool.execute(loadModelTask, model.path, config.contextLength ?? 0,
        config.threads ?? 0, config.parallel ?? 1, config.mmprojPath ?? '', config.imageMaxTokens ?? 1024,
        config.useNpu ?? true) as number;
      state.modelId = modelId;
      state.modelInfo = model;
      state.activeModelPath = model.path;
      state.loadedConfig = config;
      this.refreshAccelerationStatus();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'load model failed: %{public}s', String(error));
      state.modelId = 0;
      state.modelInfo = null;
      state.activeModelPath = '';
      state.loadedConfig = null;
      state.loadFailed = true;
      state.accelerationSummary = '';
      state.accelerationDetail = '';
    } finally {
      state.loading = false;
      state.loadingModelPath = '';
    }
  }

  unload(): void {
    const state = this.state!;
    if (state.loading || state.modelId <= 0) {
      return;
    }
    const modelId = state.modelId;
    state.loading = true;
    this.cancelQueuedGenerations();
    state.loadingModelPath = state.activeModelPath;
    taskpool.execute(unloadModelTask, modelId).then(() => {
      state.modelId = 0;
      state.modelInfo = null;
      state.activeModelPath = '';
      state.loadedConfig = null;
      state.serverRunning = false;
      state.serverInfo = '服务未启动';
      state.healthStatus = '';
      state.loadFailed = false;
      state.accelerationSummary = '';
      state.accelerationDetail = '';
      state.models = state.models.slice();
    }).catch((error: Error) => {
      hilog.error(DOMAIN, TAG, 'unload model failed: %{public}s', String(error));
    }).finally(() => {
      state.loading = false;
      state.loadingModelPath = '';
    });
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
      createdAt: Date.now(),
      updatedAt: Date.now(),
      pinned: false,
      persistent: false,
      lastStats: null,
      totalInputTokens: 0,
      totalOutputTokens: 0,
      requestId: 0,
      pendingPrompt: ''
    };
    state.sessions = state.sessions.concat([session]);
    state.activeSessionId = id;
    return id;
  }

  async deleteSession(sessionId: number): Promise<void> {
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
    this.slotRetryCounts.delete(sessionId);
    testNapi.deleteConversation(sessionId);
    this.generationQueue = this.generationQueue.filter((id: number) => id !== sessionId);
    if (state.activeSessionId === sessionId) {
      state.activeSessionId = remaining.length > 0 ? remaining[0].id : 0;
    }
    await this.removePersistedSession(sessionId);
  }

  renameSession(sessionId: number, title: string): void {
    const session = this.findSession(sessionId);
    if (session === null) {
      return;
    }
    const nextTitle = title.trim();
    if (nextTitle.length === 0) {
      return;
    }
    this.replaceSession(this.copyWith(session, { title: nextTitle }));
  }

  togglePin(sessionId: number): void {
    const session = this.findSession(sessionId);
    if (session === null) {
      return;
    }
    this.replaceSession(this.copyWith(session, { pinned: !session.pinned }));
  }

  enablePersistence(sessionId: number): void {
    const session = this.findSession(sessionId);
    if (session === null || session.persistent) {
      return;
    }
    this.replaceSession(this.copyWith(session, { persistent: true }));
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
    const userMessage: SessionMessage = {
      id: this.nextMessageId++, role: 'user', content: prompt, attachments: attachments, contentParts: []
    };
    const assistantMessage: SessionMessage = {
      id: this.nextMessageId++, role: 'assistant', content: '', attachments: [], contentParts: []
    };
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
      status: SESSION_QUEUED,
      createdAt: session.createdAt,
      updatedAt: Date.now(),
      pinned: session.pinned,
      persistent: session.persistent,
      lastStats: session.lastStats,
      totalInputTokens: session.totalInputTokens,
      totalOutputTokens: session.totalOutputTokens,
      requestId: 0,
      pendingPrompt: prompt
    });

    this.generationQueue.push(sessionId);
    this.dequeueNext();
  }

  stopGeneration(sessionId: number): void {
    const session = this.findSession(sessionId);
    if (session === null) {
      return;
    }
    if (session.status === SESSION_QUEUED) {
      this.slotRetryCounts.delete(sessionId);
      this.generationQueue = this.generationQueue.filter((id: number) => id !== sessionId);
      this.updateStatus(sessionId, SESSION_IDLE);
      this.dequeueNext();
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
      const generationPrompt = session === null ? prompt : this.buildPrompt(session);
      const requestId = testNapi.generate(generationPrompt, {
        conversationId: sessionId,
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
      this.slotRetryCounts.delete(sessionId);
      this.updateRequestId(sessionId, requestId);
    } catch (error) {
      const reason = String(error);
      const code = (error as GenerateError).code;
      if (Number(code) === 1005 || reason.indexOf('error 1005') >= 0) {
        const attempts = (this.slotRetryCounts.get(sessionId) ?? 0) + 1;
        if (state.modelId > 0 && !state.loading) {
          this.slotRetryCounts.set(sessionId, attempts);
          this.updateStatus(sessionId, SESSION_QUEUED);
          this.generationQueue.unshift(sessionId);
          this.scheduleSlotRetry();
          return;
        }
      }
      this.slotRetryCounts.delete(sessionId);
      hilog.error(DOMAIN, TAG, 'generate failed: %{public}s', String(error));
      this.failGeneration(sessionId, String(error));
      this.dequeueNext();
    }
  }

  private failGeneration(sessionId: number, reason: string): void {
    const session = this.findSession(sessionId);
    if (session === null) {
      return;
    }
    let messages = session.messages;
    const last = messages.length - 1;
    if (last >= 0) {
      const message = messages[last];
      if (message.role === 'assistant' && message.content.length === 0 && message.contentParts.length === 0) {
        messages = messages.slice();
        messages[last] = {
          id: message.id,
          role: message.role,
          content: '',
          error: `推理启动失败：${reason}`,
          attachments: [],
          contentParts: []
        };
      }
    }
    this.replaceSession(this.copyWith(session, {
      messages: messages,
      status: SESSION_FAILED,
      requestId: 0,
      pendingPrompt: ''
    }));
  }

  private onGenerateEvent(sessionId: number, event: string, data: object): void {
    const session = this.findSession(sessionId);
    if (session === null) {
      if (event === 'done' || event === 'stopped' || event === 'error') {
        this.dequeueNext();
      }
      return;
    }
    const updated: Session = {
      id: session.id,
      title: session.title,
      messages: session.messages,
      status: session.status,
      createdAt: session.createdAt,
      updatedAt: Date.now(),
      pinned: session.pinned,
      persistent: session.persistent,
      lastStats: session.lastStats,
      totalInputTokens: session.totalInputTokens,
      totalOutputTokens: session.totalOutputTokens,
      requestId: session.requestId,
      pendingPrompt: session.pendingPrompt
    };
    if (event === 'token') {
      const last = updated.messages.length - 1;
      if (last >= 0) {
        const nextMessages = updated.messages.slice();
        const message = nextMessages[last];
        const parts = message.contentParts.slice();
        const text = (data as TokenData).text;
        parts.push(text);
        nextMessages[last] = {
          id: message.id,
          role: 'assistant',
          content: message.content + text,
          attachments: message.attachments,
          contentParts: parts
        };
        updated.messages = nextMessages;
      }
    } else if (event === 'done' || event === 'stopped') {
      this.finalizeStreamingMessage(updated);
      updated.lastStats = data as GenerateStats;
      updated.totalInputTokens += updated.lastStats.promptTokens;
      updated.totalOutputTokens += updated.lastStats.generatedTokens;
      updated.status = SESSION_IDLE;
      updated.requestId = 0;
      updated.pendingPrompt = '';
    } else if (event === 'error') {
      this.finalizeStreamingMessage(updated);
      const error = data as GenerateError;
      hilog.error(DOMAIN, TAG, '推理失败 %{public}d：%{public}s', error.code, error.message);
      const nextMessages = updated.messages.slice();
      const last = nextMessages.length - 1;
      if (last >= 0 && nextMessages[last].content.length === 0) {
        const message = nextMessages[last];
        nextMessages[last] = {
          id: message.id,
          role: message.role,
          content: message.content,
          error: `推理失败（${error.code}）：${error.message}`,
          attachments: message.attachments,
          contentParts: []
        };
        updated.messages = nextMessages;
      }
      updated.status = SESSION_FAILED;
      updated.requestId = 0;
      updated.pendingPrompt = '';
    }
    this.replaceSession(updated, event !== 'token');
    if (event === 'done' || event === 'stopped' || event === 'error') {
      if (this.runningCount() === 0) {
        this.refreshAccelerationStatus();
      }
      this.dequeueNext();
    }
  }

  private refreshAccelerationStatus(): void {
    const state = this.state!;
    try {
      const status = testNapi.getAccelerationStatus();
      if (!status.enabled) {
        state.accelerationSummary = 'CPU 推理';
        state.accelerationDetail = 'NPU 加速已关闭，本次加载使用 CPU 计算。';
        return;
      }
      if (!status.available) {
        state.accelerationSummary = 'CPU 推理 · NPU 不可用';
        state.accelerationDetail = 'NPU 加速已开启，但未检测到可用的 NPU 计算设备。本次加载使用 CPU 计算。' +
          (status.lastError.length > 0 ? '\n检测结果：' + status.lastError : '');
        return;
      }
      state.accelerationSummary = status.executions > 0 ?
        `CPU + NPU · 已采用 ${status.executions} 次 NPU 结果` : 'CPU 推理 · 尚未采用 NPU 结果';
      let detail = `检测到的 NPU：${status.device}\n` +
        (status.executions > 0 ? '本次加载期间，部分计算已采用 NPU 结果，其余计算由 CPU 完成。' :
          'NPU 已开启且设备可用，但截至最近一次更新，尚未采用 NPU 计算结果。') +
        `\n\n采用 NPU 结果的计算次数：${status.executions}\n` +
        `尝试 NPU 后改由 CPU 完成的次数：${status.fallbacks}\n` +
        `未分配给 NPU、直接由 CPU 完成的计算图次数：${status.cpuGraphs}`;
      if (status.lastCpuMs > 0) {
        detail += `\n\n最近一次局部计算对照：\nNPU ${status.lastNpuMs.toFixed(1)} ms / CPU ${status.lastCpuMs.toFixed(1)} ms` +
          '\n此耗时仅对应被比较的计算部分，不是整条回复耗时。';
      }
      if (status.lastError.length > 0) {
        detail += '\n\n最近一次检测或回退说明：' + status.lastError;
      } else if (status.executions === 0 && status.cpuGraphs > 0) {
        detail += '\n\n已处理的计算尚未满足 NPU 的支持、规模或性能条件。';
      }
      state.accelerationDetail = detail;
    } catch (error) {
      hilog.warn(DOMAIN, TAG, '读取加速状态失败：%{public}s', String(error));
      state.accelerationSummary = '加速状态读取失败';
      state.accelerationDetail = '';
    }
  }

  private dequeueNext(): void {
    const state = this.state!;
    if (state.modelId === 0 || state.loading || this.runningCount() >= (state.loadedConfig?.parallel ?? 1)) {
      return;
    }
    const queued = this.findQueued();
    if (queued === null) {
      return;
    }
    this.updateStatus(queued.id, SESSION_RUNNING);
    this.generationQueue = this.generationQueue.filter((id: number) => id !== queued.id);
    this.startGenerate(queued.id, queued.pendingPrompt);
    if (this.findSession(queued.id)?.status === SESSION_RUNNING) {
      this.dequeueNext();
    }
  }

  private scheduleSlotRetry(): void {
    if (this.slotRetryTimer >= 0) {
      return;
    }
    const config = this.state!.loadedConfig;
    this.slotRetryTimer = setTimeout(() => {
      this.slotRetryTimer = -1;
      if (this.state!.loadedConfig !== config) {
        const queued = this.findQueued();
        if (queued !== null) {
          this.failGeneration(queued.id, '模型已切换，请重新发送');
        }
        this.slotRetryCounts.clear();
        return;
      }
      this.dequeueNext();
    }, 250);
  }

  private cancelQueuedGenerations(): void {
    if (this.slotRetryTimer >= 0) {
      clearTimeout(this.slotRetryTimer);
      this.slotRetryTimer = -1;
    }
    for (const id of this.generationQueue) {
      const session = this.findSession(id);
      if (session !== null && session.status === SESSION_QUEUED) {
        this.updateStatus(id, SESSION_IDLE);
      }
    }
    this.generationQueue = [];
    this.slotRetryCounts.clear();
  }

  private buildPrompt(session: Session): string {
    const messages: ChatPromptMessage[] = [];
    for (let index = 0; index < session.messages.length - 1; index++) {
      const message = session.messages[index];
      let content = message.content;
      if (index === session.messages.length - 2 && message.role === 'user' && message.attachments.length > 0) {
        content = '<__media__>'.repeat(message.attachments.length) + '\n' +
          (content.length > 0 ? content : '请描述图片。');
      }
      if (content.length === 0) {
        continue;
      }
      messages.push({ role: message.role, content: content });
    }
    return testNapi.formatChatPrompt(messages);
  }

  private finalizeStreamingMessage(session: Session): void {
    const last = session.messages.length - 1;
    if (last < 0) {
      return;
    }
    const message = session.messages[last];
    if (message.contentParts.length === 0) {
      return;
    }
    const messages = session.messages.slice();
      messages[last] = {
      id: message.id,
      role: message.role,
      content: message.contentParts.join(''),
      attachments: message.attachments,
      contentParts: []
    };
    session.messages = messages;
  }

  private sameLoadConfig(previous: LoadConfig | null, next: LoadConfig): boolean {
    if (previous === null) {
      return false;
    }
    return (previous.contextLength ?? 0) === (next.contextLength ?? 0) &&
      (previous.threads ?? 0) === (next.threads ?? 0) &&
      (previous.parallel ?? 1) === (next.parallel ?? 1) &&
      (previous.mmprojPath ?? '') === (next.mmprojPath ?? '') &&
      (previous.imageMaxTokens ?? 1024) === (next.imageMaxTokens ?? 1024) &&
      (previous.useNpu ?? true) === (next.useNpu ?? true);
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
    for (const id of this.generationQueue) {
      const s = this.findSession(id);
      if (s !== null && s.status === SESSION_QUEUED) {
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
      createdAt: session.createdAt,
      updatedAt: session.updatedAt,
      pinned: session.pinned,
      persistent: session.persistent,
      lastStats: session.lastStats,
      totalInputTokens: session.totalInputTokens,
      totalOutputTokens: session.totalOutputTokens,
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
    if (patch.persistent !== undefined) {
      result.persistent = patch.persistent;
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
    if (patch.pendingPrompt !== undefined) {
      result.pendingPrompt = patch.pendingPrompt;
    }
    return result;
  }

  private replaceSession(session: Session, persist: boolean = true): void {
    const state = this.state!;
    const next: Session[] = [];
    for (const s of state.sessions) {
      next.push(s.id === session.id ? session : s);
    }
    state.sessions = next;
    state.sessionVersion += 1;
    if (persist && session.persistent) {
      this.persistSession(session);
    }
  }

  private persistSession(session: Session): void {
    if (this.context === null) {
      return;
    }
    this.persistChain = this.persistChain.then(async () => {
      const store = SessionStore.getInstance();
      await store.init(this.context!);
      await store.saveSession({
        id: session.id,
        title: session.title,
        createdAt: session.createdAt,
        updatedAt: session.updatedAt,
        pinned: session.pinned,
        totalInputTokens: session.totalInputTokens,
        totalOutputTokens: session.totalOutputTokens
      });
      const messages: MessageRecord[] = [];
      for (let index = 0; index < session.messages.length; index++) {
        const message = session.messages[index];
        messages.push({
          id: index + 1,
          sessionId: session.id,
          role: message.role,
          content: message.content,
          attachments: message.attachments,
          createdAt: session.createdAt + index
        });
      }
      await store.replaceMessages(session.id, messages);
    }).catch((error: Error) => {
      hilog.error(DOMAIN, TAG, 'persist session failed: %{public}s', String(error));
    });
  }

  private async removePersistedSession(sessionId: number): Promise<void> {
    if (this.context === null) {
      return;
    }
    this.persistChain = this.persistChain.then(async () => {
      const store = SessionStore.getInstance();
      await store.init(this.context!);
      await store.deleteSession(sessionId);
    }).catch((error: Error) => {
      hilog.error(DOMAIN, TAG, 'delete persisted session failed: %{public}s', String(error));
    });
    await this.persistChain;
  }
}
