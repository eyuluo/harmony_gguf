import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { taskpool } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { AppState, ModelItem } from './AppState';
import { ModelStore, StoredModelInfo } from './ModelStore';
import { parseModelTask, parseMmprojTask } from './ModelTasks';

const DOMAIN = 0x0000;
const TAG = 'ModelService';

export class ModelService {
  private static instance: ModelService | null = null;
  private state: AppState | null = null;
  private context: common.Context | null = null;

  static getInstance(): ModelService {
    if (ModelService.instance === null) {
      ModelService.instance = new ModelService();
    }
    return ModelService.instance;
  }

  init(state: AppState, context: common.Context): void {
    this.state = state;
    this.context = context;
  }

  async refreshModels(): Promise<void> {
    const state = this.state!;
    const context = this.context!;
    await ModelStore.getInstance().init(context);
    const stored = ModelStore.getInstance().getModels();
    const items: ModelItem[] = [];
    for (const model of stored) {
      items.push({
        info: model,
        exists: this.isFileExists(model.path),
        mmprojExists: model.mmproj === null || this.isFileExists(model.mmproj.path)
      });
    }
    state.models = items;
  }

  async importModel(): Promise<void> {
    const state = this.state!;
    const context = this.context!;
    if (state.importing) {
      return;
    }
    let importedPath = '';
    let sourceFd = -1;
    let targetFd = -1;
    let importCommitted = false;
    state.importing = true;
    try {
      const uris = await new picker.DocumentViewPicker(context).select({
        maxSelectNumber: 1,
        fileSuffixFilters: ['.gguf']
      });
      if (uris.length === 0) {
        return;
      }
      const dir = context.filesDir + '/models';
      try {
        fileIo.mkdirSync(dir);
      } catch (error) {
        hilog.info(DOMAIN, TAG, 'models directory is ready: %{public}s', String(error));
      }

      const sourceFile = fileIo.openSync(uris[0], fileIo.OpenMode.READ_ONLY);
      sourceFd = sourceFile.fd;
      const originalName = sourceFile.name.length > 0 ? sourceFile.name : `本地模型 ${state.models.length + 1}.gguf`;

      const pathStem = `${dir}/model_${Date.now()}_${state.models.length + 1}`;
      const temporaryPath = pathStem + '.part';
      const path = pathStem + '.gguf';
      importedPath = temporaryPath;
      const targetFile = fileIo.openSync(temporaryPath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      targetFd = targetFile.fd;
      await fileIo.copyFile(sourceFile.fd, targetFile.fd);
      fileIo.closeSync(sourceFile);
      sourceFd = -1;
      fileIo.closeSync(targetFile);
      targetFd = -1;
      fileIo.renameSync(temporaryPath, path);
      importedPath = path;

      const parts = (await taskpool.execute(parseModelTask, path) as string).split('|');
      const importedModel: StoredModelInfo = {
        path: path,
        name: originalName,
        architecture: parts[0],
        quantization: parts[1],
        parameters: parts[2],
        contextLength: Number(parts[3]),
        tokenizer: parts[4],
        fileSize: Number(parts[5]),
        embdDim: Number(parts[6]),
        mmproj: null
      };
      await ModelStore.getInstance().init(context);
      await ModelStore.getInstance().saveModel(importedModel);
      importCommitted = true;
      await this.refreshModels();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'import model failed: %{public}s', String(error));
    } finally {
      if (sourceFd >= 0) {
        try {
          fileIo.closeSync(sourceFd);
        } catch (closeError) {
          hilog.error(DOMAIN, TAG, 'close source failed: %{public}s', String(closeError));
        }
      }
      if (targetFd >= 0) {
        try {
          fileIo.closeSync(targetFd);
        } catch (closeError) {
          hilog.error(DOMAIN, TAG, 'close target failed: %{public}s', String(closeError));
        }
      }
      if (!importCommitted && importedPath.length > 0) {
        try {
          if (fileIo.accessSync(importedPath)) {
            fileIo.unlinkSync(importedPath);
          }
        } catch (removeError) {
          hilog.error(DOMAIN, TAG, 'remove incomplete model failed: %{public}s', String(removeError));
        }
      }
      state.importing = false;
    }
  }

