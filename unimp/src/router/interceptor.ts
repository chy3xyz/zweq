/**
 * 路由拦截：同步自定义 tabbar 高亮。
 * C 端不做全局登录门禁，需要登录的页面在页面内自行判断（与 unix 行为一致）。
 */
import { getTabbarRedirectPath, tabbarStore } from '@/tabbar/store'

export const navigateToInterceptor = {
  invoke(options: { url?: string }) {
    const url = options?.url
    if (!url) {
      return
    }
    const path = url.split('?')[0]
    const redirectPath = getTabbarRedirectPath(path)
    if (redirectPath) {
      uni.reLaunch({ url: redirectPath })
      return false
    }
    tabbarStore.setAutoCurIdx(path)
  },
}

export const routeInterceptor = {
  install() {
    uni.addInterceptor('navigateTo', navigateToInterceptor)
    uni.addInterceptor('reLaunch', navigateToInterceptor)
    uni.addInterceptor('redirectTo', navigateToInterceptor)
    uni.addInterceptor('switchTab', navigateToInterceptor)
  },
}
