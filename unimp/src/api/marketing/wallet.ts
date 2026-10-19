import { httpGet, httpPost } from '@/http/http'
import { DEFAULT_ACCOUNT_ID } from '@/utils/env'

export interface IBalancePlan {
  id: number
  account_id: number
  name: string
  amount: number
  bonus: number
  status: number
}

export interface IWalletBalance {
  balance: number
}

export function listBalancePlans(accountId: number = DEFAULT_ACCOUNT_ID) {
  return httpGet<IBalancePlan[]>('/api/v1/shop/balance-plans', { account_id: accountId })
}

export function rechargePlan(planId: number, openid: string, accountId: number = DEFAULT_ACCOUNT_ID) {
  return httpPost<Record<string, never>>(`/api/v1/shop/balance-plans/${planId}/recharge`, {
    account_id: accountId,
    openid,
  })
}

export function getWalletBalance(accountId: number = DEFAULT_ACCOUNT_ID) {
  return httpGet<IWalletBalance>('/api/v1/app/wallet', { account_id: accountId })
}
