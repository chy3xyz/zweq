import { httpGet, httpPost } from '@/http/http'
import { DEFAULT_ACCOUNT_ID } from '@/utils/env'
import type { IPaged } from '../shop-product'

export interface ICheckinResult {
  points: number
  fresh: boolean
}

export interface ICheckinRecord {
  id: number
  day: number
  points: number
  created_at: number
}

export function checkin(accountId: number = DEFAULT_ACCOUNT_ID) {
  return httpPost<ICheckinResult>('/api/v1/app/checkin', { account_id: accountId })
}

export function listCheckinRecords(page: number, pageSize: number, accountId: number = DEFAULT_ACCOUNT_ID) {
  return httpGet<IPaged<ICheckinRecord>>('/api/v1/app/checkin/records', {
    account_id: accountId,
    page,
    page_size: pageSize,
  })
}
