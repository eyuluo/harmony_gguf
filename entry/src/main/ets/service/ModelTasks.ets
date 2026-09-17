import testNapi from 'libentry.so';

@Concurrent
export function parseModelTask(path: string): string {
  const meta = testNapi.parseGgufMetadata(path);
  return `${meta.architecture}|${meta.quantization}|${meta.parameters}|${meta.contextLength}|${meta.tokenizer}|${meta.fileSize}|${meta.embdDim}`;
}

@Concurrent
export function parseMmprojTask(path: string): string {
  const meta = testNapi.parseMmprojMetadata(path);
  return `${meta.architecture}|${meta.projectorType}|${meta.embdDim}|${meta.fileSize}`;
}

@Concurrent
export function loadModelTask(path: string, contextLength: number, threads: number, parallel: number,
  mmprojPath: string): number {
  return testNapi.loadModel(path, {
    contextLength: contextLength,
    threads: threads,
    parallel: parallel,
    mmprojPath: mmprojPath
  });
}