  async importMmproj(model: StoredModelInfo): Promise<void> {
    const context = this.context!;
    const state = this.state!;
    let sourceFd = -1;
    let targetFd = -1;
    let targetPath = '';
    try {
      const uris = await new picker.DocumentViewPicker(context).select({
        maxSelectNumber: 1,
        fileSuffixFilters: ['.gguf']
      });
      if (uris.length === 0) {
        return;
      }
      const dir = context.filesDir + '/mmproj';
      try {
        fileIo.mkdirSync(dir);
      } catch (error) {
        hilog.info(DOMAIN, TAG, 'mmproj directory is ready: %{public}s', String(error));
      }
      const sourceFile = fileIo.openSync(uris[0], fileIo.OpenMode.READ_ONLY);
      sourceFd = sourceFile.fd;
      const originalName = sourceFile.name.length > 0 ? sourceFile.name : `mmproj_${Date.now()}.gguf`;
      targetPath = `${dir}/${Date.now()}_${originalName}`;
      const targetFile = fileIo.openSync(targetPath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      targetFd = targetFile.fd;
      await fileIo.copyFile(sourceFile.fd, targetFile.fd);
      fileIo.closeSync(sourceFile);
      sourceFd = -1;
      fileIo.closeSync(targetFile);
      targetFd = -1;

      // 软校验：解析 mmproj 元数据，架构非 clip 视为无效
      const parts = (await taskpool.execute(parseMmprojTask, targetPath) as string).split('|');
      if (parts[0] !== 'clip') {
        hilog.error(DOMAIN, TAG, 'import mmproj failed: not a valid mmproj');
        fileIo.unlinkSync(targetPath);
        return;
      }

      // 关联到模型并持久化
      await ModelStore.getInstance().init(context);
      await ModelStore.getInstance().saveModel({
        path: model.path,
        name: model.name,
        architecture: model.architecture,
        quantization: model.quantization,
        parameters: model.parameters,
        contextLength: model.contextLength,
        tokenizer: model.tokenizer,
        fileSize: model.fileSize,
        embdDim: model.embdDim,
        mmproj: {
          path: targetPath,
          name: originalName,
          architecture: parts[0],
          projectorType: parts[1],
          embdDim: Number(parts[2]),
          fileSize: Number(parts[3])
        }
      });
      state.selectedMmprojPath = '';
      await this.refreshModels();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'import mmproj failed: %{public}s', String(error));
    } finally {
      if (sourceFd >= 0) {
        try {
          fileIo.closeSync(sourceFd);
        } catch (closeError) {
          hilog.error(DOMAIN, TAG, 'close source failed: %{public}s', String(closeError));
        }
      }
      if (targetFd >= 0) {
        try {
          fileIo.closeSync(targetFd);
        } catch (closeError) {
          hilog.error(DOMAIN, TAG, 'close target failed: %{public}s', String(closeError));
        }
      }
    }
  }

  async deleteMmproj(model: StoredModelInfo): Promise<void> {
    const context = this.context!;
    const state = this.state!;
    if (model.mmproj !== null && state.selectedMmprojPath === model.mmproj.path) {
      state.selectedMmprojPath = '';
    }
    await ModelStore.getInstance().init(context);
    await ModelStore.getInstance().saveModel({
      path: model.path,
      name: model.name,
      architecture: model.architecture,
      quantization: model.quantization,
      parameters: model.parameters,
      contextLength: model.contextLength,
      tokenizer: model.tokenizer,
      fileSize: model.fileSize,
      embdDim: model.embdDim,
      mmproj: null
    });
    await this.refreshModels();
  }

  toggleMmprojSelection(model: StoredModelInfo): void {
    if (model.mmproj === null) {
      return;
    }
    const state = this.state!;
    state.selectedMmprojPath = state.selectedMmprojPath === model.mmproj.path ? '' : model.mmproj.path;
  }

  async resolveMmproj(model: StoredModelInfo, useMmproj: boolean): Promise<string> {
    if (!useMmproj) {
      return '';
    }
    const mmproj = model.mmproj;
    if (mmproj === null) {
      return '';
    }
    if (!this.isFileExists(mmproj.path)) {
      throw new Error('投影器文件不存在');
    }
    if (model.embdDim > 0 && mmproj.embdDim > 0 && model.embdDim !== mmproj.embdDim) {
      throw new Error('模型与投影器维度不匹配');
    }
    return mmproj.path;
  }

  validateModelFiles(model: StoredModelInfo, useMmproj: boolean): boolean {
    if (!this.isFileExists(model.path)) {
      return false;
    }
    return !useMmproj || (model.mmproj !== null && this.isFileExists(model.mmproj.path));
  }

  async deleteRegistry(model: StoredModelInfo): Promise<void> {
    const state = this.state!;
    if (model.mmproj !== null && state.selectedMmprojPath === model.mmproj.path) {
      state.selectedMmprojPath = '';
    }
    await ModelStore.getInstance().removeModel(model.path);
    await this.refreshModels();
  }

  async deleteMissingRegistries(): Promise<void> {
    const state = this.state!;
    for (const item of state.models) {
      if (!item.exists) {
        await ModelStore.getInstance().removeModel(item.info.path);
      } else if (!item.mmprojExists && item.info.mmproj !== null) {
        if (state.selectedMmprojPath === item.info.mmproj.path) {
          state.selectedMmprojPath = '';
        }
        await ModelStore.getInstance().saveModel({
          path: item.info.path,
          name: item.info.name,
          architecture: item.info.architecture,
          quantization: item.info.quantization,
          parameters: item.info.parameters,
          contextLength: item.info.contextLength,
          tokenizer: item.info.tokenizer,
          fileSize: item.info.fileSize,
          embdDim: item.info.embdDim,
          mmproj: null
        });
      }
    }
    await this.refreshModels();
  }

  private isFileExists(path: string): boolean {
    try {
      return fileIo.accessSync(path);
    } catch (error) {
      return false;
    }
  }
}
