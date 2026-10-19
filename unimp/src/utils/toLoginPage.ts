import { LOGIN_PAGE } from '@/router/config'
import { getLastPage } from '@/utils'
import { debounce } from '@/utils/debounce'

interface ToLoginPageOptions {
  /**
   * 跳转模式, uni.navigateTo | uni.reLaunch
   * @default 'navigateTo'
   */
  mode?: 'navigateTo' | 'reLaunch'
  /** 查询参数，例如 '?redirect=/pages/index/index' */
  queryString?: string
}

/** 跳转到登录页，带防抖，避免并发 401 打开多个登录页 */
export const toLoginPage = debounce((options: ToLoginPageOptions = {}) => {
  const { mode = 'navigateTo', queryString = '' } = options
  const url = `${LOGIN_PAGE}${queryString}`

  const currentPage = getLastPage()
  const currentPath = `/${currentPage?.route || ''}`
  if (currentPath === LOGIN_PAGE) {
    return
  }

  if (mode === 'navigateTo') {
    uni.navigateTo({ url })
  }
  else {
    uni.reLaunch({ url })
  }
}, 500)
