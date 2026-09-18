import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

export interface StoredMmprojInfo {
  path: string;
  name: string;
  architecture: string;
  projectorType: string;
  embdDim: number;
  fileSize: number;
}

export interface StoredModelInfo {
  path: string;
  name: string;
  architecture: string;
  quantization: string;
  parameters: string;
  contextLength: number;
  tokenizer: string;
  fileSize: number;
  embdDim: number;
  mmproj: StoredMmprojInfo | null;
}

const PREF_NAME = 'model_registry';
const DOMAIN = 0x0000;
const TAG = 'ModelStore';

export class ModelStore {
  private static instance: ModelStore | null = null;
  private prefs: preferences.Preferences | null = null;

  static getInstance(): ModelStore {
    if (ModelStore.instance === null) {
      ModelStore.instance = new ModelStore();
    }
    return ModelStore.instance;
  }

  async init(context: common.Context): Promise<void> {
    if (this.prefs !== null) {
      return;
    }
    try {
      this.prefs = await preferences.getPreferences(context, { name: PREF_NAME });
    } catch (error) {
      hilog.error(DOMAIN, TAG, '初始化模型索引失败: %{public}s', String(error));
      throw new Error('初始化模型索引失败: ' + String(error));
    }
  }

  getModels(): StoredModelInfo[] {
    if (this.prefs === null) {
      return [];
    }
    try {
      const paths = this.prefs.getSync('paths', []) as string[];
      if (paths.length > 0) {
        const models: StoredModelInfo[] = [];
        const names = this.prefs.getSync('names', []) as string[];
        const architectures = this.prefs.getSync('architectures', []) as string[];
        const quantizations = this.prefs.getSync('quantizations', []) as string[];
        const parameters = this.prefs.getSync('parametersList', []) as string[];
        const contextLengths = this.prefs.getSync('contextLengths', []) as number[];
        const tokenizers = this.prefs.getSync('tokenizers', []) as string[];
        const fileSizes = this.prefs.getSync('fileSizes', []) as number[];
        const embdDims = this.prefs.getSync('embdDims', []) as number[];
        const mmprojJsons = this.prefs.getSync('mmprojJsons', []) as string[];
        for (let index = 0; index < paths.length; index++) {
          models.push({
            path: paths[index],
            name: names[index] || '本地 GGUF 模型',
            architecture: architectures[index] || '未知',
            quantization: quantizations[index] || '未知',
            parameters: parameters[index] || '未知',
            contextLength: contextLengths[index] || 0,
            tokenizer: tokenizers[index] || '未知',
            fileSize: fileSizes[index] || 0,
            embdDim: embdDims[index] || 0,
            mmproj: this.parseMmproj(mmprojJsons[index] || '')
          });
        }
        return models;
      }

      // 兼容早期版本的单模型索引。
      const path = this.prefs.getSync('path', '') as string;
      if (path.length === 0) {
        return [];
      }
      return [{
        path: path,
        name: this.prefs.getSync('name', '本地 GGUF 模型') as string,
        architecture: this.prefs.getSync('architecture', '未知') as string,
        quantization: this.prefs.getSync('quantization', '未知') as string,
        parameters: this.prefs.getSync('parameters', '未知') as string,
        contextLength: this.prefs.getSync('contextLength', 0) as number,
        tokenizer: this.prefs.getSync('tokenizer', '未知') as string,
        fileSize: this.prefs.getSync('fileSize', 0) as number,
        embdDim: 0,
        mmproj: null
      }];
    } catch (error) {
      hilog.error(DOMAIN, TAG, '读取模型索引失败: %{public}s', String(error));
      return [];
    }
  }

  async saveModel(model: StoredModelInfo): Promise<void> {
    if (this.prefs === null) {
      throw new Error('ModelStore 尚未初始化');
    }
    try {
      const models = this.getModels();
      let found = false;
      for (let index = 0; index < models.length; index++) {
        if (models[index].path === model.path) {
          models[index] = model;
          found = true;
          break;
        }
      }
      if (!found) {
        models.push(model);
      }
      await this.saveModels(models);
    } catch (error) {
      hilog.error(DOMAIN, TAG, '保存模型索引失败: %{public}s', String(error));
      throw new Error('保存模型索引失败: ' + String(error));
    }
  }

  async removeModel(path: string): Promise<void> {
    if (this.prefs === null) {
      throw new Error('ModelStore 尚未初始化');
    }
    const models = this.getModels();
    const remaining: StoredModelInfo[] = [];
    for (const model of models) {
      if (model.path !== path) {
        remaining.push(model);
      }
    }
    await this.saveModels(remaining);
  }

  private async saveModels(models: StoredModelInfo[]): Promise<void> {
    if (this.prefs === null) {
      throw new Error('ModelStore 尚未初始化');
    }
    const paths: string[] = [];
    const names: string[] = [];
    const architectures: string[] = [];
    const quantizations: string[] = [];
    const parameters: string[] = [];
    const contextLengths: number[] = [];
    const tokenizers: string[] = [];
    const fileSizes: number[] = [];
    const embdDims: number[] = [];
    const mmprojJsons: string[] = [];
    for (const model of models) {
      paths.push(model.path);
      names.push(model.name);
      architectures.push(model.architecture);
      quantizations.push(model.quantization);
      parameters.push(model.parameters);
      contextLengths.push(model.contextLength);
      tokenizers.push(model.tokenizer);
      fileSizes.push(model.fileSize);
      embdDims.push(model.embdDim);
      mmprojJsons.push(model.mmproj ? JSON.stringify(model.mmproj) : '');
    }
    try {
      await this.prefs.put('paths', paths);
      await this.prefs.put('names', names);
      await this.prefs.put('architectures', architectures);
      await this.prefs.put('quantizations', quantizations);
      await this.prefs.put('parametersList', parameters);
      await this.prefs.put('contextLengths', contextLengths);
      await this.prefs.put('tokenizers', tokenizers);
      await this.prefs.put('fileSizes', fileSizes);
      await this.prefs.put('embdDims', embdDims);
      await this.prefs.put('mmprojJsons', mmprojJsons);
      // Remove legacy single-model fields after the first list write.
      await this.prefs.delete('path');
      await this.prefs.delete('name');
      await this.prefs.delete('architecture');
      await this.prefs.delete('quantization');
      await this.prefs.delete('parameters');
      await this.prefs.delete('contextLength');
      await this.prefs.delete('tokenizer');
      await this.prefs.delete('fileSize');
      await this.prefs.flush();
    } catch (error) {
      hilog.error(DOMAIN, TAG, '批量写入模型索引失败: %{public}s', String(error));
      throw new Error('批量写入模型索引失败: ' + String(error));
    }
  }

  private parseMmproj(json: string): StoredMmprojInfo | null {
    if (json.length === 0) {
      return null;
    }
    try {
      return JSON.parse(json) as StoredMmprojInfo;
    } catch (error) {
      return null;
    }
  }

  async clearModel(): Promise<void> {
    if (this.prefs === null) {
      return;
    }
    try {
      await this.prefs.clear();
      await this.prefs.flush();
    } catch (error) {
      hilog.error(DOMAIN, TAG, '清理模型索引失败: %{public}s', String(error));
      throw new Error('清理模型索引失败: ' + String(error));
    }
  }
}
