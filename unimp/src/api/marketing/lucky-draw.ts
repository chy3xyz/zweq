import { httpGet, httpPost } from '@/http/http'
import { DEFAULT_ACCOUNT_ID } from '@/utils/env'
import type { IPaged } from '../shop-product'

export interface IDrawConfig {
  cost: number
  daily_limit: number
  prize_count: number
}

export interface IDrawRecord {
  id: number
  prize_name: string
  points: number
  created_at: number
}

export interface IDrawResult {
  prize_name: string
  points: number
}

export function getDrawConfig(accountId: number = DEFAULT_ACCOUNT_ID) {
  return httpGet<IDrawConfig>('/api/v1/app/lucky-draw/config', { account_id: accountId })
}

export function listDrawRecords(page: number, pageSize: number, accountId: number = DEFAULT_ACCOUNT_ID) {
  return httpGet<IPaged<IDrawRecord>>('/api/v1/app/lucky-draw/records', {
    account_id: accountId,
    page,
    page_size: pageSize,
  })
}

export function draw(accountId: number = DEFAULT_ACCOUNT_ID) {
  return httpPost<IDrawResult>('/api/v1/app/lucky-draw/draw', { account_id: accountId })
}
