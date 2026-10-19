/** 过渡期：单账号写死 account_id；后端按小程序 appid 识别就绪后移除 */
export const DEFAULT_ACCOUNT_ID = 1

export type EnvType = 'development' | 'test' | 'production'

export interface EnvConfig {
  /** 环境中文名 */
  name: string
  /** 接口基础地址 */
  baseURL: string
}

/** 编译期系统默认环境 */
export function getSystemEnv(): EnvType {
  return import.meta.env.DEV ? 'development' : 'production'
}

/** 当前环境（保留手动切换能力，便于调试） */
let overrideEnv: EnvType | null = null

export function getCurrentEnv(): EnvType {
  return overrideEnv ?? getSystemEnv()
}

export function setCurrentEnv(value: EnvType): void {
  overrideEnv = value
}

export function resetEnv(): void {
  overrideEnv = null
}

export function getEnvConfig(): EnvConfig {
  const env = getCurrentEnv()
  const baseURL = import.meta.env.VITE_SERVER_BASEURL || ''
  return {
    name: env === 'development' ? '开发环境' : env === 'test' ? '测试环境' : '生产环境',
    baseURL,
  }
}

export function getEnvLabel(type: EnvType): string {
  return type === 'development' ? '开发' : type === 'test' ? '测试' : '生产'
}

export function isDev(): boolean {
  return getCurrentEnv() === 'development'
}

export function isTest(): boolean {
  return getCurrentEnv() === 'test'
}

export function isProd(): boolean {
  return getCurrentEnv() === 'production'
}
