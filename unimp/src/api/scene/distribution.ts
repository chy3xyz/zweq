import { httpGet, httpPost } from '@/http/http'
import { DEFAULT_ACCOUNT_ID } from '@/utils/env'

export interface IDistribution {
  openid: string
  parent_openid: string
  commission_balance: number
  total_commission: number
}

export function getDistribution(accountId: number = DEFAULT_ACCOUNT_ID) {
  return httpGet<IDistribution | null>('/api/v1/app/distribution', { account_id: accountId })
}

export function joinDistribution(parentOpenid: string, accountId: number = DEFAULT_ACCOUNT_ID) {
  return httpPost<Record<string, never>>('/api/v1/app/distribution/join', {
    account_id: accountId,
    parent_openid: parentOpenid,
  })
}

export function withdrawDistribution(amount: number, accountId: number = DEFAULT_ACCOUNT_ID) {
  return httpPost<Record<string, never>>('/api/v1/app/distribution/withdraw', {
    account_id: accountId,
    amount,
  })
}
