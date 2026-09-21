import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

// 会话记录
export interface SessionRecord {
  id: number;
  title: string;
  createdAt: number;
  updatedAt: number;
  pinned: boolean;
}

// 消息记录
export interface MessageRecord {
  id: number;
  sessionId: number;
  role: string;
  content: string;
  createdAt: number;
}

// 持久化消息（仅文本内容）
export interface PersistMessage {
  role: string;
  content: string;
}

// 消息角色
export const ROLE_USER = 'user';
export const ROLE_ASSISTANT = 'assistant';
export const ROLE_SYSTEM = 'system';

const DB_NAME = 'session.db';
const DOMAIN = 0x0000;
const TAG = 'SessionStore';

// 会话持久化数据层（RDB）：提供会话与消息的 CRUD 接口
export class SessionStore {
  private static instance: SessionStore | null = null;
  private store: relationalStore.RdbStore | null = null;
  private initialized: boolean = false;

  static getInstance(): SessionStore {
    if (SessionStore.instance === null) {
      SessionStore.instance = new SessionStore();
    }
    return SessionStore.instance;
  }

  async init(context: common.Context): Promise<void> {
    if (this.initialized) {
      return;
    }
    try {
      const config: relationalStore.StoreConfig = {
        name: DB_NAME,
        securityLevel: relationalStore.SecurityLevel.S1
      };
      this.store = await relationalStore.getRdbStore(context, config);
      await this.createTables();
      this.initialized = true;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'init failed: %{public}s', String(error));
      throw new Error('初始化会话存储失败: ' + String(error));
    }
  }

  private async createTables(): Promise<void> {
    try {
      await this.store!.executeSql(
        'CREATE TABLE IF NOT EXISTS session (' +
        'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
        'title TEXT NOT NULL, ' +
        'created_at INTEGER NOT NULL, ' +
        'updated_at INTEGER NOT NULL, ' +
        'pinned INTEGER NOT NULL DEFAULT 0)'
      );
      await this.store!.executeSql(
        'CREATE TABLE IF NOT EXISTS message (' +
        'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
        'session_id INTEGER NOT NULL, ' +
        'role TEXT NOT NULL, ' +
        'content TEXT NOT NULL, ' +
        'created_at INTEGER NOT NULL)'
      );
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'create tables failed: %{public}s', String(error));
      throw new Error('创建数据表失败: ' + String(error));
    }
    // 旧库迁移：补 pinned 列（已存在则忽略）
    try {
      await this.store!.executeSql('ALTER TABLE session ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0');
    } catch (error) {
      // 列已存在，忽略
    }
  }

  // 创建会话，返回会话 id
  async createSession(title: string): Promise<number> {
    try {
      const now = Date.now();
      const values: relationalStore.ValuesBucket = {
        'title': title.length > 0 ? title : '新会话',
        'created_at': now,
        'updated_at': now
      };
      return await this.store!.insert('session', values);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'create session failed: %{public}s', String(error));
      throw new Error('创建会话失败: ' + String(error));
    }
  }

  // 会话列表（按最近更新倒序）
  async listSessions(): Promise<SessionRecord[]> {
    try {
      const predicates = new relationalStore.RdbPredicates('session');
      predicates.orderByDesc('updated_at');
      const resultSet = await this.store!.query(predicates);
      const sessions: SessionRecord[] = [];
      while (resultSet.goToNextRow()) {
        sessions.push({
          id: resultSet.getLong(resultSet.getColumnIndex('id')),
          title: resultSet.getString(resultSet.getColumnIndex('title')),
          createdAt: resultSet.getLong(resultSet.getColumnIndex('created_at')),
          updatedAt: resultSet.getLong(resultSet.getColumnIndex('updated_at')),
          pinned: resultSet.getLong(resultSet.getColumnIndex('pinned')) !== 0
        });
      }
      resultSet.close();
      return sessions;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'list sessions failed: %{public}s', String(error));
      throw new Error('读取会话列表失败: ' + String(error));
    }
  }

  // 重命名会话
  async renameSession(id: number, title: string): Promise<void> {
    try {
      const values: relationalStore.ValuesBucket = {
        'title': title,
        'updated_at': Date.now()
      };
      const predicates = new relationalStore.RdbPredicates('session');
      predicates.equalTo('id', id);
      await this.store!.update(values, predicates);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'rename session failed: %{public}s', String(error));
      throw new Error('重命名会话失败: ' + String(error));
    }
  }

  // 删除会话及其消息
  async deleteSession(id: number): Promise<void> {
    try {
      const sessionPredicates = new relationalStore.RdbPredicates('session');
      sessionPredicates.equalTo('id', id);
      await this.store!.delete(sessionPredicates);

      const messagePredicates = new relationalStore.RdbPredicates('message');
      messagePredicates.equalTo('session_id', id);
      await this.store!.delete(messagePredicates);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'delete session failed: %{public}s', String(error));
      throw new Error('删除会话失败: ' + String(error));
    }
  }

  // 追加消息，返回消息 id；同时刷新会话 updated_at
  async addMessage(sessionId: number, role: string, content: string): Promise<number> {
    try {
      const values: relationalStore.ValuesBucket = {
        'session_id': sessionId,
        'role': role,
        'content': content,
        'created_at': Date.now()
      };
      const id = await this.store!.insert('message', values);

      const sessionValues: relationalStore.ValuesBucket = {
        'updated_at': Date.now()
      };
      const predicates = new relationalStore.RdbPredicates('session');
      predicates.equalTo('id', sessionId);
      await this.store!.update(sessionValues, predicates);

      return id;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'add message failed: %{public}s', String(error));
      throw new Error('追加消息失败: ' + String(error));
    }
  }

  // 会话消息列表（按时间正序）
  async listMessages(sessionId: number): Promise<MessageRecord[]> {
    try {
      const predicates = new relationalStore.RdbPredicates('message');
      predicates.equalTo('session_id', sessionId);
      predicates.orderByAsc('id');
      const resultSet = await this.store!.query(predicates);
      const messages: MessageRecord[] = [];
      while (resultSet.goToNextRow()) {
        messages.push({
          id: resultSet.getLong(resultSet.getColumnIndex('id')),
          sessionId: resultSet.getLong(resultSet.getColumnIndex('session_id')),
          role: resultSet.getString(resultSet.getColumnIndex('role')),
          content: resultSet.getString(resultSet.getColumnIndex('content')),
          createdAt: resultSet.getLong(resultSet.getColumnIndex('created_at'))
        });
      }
      resultSet.close();
      return messages;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'list messages failed: %{public}s', String(error));
      throw new Error('读取消息列表失败: ' + String(error));
    }
  }

  // 清空会话消息
  async clearMessages(sessionId: number): Promise<void> {
    try {
      const predicates = new relationalStore.RdbPredicates('message');
      predicates.equalTo('session_id', sessionId);
      await this.store!.delete(predicates);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'clear messages failed: %{public}s', String(error));
      throw new Error('清空消息失败: ' + String(error));
    }
  }

  // 持久化会话：按内存会话 id 写入（不存在则创建），并全量替换其消息
  async persistSession(id: number, title: string, messages: PersistMessage[], pinned: boolean): Promise<void> {
    try {
      const now = Date.now();
      const sessionPredicates = new relationalStore.RdbPredicates('session');
      sessionPredicates.equalTo('id', id);
      const resultSet = await this.store!.query(sessionPredicates);
      const exists = resultSet.goToNextRow();
      resultSet.close();

      if (exists) {
        const values: relationalStore.ValuesBucket = {
          'title': title.length > 0 ? title : '新会话',
          'updated_at': now,
          'pinned': pinned ? 1 : 0
        };
        await this.store!.update(values, sessionPredicates);
      } else {
        const values: relationalStore.ValuesBucket = {
          'id': id,
          'title': title.length > 0 ? title : '新会话',
          'created_at': now,
          'updated_at': now,
          'pinned': pinned ? 1 : 0
        };
        await this.store!.insert('session', values);
      }

      await this.clearMessages(id);
      for (const message of messages) {
        await this.addMessage(id, message.role, message.content);
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'persist session failed: %{public}s', String(error));
      throw new Error('持久化会话失败: ' + String(error));
    }
  }
}
