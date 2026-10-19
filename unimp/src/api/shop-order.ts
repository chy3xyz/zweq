import { httpGet, httpPost } from '@/http/http'
import { DEFAULT_ACCOUNT_ID } from '@/utils/env'
import type { IPaged } from './shop-product'

export interface IOrder {
  id: number
  account_id: number
  order_no: string
  openid: string
  total_amount: number
  pay_amount: number
  status: number
  address_json: string
  express_company: string
  express_no: string
  paid_at: number
  created_at: number
}

export interface IOrderProduct {
  id: number
  order_id: number
  product_id: number
  sku_id: number
  name: string
  image: string
  spec_json: string
  price: number
  quantity: number
  created_at: number
}

export interface IOrderDetail {
  order: IOrder
  items: IOrderProduct[]
  commented_order_product_ids: number[]
}

export interface IOrderItemInput {
  product_id: number
  sku_id: number
  quantity: number
}

export interface IOrderCreateReq {
  account_id: number
  openid: string
  address_id: number
  items: IOrderItemInput[]
  coupon_code: string
  client_trade_no: string
  pay_type: string
  pickup_store_id: number
  remark: string
}

export interface ICreateOrderRes {
  id: number
}

export interface IPaymentField {
  timeStamp: string
  nonceStr: string
  package: string
  signType: string
  paySign: string
}

export interface IPayParams {
  mode: string
  amount: number
  order_no: string
  payment: IPaymentField
}

export interface IOrderSummary {
  order_id: number
  cover_image: string
  item_count: number
  summary: string
}

export function createOrder(req: IOrderCreateReq) {
  return httpPost<ICreateOrderRes>('/api/v1/shop/orders', req)
}

export function listOrders(
  openid: string,
  page: number,
  pageSize: number,
  status = -1,
  accountId: number = DEFAULT_ACCOUNT_ID,
) {
  const query: Record<string, string | number> = {
    account_id: accountId,
    page,
    page_size: pageSize,
    status,
  }
  if (openid !== '')
    query.openid = openid
  return httpGet<IPaged<IOrder>>('/api/v1/shop/orders', query)
}

export function getOrderDetail(id: number) {
  return httpGet<IOrderDetail>(`/api/v1/shop/orders/${id}`)
}

export function getOrderPayParams(id: number) {
  return httpGet<IPayParams>(`/api/v1/shop/orders/${id}/pay-params`)
}

export function payComplete(id: number) {
  return httpPost<Record<string, never>>(`/api/v1/shop/orders/${id}/pay-complete`, {})
}

export function cancelOrder(id: number) {
  return httpPost<Record<string, never>>(`/api/v1/shop/orders/${id}/cancel`, {})
}

export function confirmOrder(id: number) {
  return httpPost<Record<string, never>>(`/api/v1/shop/orders/${id}/confirm`, {})
}

export function orderSummaries(ids: number[]) {
  return httpGet<IOrderSummary[] | null>('/api/v1/shop/orders/summaries', { ids: ids.join(',') })
    .then(list => list ?? [])
}
