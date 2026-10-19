/** 登录拦截策略映射 */
export const LOGIN_STRATEGY_MAP = {
  /** 黑名单策略：默认无需登录，只在特定页面拦截 */
  DEFAULT_NO_NEED_LOGIN: 0,
  /** 白名单策略：默认全部拦截，仅在特定免登录页面直接放行 */
  DEFAULT_NEED_LOGIN: 1,
}

/** 当前使用黑名单策略（业务页自行按需拦截） */
export const LOGIN_STRATEGY = LOGIN_STRATEGY_MAP.DEFAULT_NO_NEED_LOGIN
export const isNeedLoginMode = LOGIN_STRATEGY === LOGIN_STRATEGY_MAP.DEFAULT_NEED_LOGIN

/** 登录页（分包） */
export const LOGIN_PAGE = '/pages-sub/auth/login'
export const REGISTER_PAGE = '/pages-sub/auth/register'
export const LOGIN_PAGE_LIST = [LOGIN_PAGE, REGISTER_PAGE]

/** 黑名单策略下：未登录访问这些页面会被强制拦截 */
export const EXCLUDE_LOGIN_PATH_LIST: string[] = []
