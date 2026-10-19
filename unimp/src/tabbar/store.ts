import type { CustomTabBarItem, CustomTabBarItemBadge } from './types'
import { computed, reactive, ref } from 'vue'
import { HOME_PAGE } from '@/utils'
import { tabbarList as _tabbarList, selectedTabbarStrategy, TABBAR_STRATEGY_MAP } from './config'

/**
 * 当前 tabbar 页面的缓存 key。
 * 存「路径」而非下标，避免角色/配置变化后高亮错位。
 */
const TABBAR_PATH_STORAGE_KEY = 'app-tabbar-path'

/** tabbarList 里的 path 统一成 '/' 开头 */
const baseTabbarList = reactive<CustomTabBarItem[]>(_tabbarList.map(item => ({
  ...item,
  pagePath: item.pagePath.startsWith('/') ? item.pagePath : `/${item.pagePath}`,
})))

/** 当前可见的 tabbar 列表（C 端无角色过滤，保留 computed 以兼容原实现） */
const tabbarList = computed(() => baseTabbarList)

export function normalizeRoutePath(path?: string) {
  if (!path) {
    return ''
  }
  const _path = path.split('?')[0]
  return _path.startsWith('/') ? _path : `/${_path}`
}

/**
 * 把路由路径归一成能跟 tabbar 配置比对的路径。
 * H5 首页是 '/'，需要还原成真实首页路由再匹配。
 */
function resolveTabbarPath(path?: string) {
  const _path = normalizeRoutePath(path)
  return _path === '/' ? HOME_PAGE : _path
}

/** 在 tabbar 配置全集里查找 */
function findTabbarItemByPath(path?: string) {
  const _path = resolveTabbarPath(path)
  return _path ? baseTabbarList.find(item => item.pagePath === _path) : undefined
}

/** 是否 tabbar 页面（决定是否渲染自定义 tabbar） */
export function isPageTabbar(path: string) {
  if (selectedTabbarStrategy === TABBAR_STRATEGY_MAP.NO_TABBAR) {
    return false
  }
  return !!findTabbarItemByPath(path)
}

/** C 端不做角色门禁，保留空实现以兼容路由拦截器调用 */
export function getTabbarRedirectPath(_path?: string) {
  return ''
}

function getCurrentPagePath() {
  const pages = getCurrentPages()
  const currentPage = pages[pages.length - 1]
  return normalizeRoutePath(currentPage?.route)
}

/** 在列表里找下标；找不到返回 -1 */
function findTabbarIndexByPath(path?: string) {
  const _path = resolveTabbarPath(path)
  if (!_path) {
    return -1
  }
  return tabbarList.value.findIndex(item => item.pagePath === _path)
}

const curPath = ref<string>(normalizeRoutePath(uni.getStorageSync(TABBAR_PATH_STORAGE_KEY)) || HOME_PAGE)
const prevPath = ref<string>(curPath.value)

/**
 * 自定义 tabbar 状态管理。
 * 当前高亮下标由路径实时推导，刷新浏览器后也能停在正确的 tab。
 */
const tabbarStore = reactive({
  get curIdx() {
    return findTabbarIndexByPath(curPath.value)
  },
  set curIdx(idx: number) {
    this.setCurIdx(idx)
  },
  get prevIdx() {
    return findTabbarIndexByPath(prevPath.value)
  },
  setCurPath(path: string) {
    const _path = resolveTabbarPath(path)
    prevPath.value = curPath.value
    curPath.value = _path
    uni.setStorageSync(TABBAR_PATH_STORAGE_KEY, _path)
  },
  setCurIdx(idx: number) {
    this.setCurPath(tabbarList.value[idx]?.pagePath || '')
  },
  setCurIdxByPath(path: string) {
    const idx = findTabbarIndexByPath(path)
    if (idx >= 0) {
      this.setCurIdx(idx)
    }
    else {
      this.setCurPath(path)
    }
  },
  setTabbarItemBadge(idx: number, badge: CustomTabBarItemBadge) {
    const list = tabbarList.value
    if (list[idx]) {
      list[idx].badge = badge
    }
  },
  setAutoCurIdx(path: string) {
    // 目标不是 tabbar 页（详情页）时保持当前高亮
    if (!findTabbarItemByPath(path)) {
      return
    }
    this.setCurPath(path)
  },
  syncCurIdxByCurrentPage() {
    const currentPath = getCurrentPagePath()
    if (currentPath) {
      this.setAutoCurIdx(currentPath)
    }
  },
  syncCurIdxByCurrentPageAsync() {
    setTimeout(() => {
      this.syncCurIdxByCurrentPage()
    }, 0)
  },
  isCurrentRouteTabbarItem(index: number) {
    const item = tabbarList.value[index]
    if (!item) {
      return false
    }
    return findTabbarIndexByPath(getCurrentPagePath()) === index
  },
  restorePrevIdx() {
    if (prevPath.value === curPath.value)
      return
    this.setCurPath(prevPath.value)
  },
})

/** 兼容旧的 setCurIdxByPath 调用（我的页退出登录后回首页） */
export function setCurIdxByPath(path: string) {
  tabbarStore.setCurIdxByPath(path)
}

export { tabbarList, tabbarStore }
