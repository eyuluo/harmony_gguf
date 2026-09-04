import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

// 会话记录
export interface SessionRecord {
  id: number;
  title: string;
  createdAt: number;
  updatedAt: number;
}

// 消息记录
export interface MessageRecord {
  id: number;
  sessionId: number;
  role: string;
  content: string;
  createdAt: number;
}

// 消息角色
export const ROLE_USER = 'user';
export const ROLE_ASSISTANT = 'assistant';
export const ROLE_SYSTEM = 'system';

const DB_NAME = 'session.db';

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
    const config: relationalStore.StoreConfig = {
      name: DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    this.store = await relationalStore.getRdbStore(context, config);
    await this.createTables();
    this.initialized = true;
  }

  private async createTables(): Promise<void> {
    await this.store!.executeSql(
      'CREATE TABLE IF NOT EXISTS session (' +
      'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
      'title TEXT NOT NULL, ' +
      'created_at INTEGER NOT NULL, ' +
      'updated_at INTEGER NOT NULL)'
    );
    await this.store!.executeSql(
      'CREATE TABLE IF NOT EXISTS message (' +
      'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
      'session_id INTEGER NOT NULL, ' +
      'role TEXT NOT NULL, ' +
      'content TEXT NOT NULL, ' +
      'created_at INTEGER NOT NULL)'
    );
  }

  // 创建会话，返回会话 id
  async createSession(title: string): Promise<number> {
    const now = Date.now();
    const values: relationalStore.ValuesBucket = {
      'title': title.length > 0 ? title : '新会话',
      'created_at': now,
      'updated_at': now
    };
    return await this.store!.insert('session', values);
  }

  // 会话列表（按最近更新倒序）
  async listSessions(): Promise<SessionRecord[]> {
    const predicates = new relationalStore.RdbPredicates('session');
    predicates.orderByDesc('updated_at');
    const resultSet = await this.store!.query(predicates);
    const sessions: SessionRecord[] = [];
    while (resultSet.goToNextRow()) {
      sessions.push({
        id: resultSet.getLong(resultSet.getColumnIndex('id')),
        title: resultSet.getString(resultSet.getColumnIndex('title')),
        createdAt: resultSet.getLong(resultSet.getColumnIndex('created_at')),
        updatedAt: resultSet.getLong(resultSet.getColumnIndex('updated_at'))
      });
    }
    resultSet.close();
    return sessions;
  }

  // 重命名会话
  async renameSession(id: number, title: string): Promise<void> {
    const values: relationalStore.ValuesBucket = {
      'title': title,
      'updated_at': Date.now()
    };
    const predicates = new relationalStore.RdbPredicates('session');
    predicates.equalTo('id', id);
    await this.store!.update(values, predicates);
  }

  // 删除会话及其消息
  async deleteSession(id: number): Promise<void> {
    const sessionPredicates = new relationalStore.RdbPredicates('session');
    sessionPredicates.equalTo('id', id);
    await this.store!.delete(sessionPredicates);

    const messagePredicates = new relationalStore.RdbPredicates('message');
    messagePredicates.equalTo('session_id', id);
    await this.store!.delete(messagePredicates);
  }

  // 追加消息，返回消息 id；同时刷新会话 updated_at
  async addMessage(sessionId: number, role: string, content: string): Promise<number> {
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
  }

  // 会话消息列表（按时间正序）
  async listMessages(sessionId: number): Promise<MessageRecord[]> {
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
  }

  // 清空会话消息
  async clearMessages(sessionId: number): Promise<void> {
    const predicates = new relationalStore.RdbPredicates('message');
    predicates.equalTo('session_id', sessionId);
    await this.store!.delete(predicates);
  }
}
