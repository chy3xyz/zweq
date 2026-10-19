import type { CustomRequestOptions } from '@/http/types'
import { useFanStore } from '@/store/fan'
import { getEnvBaseUrl } from '@/utils'
import { stringifyQuery } from './tools/queryString'

const baseUrl = getEnvBaseUrl()

const httpInterceptor = {
  invoke(options: CustomRequestOptions) {
    if (options.query) {
      const queryStr = stringifyQuery(options.query)
      options.url += options.url.includes('?') ? `&${queryStr}` : `?${queryStr}`
    }

    if (!options.url.startsWith('http')) {
      // #ifdef H5
      if (JSON.parse(import.meta.env.VITE_APP_PROXY_ENABLE)) {
        options.url = import.meta.env.VITE_APP_PROXY_PREFIX + options.url
      }
      else {
        options.url = baseUrl + options.url
      }
      // #endif
      // #ifndef H5
      options.url = baseUrl + options.url
      // #endif
    }

    options.timeout = 60000
    options.header = { ...options.header }

    // C 端粉丝 token（登录后由 store 持久化）
    const fanStore = useFanStore()
    if (fanStore.fanToken) {
      options.header.Authorization = `Bearer ${fanStore.fanToken}`
    }
    return options
  },
}

export const requestInterceptor = {
  install() {
    uni.addInterceptor('request', httpInterceptor)
    uni.addInterceptor('uploadFile', httpInterceptor)
  },
}
