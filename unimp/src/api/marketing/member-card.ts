import { httpGet, httpPost } from '@/http/http'
import { DEFAULT_ACCOUNT_ID } from '@/utils/env'

export interface IMemberCard {
  openid: string
  level_name: string
  level: number
  discount: number
  points: number
  total_points: number
}

export function getMemberCard(accountId: number = DEFAULT_ACCOUNT_ID) {
  return httpGet<IMemberCard | null>('/api/v1/app/member-card', { account_id: accountId })
}

export function openMemberCard(accountId: number = DEFAULT_ACCOUNT_ID) {
  return httpPost<Record<string, never>>('/api/v1/app/member-card/open', { account_id: accountId })
}
