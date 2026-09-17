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

export const PRIMARY = new ModelFixture('llama', 'tinyllama-1.1b-chat-q4_k_m.gguf', 'llama',
  '<|system|>\n你是一个助手。</s>\n<|user|>\n请从一数到二十。</s>\n<|assistant|>\n');

export const ARCHITECTURES: ModelFixture[] = [
  PRIMARY,
  new ModelFixture('qwen2', 'qwen2-0.5b-instruct-q4_k_m.gguf', 'qwen2',
    '<|im_start|>user\n你好，请介绍你自己。<|im_end|>\n<|im_start|>assistant\n'),
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
  return abilityDelegatorRegistry.getAbilityDelegator().getAppContext().filesDir + '/m2-models/' + file;
}

export function requireFixture(file: string): string {
  const path = fixturePath(file);
  if (!fileIo.accessSync(path)) {
    throw new Error('缺少 M2 测试模型，请按 docs/M2-TESTING.md 部署：' + path);
  }
  return path;
}
