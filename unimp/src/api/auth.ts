import { httpGet, httpPost } from '@/http/http'
import { DEFAULT_ACCOUNT_ID } from '@/utils/env'

export interface IMiniLoginRes {
  openid: string
}

export interface ICLoginRes {
  token: string
}

export interface IFanProfile {
  openid: string
  nickname: string
  avatar: string
  points: number
}

/** 小程序 code → openid */
export function miniLogin(code: string, accountId: number = DEFAULT_ACCOUNT_ID) {
  return httpPost<IMiniLoginRes>('/api/v1/miniprogram/login', { account_id: accountId, code })
}

/** C 端粉丝登录：openid → fan token */
export function cLogin(openid: string, accountId: number = DEFAULT_ACCOUNT_ID) {
  return httpPost<ICLoginRes>('/api/v1/shop/auth/login', { account_id: accountId, openid })
}

export function getFanProfile(accountId: number = DEFAULT_ACCOUNT_ID) {
  return httpGet<IFanProfile>('/api/v1/app/fan/profile', { account_id: accountId })
}
