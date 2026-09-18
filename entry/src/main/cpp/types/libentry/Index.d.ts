export interface ModelMetadata {
  architecture: string;
  parameters: string;
  quantization: string;
  contextLength: number;
  tokenizer: string;
  fileSize: number;
  embdDim: number;
}

export interface MmprojMetadata {
  architecture: string;
  projectorType: string;
  embdDim: number;
  hasVision: boolean;
  hasAudio: boolean;
  fileSize: number;
}

export interface LoadConfig {
  contextLength?: number;
  threads?: number;
  parallel?: number;
  mmprojPath?: string;
}

export interface GenerateParams {
  temperature?: number;
  topK?: number;
  topP?: number;
  repeatPenalty?: number;
  maxTokens?: number;
  threads?: number;
  images?: string[];
}

export interface GenerateStats {
  promptTokens: number;
  generatedTokens: number;
  ttftMs: number;
  tokensPerSecond: number;
}

export interface GenerateError {
  code: number;
  message: string;
}

export interface TokenData {
  text: string;
}

export type GenerateEvent = 'token' | 'done' | 'error' | 'stopped';

export type GenerateCallback = (event: GenerateEvent, data: TokenData | GenerateStats | GenerateError) => void;

export const parseGgufMetadata: (path: string) => ModelMetadata;
export const parseMmprojMetadata: (path: string) => MmprojMetadata;
export const loadModel: (path: string, config?: LoadConfig) => number;
export const unloadModel: (modelId: number) => void;
export const generate: (prompt: string, params: GenerateParams, callback: GenerateCallback) => number;
export const stopGenerate: (requestId: number) => void;
export const stopAllGenerations: () => void;

export interface ServerConfig {
  host?: string;
  port?: number;
  apiKey?: string;
}

export interface ServerInfo {
  host: string;
  port: number;
  lanAddress: string;
  running: boolean;
}

export const startServer: (config?: ServerConfig) => void;
export const stopServer: () => void;
export const getServerStatus: () => ServerInfo;
