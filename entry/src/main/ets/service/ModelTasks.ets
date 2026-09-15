import testNapi from 'libentry.so';

@Concurrent
export function parseModelTask(path: string): string {
  const meta = testNapi.parseGgufMetadata(path);
  return `${meta.architecture}|${meta.quantization}|${meta.parameters}|${meta.contextLength}|${meta.tokenizer}|${meta.fileSize}`;
}

@Concurrent
export function loadModelTask(path: string, contextLength: number, threads: number, parallel: number): number {
  return testNapi.loadModel(path, { contextLength: contextLength, threads: threads, parallel: parallel });
}
