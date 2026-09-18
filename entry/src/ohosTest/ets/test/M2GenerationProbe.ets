import { expect } from '@ohos/hypium';
import napi, { GenerateParams, GenerateEvent, GenerateStats, GenerateError, TokenData } from 'libentry.so';

export function delay(ms: number): Promise<void> {
  return new Promise<void>((resolve) => { setTimeout(resolve, ms); });
}

export class GenerationProbe {
  requestId: number = 0;
  tokens: string[] = [];
  terminal: string = '';
  terminalCount: number = 0;
  lateEvents: number = 0;
  malformedTokens: number = 0;
  timedOut: boolean = false;
  stats: GenerateStats | undefined = undefined;
  error: GenerateError | undefined = undefined;
  finished: Promise<void> = Promise.resolve();
  private resolveFinished: () => void = () => {};
  private timer: number = -1;

  start(prompt: string, params: GenerateParams, onToken?: () => void): void {
    this.finished = new Promise<void>((resolve) => { this.resolveFinished = resolve; });
    this.timer = setTimeout(() => {
      this.timedOut = true;
      napi.stopGenerate(this.requestId);
      this.resolveFinished();
    }, 60000);
    try {
      this.requestId = napi.generate(prompt, params,
        (event: GenerateEvent, data: TokenData | GenerateStats | GenerateError) => {
          if (this.terminal !== '') {
            this.lateEvents++;
          }
          if (event === 'token') {
            const text = (data as TokenData).text;
            if (typeof text !== 'string' || text.length === 0 || text.indexOf('\uFFFD') >= 0) {
              this.malformedTokens++;
            }
            this.tokens.push(text);
            if (onToken !== undefined) { onToken(); }
            return;
          }
          this.terminalCount++;
          this.terminal = event;
          if (event === 'error') {
            this.error = data as GenerateError;
          } else {
            this.stats = data as GenerateStats;
          }
          clearTimeout(this.timer);
          this.resolveFinished();
        });
    } catch (error) {
      clearTimeout(this.timer);
      throw error as Error;
    }
  }

  async verify(expected: string, maxTokens: number, minimumTokens: number = 0): Promise<void> {
    await this.finished;
    await delay(100);
    expect(this.timedOut).message('60 秒内必须收到终态').assertFalse();
    expect(this.requestId > 0 && Number.isInteger(this.requestId)).assertTrue();
    expect(this.terminal).message(this.error === undefined ? '终态类型' : this.error.message).assertEqual(expected);
    expect(this.terminalCount).message('只能收到一次终态').assertEqual(1);
    expect(this.lateEvents).message('终态后不得再回调').assertEqual(0);
    expect(this.malformedTokens).message('token 必须为有效 UTF-8 文本').assertEqual(0);
    expect(this.tokens.length >= minimumTokens).assertTrue();
    if (expected === 'error') {
      expect(this.error !== undefined).assertTrue();
      if (this.error !== undefined) {
        expect(this.error.code).assertEqual(1004);
        expect(this.error.message.length > 0).assertTrue();
      }
      return;
    }
    expect(this.stats !== undefined).assertTrue();
    if (this.stats !== undefined) {
      expect(Number.isInteger(this.stats.promptTokens) && this.stats.promptTokens > 0).assertTrue();
      expect(Number.isInteger(this.stats.generatedTokens)).assertTrue();
      expect(this.stats.generatedTokens >= this.tokens.length && this.stats.generatedTokens <= maxTokens).assertTrue();
      expect(Number.isFinite(this.stats.ttftMs) && this.stats.ttftMs >= 0).assertTrue();
      expect(Number.isFinite(this.stats.tokensPerSecond) && this.stats.tokensPerSecond >= 0).assertTrue();
    }
  }
}
