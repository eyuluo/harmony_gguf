import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import napi from 'libentry.so';

export default function napiIntegrationTest() {
  describe('NAPI集成测试', () => {
    // ---- 模型管理接口 ----
    describe('parseGgufMetadata', () => {
      it('解析有效GGUF文件返回元数据', 0, () => {
        const metadata = napi.parseGgufMetadata('/data/test/ggml-vocab-llama-bpe.gguf');
        expect(metadata).assertLabeled('ModelMetadata');
        expect(metadata.architecture).assertEqual('llama');
        expect(metadata.contextLength).assertGreaterThan(0);
        expect(metadata.fileSize).assertGreaterThan(0);
      });

      it('解析不存在的文件应抛出错误', 0, () => {
        try {
          napi.parseGgufMetadata('/data/nonexistent.gguf');
          expect(true).assertFail('应抛出异常');
        } catch (e) {
          expect(e).assertLabeled('Error');
        }
      });
    });

    describe('loadModel', () => {
      it('加载有效模型返回正数modelId', 0, () => {
        const modelId = napi.loadModel('/data/test/ggml-vocab-llama-bpe.gguf');
        expect(modelId).assertGreaterThan(0);
        napi.unloadModel(modelId);
      });

      it('加载不存在的文件返回错误码', 0, () => {
        const result = napi.loadModel('/data/nonexistent.gguf');
        expect(result).assertLessThanOrEqual(0);
      });
    });

    describe('unloadModel', () => {
      it('卸载已加载模型不报错', 0, () => {
        const modelId = napi.loadModel('/data/test/ggml-vocab-llama-bpe.gguf');
        napi.unloadModel(modelId);
        expect(true).assertTrue();
      });

      it('卸载无效modelId不崩溃', 0, () => {
        napi.unloadModel(99999);
        expect(true).assertTrue();
      });
    });

    // ---- 推理接口 ----
    describe('generate', () => {
      let modelId: number;

      beforeAll(() => {
        modelId = napi.loadModel('/data/test/ggml-vocab-llama-bpe.gguf', {
          contextLength: 512,
          threads: 2,
        });
      });

      afterAll(() => {
        napi.unloadModel(modelId);
      });

      it('流式生成返回token回调', 0, (done: Function) => {
        let tokenCount = 0;
        let doneReceived = false;

        napi.generate('Hello', {
          temperature: 0.8,
          topK: 50,
          topP: 0.9,
          maxTokens: 10,
        }, (event: string, data: object) => {
          if (event === 'token') {
            tokenCount++;
            expect(data).assertLabeled('TokenData');
            expect((data as napi.TokenData).text).assertType('string');
          } else if (event === 'done') {
            doneReceived = true;
            expect(data).assertLabeled('GenerateStats');
            expect(tokenCount).assertGreaterThan(0);
            expect((data as napi.GenerateStats).generatedTokens).assertEqual(tokenCount);
            done();
          } else if (event === 'error') {
            expect(data).assertLabeled('GenerateError');
            done();
          }
        });
      });

      it('空prompt不崩溃', 0, (done: Function) => {
        napi.generate('', {
          maxTokens: 1,
        }, (event: string, data: object) => {
          if (event === 'done' || event === 'error') {
            done();
          }
        });
      });
    });

    describe('stopGenerate', () => {
      it('停止生成后不再收到token回调', 0, (done: Function) => {
        let tokenCount = 0;
        const modelId = napi.loadModel('/data/test/ggml-vocab-llama-bpe.gguf');

        napi.generate('Hello world test', {
          maxTokens: 100,
        }, (event: string, data: object) => {
          if (event === 'token') {
            tokenCount++;
            if (tokenCount === 2) {
              napi.stopGenerate();
            }
          } else if (event === 'done' || event === 'error') {
            expect(tokenCount).assertLessThanOrEqual(5);
            napi.unloadModel(modelId);
            done();
          }
        });
      });
    });

    // ---- Serve 接口（阶段5预写） ----
    describe('startServer/stopServer', () => {
      it('启动和停止Serve服务', 0, () => {
        napi.startServer({ host: '127.0.0.1', port: 18080 });
        const info = napi.getServerStatus();
        expect(info.running).assertTrue();
        expect(info.port).assertEqual(18080);

        napi.stopServer();
        const info2 = napi.getServerStatus();
        expect(info2.running).assertFalse();
      });
    });
  });
}
