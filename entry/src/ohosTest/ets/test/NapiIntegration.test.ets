import { describe, beforeEach, afterEach, it, expect } from '@ohos/hypium';
import { fileIo } from '@kit.CoreFileKit';
import napi from 'libentry.so';
import { ARCHITECTURES, PRIMARY, fixturePath, requireFixture } from './M2Fixtures';
import { GenerationProbe, delay } from './M2GenerationProbe';

function expectError(action: () => void, code: number): void {
  let caught: Error | undefined = undefined;
  try {
    action();
  } catch (error) {
    caught = error as Error;
  }
  expect(caught !== undefined).message('接口必须抛出异常').assertTrue();
  if (caught !== undefined) {
    expect(caught.message).assertContain('[error ' + code.toString() + ']');
  }
}

function loadPrimary(parallel: number = 2): void {
  expect(napi.loadModel(requireFixture(PRIMARY.file), {
    contextLength: 512, threads: 2, parallel: parallel
  })).assertEqual(1);
}

export default function napiIntegrationTest() {
  describe('M2无模型接口契约', () => {
    beforeEach(() => { napi.unloadModel(1); });
    afterEach(() => { napi.unloadModel(1); });

    it('空路径解析抛出1001', 0, () => {
      expectError(() => { napi.parseGgufMetadata(''); }, 1001);
    });
    it('空路径加载抛出1001', 0, () => {
      expectError(() => { napi.loadModel(''); }, 1001);
    });
    it('不存在文件解析抛出1003', 0, () => {
      expectError(() => { napi.parseGgufMetadata(fixturePath('M2-missing.gguf')); }, 1003);
    });
    it('不存在文件加载抛出1003', 0, () => {
      expectError(() => { napi.loadModel(fixturePath('M2-missing.gguf')); }, 1003);
    });
    it('未加载生成同步抛出1002且无回调', 0, async () => {
      let callbacks = 0;
      expectError(() => { napi.generate('你好', {}, () => { callbacks++; }); }, 1002);
      await delay(100);
      expect(callbacks).assertEqual(0);
    });
    it('重复卸载和未知请求停止可安全调用', 0, () => {
      napi.unloadModel(1);
      napi.unloadModel(1);
      napi.stopGenerate(0);
      napi.stopGenerate(2147483647);
      napi.stopAllGenerations();
      expectError(() => { napi.generate('你好', {}, () => {}); }, 1002);
    });
    it('接口标识参数非法抛出1001', 0, () => {
      expectError(() => { napi.unloadModel(2); }, 1001);
      expectError(() => { napi.stopGenerate(-1); }, 1001);
    });
  });

  describe('M2真实NAPI桥接', () => {
    beforeEach(() => { napi.unloadModel(1); });
    afterEach(async () => {
      napi.stopAllGenerations();
      napi.unloadModel(1);
      await delay(100);
    });

    it('元数据字段及文件大小转换正确', 0, () => {
      const path = requireFixture(PRIMARY.file);
      const metadata = napi.parseGgufMetadata(path);
      expect(metadata.architecture).assertEqual(PRIMARY.architecture);
      expect(typeof metadata.parameters === 'string' && metadata.parameters.length > 0).assertTrue();
      expect(typeof metadata.quantization === 'string' && metadata.quantization.length > 0).assertTrue();
      expect(Number.isInteger(metadata.contextLength) && metadata.contextLength > 0).assertTrue();
      expect(['bpe', 'sentencepiece', 'wordpiece', 'unigram', 'rwkv', 'plamo2'].includes(metadata.tokenizer)).assertTrue();
      expect(metadata.fileSize).assertEqual(fileIo.statSync(path).size);
    });

    it('vocab模型仅可解析不可用于真实推理加载', 0, () => {
      const path = requireFixture('ggml-vocab-llama-bpe.gguf');
      expect(napi.parseGgufMetadata(path).architecture).assertEqual('llama');
      expectError(() => { napi.loadModel(path, { contextLength: 512 }); }, 1003);
    });

    it('加载卸载后生成返回1002', 0, () => {
      loadPrimary();
      napi.unloadModel(1);
      expectError(() => { napi.generate('你好', {}, () => {}); }, 1002);
    });

    it('非法加载和生成参数抛出1001且不占用槽位', 0, async () => {
      const path = requireFixture(PRIMARY.file);
      expectError(() => { napi.loadModel(path, { parallel: 0 }); }, 1001);
      loadPrimary(1);
      expectError(() => {
        napi.generate(PRIMARY.prompt, { topP: 2 }, () => {});
      }, 1001);
      const run = new GenerationProbe();
      run.start(PRIMARY.prompt, { maxTokens: 4 });
      await run.verify('done', 4, 1);
    });

    it('单模型切换后可以生成', 0, async () => {
      loadPrimary();
      expect(napi.loadModel(requireFixture(ARCHITECTURES[1].file), {
        contextLength: 512, threads: 2, parallel: 1
      })).assertEqual(1);
      const run = new GenerationProbe();
      run.start(ARCHITECTURES[1].prompt, { temperature: 0, maxTokens: 8 });
      await run.verify('done', 8, 1);
    });

    it('连续多token回调与统计且主线程可调度', 0, async () => {
      loadPrimary();
      const run = new GenerationProbe();
      run.start(PRIMARY.prompt, { temperature: 0, topK: 1, topP: 1, repeatPenalty: 1, maxTokens: 32, threads: 2 });
      expect(run.terminal).assertEqual('');
      let ticks = 0;
      const heartbeat = setInterval(() => { ticks++; }, 1);
      try {
        await run.finished;
        expect(ticks > 0).message('等待推理期间事件循环仍可运行').assertTrue();
        await run.verify('done', 32, 2);
      } finally {
        clearInterval(heartbeat);
      }
    });

    it('maxTokens上限与连续五次槽位复用', 0, async () => {
      loadPrimary(1);
      for (let i = 0; i < 5; i++) {
        const run = new GenerationProbe();
        run.start(PRIMARY.prompt, { temperature: 0, maxTokens: 1 });
        await run.verify('done', 1, 1);
      }
    });

    it('超长输入通过error回调返回1004且释放槽位', 0, async () => {
      loadPrimary(1);
      const failed = new GenerationProbe();
      failed.start('你好 世界 '.repeat(4096), { maxTokens: 1 });
      await failed.verify('error', 1);
      expect(failed.tokens.length).assertEqual(0);
      const next = new GenerationProbe();
      next.start(PRIMARY.prompt, { maxTokens: 4 });
      await next.verify('done', 4, 1);
    });

    it('单槽位满载同步抛出1005且不产生额外回调', 0, async () => {
      loadPrimary(1);
      const first = new GenerationProbe();
      first.start(PRIMARY.prompt, { maxTokens: 4096 });
      let rejectedCallbacks = 0;
      expectError(() => {
        napi.generate(PRIMARY.prompt, { maxTokens: 4 }, () => { rejectedCallbacks++; });
      }, 1005);
      napi.stopGenerate(first.requestId);
      await first.verify('stopped', 4096);
      expect(rejectedCallbacks).assertEqual(0);
    });

    it('两个请求并发且停止一个不影响另一个', 0, async () => {
      loadPrimary();
      const first = new GenerationProbe();
      const second = new GenerationProbe();
      first.start(PRIMARY.prompt, { maxTokens: 4096 });
      second.start(PRIMARY.prompt, { temperature: 0, maxTokens: 16 });
      expect(first.requestId !== second.requestId).assertTrue();
      napi.stopGenerate(first.requestId);
      await Promise.all([first.finished, second.finished]);
      await first.verify('stopped', 4096);
      await second.verify('done', 16, 1);
    });

    it('收到token后按requestId停止并收到唯一stopped', 0, async () => {
      loadPrimary();
      const run = new GenerationProbe();
      run.start(PRIMARY.prompt, { maxTokens: 4096 }, () => {
        if (run.tokens.length === 1) { napi.stopGenerate(run.requestId); }
      });
      await run.verify('stopped', 4096, 1);
    });

    it('stopAll结束全部请求后无需重载即可再次生成', 0, async () => {
      loadPrimary();
      const first = new GenerationProbe();
      const second = new GenerationProbe();
      first.start(PRIMARY.prompt, { maxTokens: 4096 });
      second.start(PRIMARY.prompt, { maxTokens: 4096 });
      napi.stopAllGenerations();
      await Promise.all([first.finished, second.finished]);
      await first.verify('stopped', 4096);
      await second.verify('stopped', 4096);
      const next = new GenerationProbe();
      next.start(PRIMARY.prompt, { maxTokens: 4 });
      await next.verify('done', 4, 1);
    });

    it('生成期间卸载中断全部请求并可重新加载', 0, async () => {
      loadPrimary();
      const first = new GenerationProbe();
      const second = new GenerationProbe();
      first.start(PRIMARY.prompt, { maxTokens: 4096 });
      second.start(PRIMARY.prompt, { maxTokens: 4096 });
      napi.unloadModel(1);
      await Promise.all([first.finished, second.finished]);
      await first.verify('stopped', 4096);
      await second.verify('stopped', 4096);
      loadPrimary();
      const next = new GenerationProbe();
      next.start(PRIMARY.prompt, { maxTokens: 4 });
      await next.verify('done', 4, 1);
    });
  });

  describe('M2多架构与模板冒烟', () => {
    afterEach(() => { napi.unloadModel(1); });
    for (const fixture of ARCHITECTURES) {
      it(fixture.name + '元数据加载及模板生成', 0, async () => {
        const path = requireFixture(fixture.file);
        expect(napi.parseGgufMetadata(path).architecture).assertEqual(fixture.architecture);
        expect(napi.loadModel(path, { contextLength: 512, threads: 2, parallel: 1 })).assertEqual(1);
        const run = new GenerationProbe();
        run.start(fixture.prompt, { temperature: 0, maxTokens: 8 });
        await run.verify('done', 8, 1);
      });
    }
  });
}
