import { httpGet, httpPost } from '@/http/http'
import { DEFAULT_ACCOUNT_ID } from '@/utils/env'

export interface IAddress {
  id: number
  openid: string
  name: string
  mobile: string
  region: string
  detail: string
  is_default: number
}

export interface IAddressInput {
  openid: string
  name: string
  mobile: string
  region: string
  detail: string
  is_default: number
}

export function listAddresses(openid: string, accountId: number = DEFAULT_ACCOUNT_ID) {
  return httpGet<IAddress[] | null>('/api/v1/shop/addresses', { account_id: accountId, openid })
    .then(list => list ?? [])
}

export function createAddress(addr: IAddressInput) {
  return httpPost<Record<string, never>>('/api/v1/shop/addresses', addr)
}
