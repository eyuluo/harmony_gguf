import { hilog } from '@kit.PerformanceAnalysisKit';
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import testNapi from 'libentry.so';
import { ServerInfo } from 'libentry.so';
import { AppState } from './AppState';

const DOMAIN = 0x0000;
const TAG = 'ServeService';
const BASE_URL = 'http://127.0.0.1:5160';

export class ServeService {
  private static instance: ServeService | null = null;
  private state: AppState | null = null;
  private timerId: number = -1;
  private httpRequest: http.HttpRequest = http.createHttp();
  private disposed: boolean = false;
  private healthRequestId: number = 0;

  static getInstance(): ServeService {
    if (ServeService.instance === null) {
      ServeService.instance = new ServeService();
    }
    return ServeService.instance;
  }

  init(state: AppState): void {
    this.state = state;
    this.disposed = false;
  }

  startServe(): void {
    const state = this.state!;
    if (state.modelId <= 0) {
      return;
    }
    try {
      testNapi.startServer({ host: '127.0.0.1', port: 5160 });
      this.refreshServerStatus();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'start server failed: %{public}s', String(error));
      state.serverRunning = false;
      state.serverInfo = '服务启动失败';
    }
  }

  stopServe(): void {
    const state = this.state!;
    try {
      testNapi.stopServer();
      this.refreshServerStatus();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'stop server failed: %{public}s', String(error));
      state.serverInfo = '服务停止失败';
    }
  }

  refreshServerStatus(): void {
    if (this.disposed || this.state === null) {
      return;
    }
    try {
      const state = this.state;
      const info = testNapi.getServerStatus() as ServerInfo;
      state.serverRunning = info.running;
      state.serverInfo = info.running ? `http://${info.host}:${info.port}` : '服务未启动';
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'refresh server status failed: %{public}s', String(error));
    }
  }

  startAutoCheck(): void {
    if (this.timerId >= 0) {
      return;
    }
    this.timerId = setInterval(() => {
      this.refreshServerStatus();
    }, 60000);
  }

  stopAutoCheck(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  dispose(): void {
    this.disposed = true;
    this.healthRequestId += 1;
    this.stopAutoCheck();
    this.httpRequest.destroy();
  }

  checkHealth(): void {
    const state = this.state!;
    if (!state.serverRunning) {
      state.healthStatus = '服务未运行';
      return;
    }
    const requestId = ++this.healthRequestId;
    this.httpRequest.request(`${BASE_URL}/health`, {
      method: http.RequestMethod.GET,
      connectTimeout: 3000,
      readTimeout: 5000
    }, (err: BusinessError, data: http.HttpResponse) => {
      if (this.disposed || requestId !== this.healthRequestId) {
        return;
      }
      if (err) {
        state.healthStatus = `状态异常：${err.message}`;
      } else {
        state.healthStatus = `状态正常 (HTTP ${data.responseCode})`;
      }
    });
  }
}
