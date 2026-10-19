import { httpGet, httpPost } from '@/http/http'
import { DEFAULT_ACCOUNT_ID } from '@/utils/env'
import type { IPaged } from '../shop-product'

export interface IPointsProduct {
  id: number
  account_id: number
  name: string
  points: number
  stock: number
}

export interface IPointsOrder {
  id: number
  product_id: number
  product_name: string
  points_spent: number
  status: string
}

export interface IRedeemRes {
  order_id: number
}

export function listPointsProducts(page: number, pageSize: number, accountId: number = DEFAULT_ACCOUNT_ID) {
  return httpGet<IPaged<IPointsProduct>>('/api/v1/app/points/products', {
    account_id: accountId,
    page,
    page_size: pageSize,
  })
}

export function redeemPoints(productId: number, accountId: number = DEFAULT_ACCOUNT_ID) {
  return httpPost<IRedeemRes>('/api/v1/app/points/redeem', {
    account_id: accountId,
    product_id: productId,
  })
}

export function listPointsOrders(accountId: number = DEFAULT_ACCOUNT_ID) {
  return httpGet<IPointsOrder[] | null>('/api/v1/app/points/orders', { account_id: accountId })
    .then(list => list ?? [])
}
