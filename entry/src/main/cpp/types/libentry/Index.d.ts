<<<<<<< HEAD
export interface ModelMetadata {
  architecture: string;
  parameters: string;
  quantization: string;
  contextLength: number;
  tokenizer: string;
  fileSize: number;
}

export interface LoadConfig {
  contextLength?: number;
  threads?: number;
}

export interface GenerateParams {
  temperature?: number;
  topK?: number;
  topP?: number;
  repeatPenalty?: number;
  maxTokens?: number;
  threads?: number;
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

export type GenerateEvent = 'token' | 'done' | 'error';

export type GenerateCallback = (event: GenerateEvent, data: TokenData | GenerateStats | GenerateError) => void;

export const add: (a: number, b: number) => number;

export const parseGgufMetadata: (path: string) => ModelMetadata;
export const loadModel: (path: string, config?: LoadConfig) => number;
export const unloadModel: (modelId: number) => void;
export const generate: (prompt: string, params: GenerateParams, callback: GenerateCallback) => void;
export const stopGenerate: () => void;

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
=======
export interface ModelMetadata {
  architecture: string;
  parameters: string;
  quantization: string;
  contextLength: number;
  tokenizer: string;
  fileSize: number;
}

export interface LoadConfig {
  contextLength?: number;
  threads?: number;
}

export interface GenerateParams {
  temperature?: number;
  topK?: number;
  topP?: number;
  repeatPenalty?: number;
  maxTokens?: number;
  threads?: number;
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
export const loadModel: (path: string, config?: LoadConfig) => number;
export const unloadModel: (modelId: number) => void;
export const generate: (prompt: string, params: GenerateParams, callback: GenerateCallback) => void;
export const stopGenerate: () => void;

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
>>>>>>> cpp
