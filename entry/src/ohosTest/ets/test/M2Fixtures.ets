import { abilityDelegatorRegistry } from '@kit.TestKit';
import { fileIo } from '@kit.CoreFileKit';

export class ModelFixture {
  name: string;
  file: string;
  architecture: string;
  prompt: string;

  constructor(name: string, file: string, architecture: string, prompt: string) {
    this.name = name;
    this.file = file;
    this.architecture = architecture;
    this.prompt = prompt;
  }
}

export const LLAMA = new ModelFixture('llama', 'smollm2-360m-instruct-q4_k_m.gguf', 'llama',
  '<|im_start|>system\n你是一个助手。<|im_end|>\n<|im_start|>user\n请从一数到二十。<|im_end|>\n' +
  '<|im_start|>assistant\n');

export const PRIMARY = new ModelFixture('qwen2', 'qwen2-0.5b-instruct-q4_k_m.gguf', 'qwen2',
  '<|im_start|>user\n你好，请介绍你自己。<|im_end|>\n<|im_start|>assistant\n');

export const ARCHITECTURES: ModelFixture[] = [
  LLAMA,
  PRIMARY,
  new ModelFixture('gemma2', 'gemma-2-2b-it-q4_k_m.gguf', 'gemma2',
    '<start_of_turn>user\n你好。<end_of_turn>\n<start_of_turn>model\n'),
  new ModelFixture('mistral', 'mistral-7b-instruct-v0.3-q4_k_m.gguf', 'llama',
    '[INST] Hello, introduce yourself. [/INST]'),
  new ModelFixture('deepseek蒸馏', 'deepseek-r1-distill-qwen-1.5b-q4_k_m.gguf', 'qwen2',
    '<｜begin▁of▁sentence｜><｜User｜>你好。<｜Assistant｜>'),
  new ModelFixture('deepseek原生MLA', 'deepseek2-mla-q4_k_m.gguf', 'deepseek2',
    'User: Hello.\n\nAssistant:'),
  new ModelFixture('chatglm', 'chatglm3-6b-q4_k_m.gguf', 'chatglm',
    '[gMASK]sop<|user|>\n你好。<|assistant|>\n')
];

export function fixturePath(file: string): string {
  const dir = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().filesDir + '/m2-models';
  try {
    fileIo.mkdirSync(dir);
  } catch (error) {
    let exists = false;
    try {
      exists = fileIo.accessSync(dir);
    } catch (accessError) {
      throw error as Error;
    }
    if (!exists) {
      throw error as Error;
    }
  }
  return dir + '/' + file;
}

export function requireFixture(file: string): string {
  const path = fixturePath(file);
  let exists = false;
  try {
    exists = fileIo.accessSync(path);
  } catch (error) {
    throw new Error('无法访问 M2 测试模型：' + path);
  }
  if (!exists) {
    throw new Error('缺少 M2 测试模型，请按 reports/test-report-M2.md 部署：' + path);
  }
  return path;
}
