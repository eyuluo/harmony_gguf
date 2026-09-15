import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { taskpool } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { AppState, ModelItem } from './AppState';
import { ModelStore, StoredModelInfo } from './ModelStore';
import { parseModelTask } from './ModelTasks';

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
      items.push({ info: model, exists: this.isFileExists(model.path) });
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
        fileSize: Number(parts[5])
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

  async deleteRegistry(model: StoredModelInfo): Promise<void> {
    await ModelStore.getInstance().removeModel(model.path);
    await this.refreshModels();
  }

  async deleteMissingRegistries(): Promise<void> {
    const state = this.state!;
    for (const item of state.models) {
      if (!item.exists) {
        await ModelStore.getInstance().removeModel(item.info.path);
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
