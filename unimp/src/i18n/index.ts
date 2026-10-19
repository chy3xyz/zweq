import type { Locale } from 'vue-i18n'
import { createI18n } from 'vue-i18n'
import enUS from './locales/en-US.json'
import zhCN from './locales/zh-CN.json'

export const SUPPORTED_LOCALES = ['zh-CN', 'en-US'] as const
export type AppLocale = (typeof SUPPORTED_LOCALES)[number]

const i18n = createI18n({
  legacy: false,
  globalInjection: true,
  locale: 'zh-CN',
  fallbackLocale: 'zh-CN',
  messages: {
    'zh-CN': zhCN,
    'en-US': enUS,
  },
})

/** 非 SFC 环境（api / store / utils）使用的翻译函数 */
export function t(key: string, named?: Record<string, string | number>): string {
  if (named) {
    return i18n.global.t(key, named)
  }
  return i18n.global.t(key)
}

/** 设置当前语言（同时同步 vue-i18n 与 uni-app 原生语言） */
export function setI18nLocale(locale: string) {
  i18n.global.locale.value = locale as Locale
}

export default i18n
