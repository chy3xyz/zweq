import { defineStore } from 'pinia'
import { ref, watch } from 'vue'
import i18n from '@/i18n'

const DEFAULT_THEME = '#0957DE'

/** 读取系统语言，默认中文 */
function getSystemLocale(): string {
  try {
    const locale = uni.getLocale()
    if (locale && /^en/i.test(locale)) {
      return 'en-US'
    }
  }
  catch {
    // 某些平台不支持 getLocale，忽略即可
  }
  return 'zh-CN'
}

/**
 * 应用级状态：主题色 + 语言。
 * 原 unix 的 app store 使用 x-pinia-s，这里改为 pinia + 持久化，key 保持 'pinia:app'。
 */
export const useAppStore = defineStore(
  'app',
  () => {
    const theme = ref(DEFAULT_THEME)
    const locale = ref(getSystemLocale())

    // 初始化时同步一次到 i18n
    i18n.global.locale.value = locale.value as 'zh-CN' | 'en-US'
    watch(locale, (value) => {
      i18n.global.locale.value = value as 'zh-CN' | 'en-US'
    })

    function setTheme(color: string) {
      theme.value = color
      // #ifdef H5
      document.documentElement.style.setProperty('--theme-color', color)
      // #endif
    }

    function setLocale(value: string) {
      locale.value = value
    }

    function toggleLocale() {
      locale.value = locale.value === 'zh-CN' ? 'en-US' : 'zh-CN'
    }

    return {
      theme,
      locale,
      setTheme,
      setLocale,
      toggleLocale,
    }
  },
  {
    persist: {
      key: 'pinia:app',
    },
  },
)
