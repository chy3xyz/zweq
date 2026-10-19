import type { TabBar } from '@uni-helper/vite-plugin-uni-pages'
import type { CustomTabBarItem, NativeTabBarItem } from './types'

/**
 * tabbar 选择的策略
 * 0: 'NO_TABBAR' 无 tabbar
 * 1: 'NATIVE_TABBAR' 原生 tabbar
 * 2: 'CUSTOM_TABBAR' 自定义 tabbar
 */
export const TABBAR_STRATEGY_MAP = {
  NO_TABBAR: 0,
  NATIVE_TABBAR: 1,
  CUSTOM_TABBAR: 2,
}

/** ZWEQ C 端使用自定义 tabbar（保留鼓包 / 主题色 / 动态角标能力） */
export const selectedTabbarStrategy = TABBAR_STRATEGY_MAP.CUSTOM_TABBAR

/** 原生 tabbar（自定义模式下不生效，保留给需要切换策略时使用） */
export const nativeTabbarList: NativeTabBarItem[] = []

/**
 * 自定义 tabbar 列表
 * text 使用 i18n key，组件内通过 t() 翻译
 * 架构：首页 / 分类 / 购物车 / 我的（AI 助手为全局浮动入口，不在 tabbar）
 */
export const customTabbarList: CustomTabBarItem[] = [
  {
    text: 'tabbar.home',
    pagePath: 'pages/index/index',
    iconType: 'unocss',
    icon: 'i-carbon-home',
  },
  {
    text: 'tabbar.category',
    pagePath: 'pages/category/category',
    iconType: 'unocss',
    icon: 'i-carbon-catalog',
  },
  {
    text: 'tabbar.cart',
    pagePath: 'pages/cart/cart',
    iconType: 'unocss',
    icon: 'i-carbon-shopping-cart',
  },
  {
    text: 'tabbar.me',
    pagePath: 'pages/me/me',
    iconType: 'unocss',
    icon: 'i-carbon-user',
  },
]

/** 原生 tabbar 文案（pages.json 需要真实文本） */
const TABBAR_TEXT_MAP: Record<string, string> = {
  'tabbar.home': '首页',
  'tabbar.category': '分类',
  'tabbar.cart': '购物车',
  'tabbar.me': '我的',
}

const _tabbarList = customTabbarList.map(item => ({
  text: TABBAR_TEXT_MAP[item.text] || item.text,
  pagePath: item.pagePath,
}))

const _tabbar: TabBar = {
  custom: true,
  color: '#94a3b8',
  selectedColor: '#0957DE',
  backgroundColor: '#ffffff',
  borderStyle: 'white',
  height: '50px',
  fontSize: '10px',
  iconWidth: '24px',
  spacing: '3px',
  list: _tabbarList as unknown as TabBar['list'],
}

export const tabBar = _tabbar

/** 是否启用 tabbar 缓存 */
export const tabbarCacheEnable = true
/** 是否启用自定义 tabbar */
export const customTabbarEnable = selectedTabbarStrategy === TABBAR_STRATEGY_MAP.CUSTOM_TABBAR
/** 是否需要隐藏原生 tabbar */
export const needHideNativeTabbar = selectedTabbarStrategy === TABBAR_STRATEGY_MAP.CUSTOM_TABBAR

export const tabbarList = customTabbarEnable ? customTabbarList : nativeTabbarList
