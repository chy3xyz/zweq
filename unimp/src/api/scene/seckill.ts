import { httpGet, httpPost } from '@/http/http'
import { DEFAULT_ACCOUNT_ID } from '@/utils/env'
import type { IPaged } from '../shop-product'

export interface ISeckill {
  id: number
  account_id: number
  title: string
  price: number
  original_price: number
  stock: number
  sold: number
  per_user: number
  start_at: number
  end_at: number
  status: number
  created_at: number
}

export interface ISeckillOrder {
  id: number
  account_id: number
  openid: string
  activity_id: number
  quantity: number
  created_at: number
}

export interface IRushRes {
  order_id: number
}

export function listSeckill(page: number, pageSize: number, accountId: number = DEFAULT_ACCOUNT_ID) {
  return httpGet<IPaged<ISeckill>>('/api/v1/app/seckill/activities', {
    account_id: accountId,
    page,
    page_size: pageSize,
  })
}

export function listSeckillOrders(page: number, pageSize: number, accountId: number = DEFAULT_ACCOUNT_ID) {
  return httpGet<IPaged<ISeckillOrder>>('/api/v1/app/seckill/orders', {
    account_id: accountId,
    page,
    page_size: pageSize,
  })
}

export function seckillRush(id: number, quantity: number, accountId: number = DEFAULT_ACCOUNT_ID) {
  return httpPost<IRushRes>(`/api/v1/app/seckill/activities/${id}/rush`, {
    account_id: accountId,
    quantity,
  })
}
