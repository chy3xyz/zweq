import type { CustomTabBarItem } from './types'
import { beforeEach, describe, expect, it, vi } from 'vitest'

/**
 * config.ts 是 tabbar 的唯一配置源。这里用可变的 mock 配置，
 * 配合 vi.resetModules() 让每个用例拿到一份按自己配置初始化的 store。
 */
const configState = vi.hoisted(() => ({ list: [] as CustomTabBarItem[] }))

vi.mock('./config', () => ({
  TABBAR_STRATEGY_MAP: { NO_TABBAR: 0, NATIVE_TABBAR: 1, CUSTOM_TABBAR: 2 },
  selectedTabbarStrategy: 2,
  get tabbarList() {
    return configState.list
  },
}))

vi.mock('@/utils', () => ({
  HOME_PAGE: '/pages/index/index',
}))

function item(text: string, pagePath: string): CustomTabBarItem {
  return { text, pagePath: pagePath as CustomTabBarItem['pagePath'], iconType: 'unocss', icon: 'i-carbon-home' }
}

const TAB_LIST = [
  item('首页', 'pages/index/index'),
  item('分类', 'pages/category/category'),
  item('购物车', 'pages/cart/cart'),
  item('我的', 'pages/me/me'),
]

async function setupStore(list: CustomTabBarItem[] = TAB_LIST) {
  configState.list = list
  return import('./store')
}

beforeEach(() => {
  vi.resetModules()
})

describe('tabbarList 归一化', () => {
  it('所有 pagePath 都以 / 开头', async () => {
    const { tabbarList } = await setupStore()
    expect(tabbarList.value.map(i => i.pagePath)).toEqual([
      '/pages/index/index',
      '/pages/category/category',
      '/pages/cart/cart',
      '/pages/me/me',
    ])
  })
})

describe('curIdx 高亮', () => {
  it('h5 首屏 "/" 高亮真实首页', async () => {
    const { tabbarStore } = await setupStore()
    tabbarStore.setAutoCurIdx('/')
    expect(tabbarStore.curIdx).toBe(0)
    expect(tabbarStore.isCurrentRouteTabbarItem(0)).toBe(true)
  })

  it('按路径设置高亮下标', async () => {
    const { tabbarStore } = await setupStore()
    tabbarStore.setCurIdxByPath('/pages/me/me')
    expect(tabbarStore.curIdx).toBe(3)
  })

  it('带 query 的路径也能正确高亮', async () => {
    const { tabbarStore } = await setupStore()
    tabbarStore.setAutoCurIdx('/pages/me/me?from=share')
    expect(tabbarStore.curIdx).toBe(3)
  })

  it('跳转到非 tabbar 页面时保持当前高亮', async () => {
    const { tabbarStore } = await setupStore()
    tabbarStore.setAutoCurIdx('/pages/me/me')
    tabbarStore.setAutoCurIdx('/pages-sub/shop/product-detail?id=1')
    expect(tabbarStore.curIdx).toBe(3)
  })

  it('传 -1 时不高亮任何一项', async () => {
    const { tabbarStore } = await setupStore()
    tabbarStore.setCurIdx(-1)
    expect(tabbarStore.curIdx).toBe(-1)
  })
})

describe('isPageTabbar', () => {
  it('tabbar 页（含 H5 的 "/"）返回 true', async () => {
    const { isPageTabbar } = await setupStore()
    expect(isPageTabbar('/')).toBe(true)
    expect(isPageTabbar('/pages/me/me')).toBe(true)
  })

  it('非 tabbar 页面返回 false', async () => {
    const { isPageTabbar } = await setupStore()
    expect(isPageTabbar('/pages/detail/detail')).toBe(false)
    expect(isPageTabbar('/pages-sub/shop/order-list')).toBe(false)
  })
})

describe('c 端无角色门禁', () => {
  it('getTabbarRedirectPath 始终返回空串', async () => {
    const { getTabbarRedirectPath } = await setupStore()
    expect(getTabbarRedirectPath('/pages/me/me')).toBe('')
    expect(getTabbarRedirectPath('/pages/about/about')).toBe('')
  })
})
