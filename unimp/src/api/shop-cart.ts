import { httpDelete, httpGet, httpPost, httpPut } from '@/http/http'
import { DEFAULT_ACCOUNT_ID } from '@/utils/env'

export interface ICart {
  id: number
  openid: string
  product_id: number
  sku_id: number
  quantity: number
  created_at: number
}

export function listCart(openid: string, accountId: number = DEFAULT_ACCOUNT_ID) {
  return httpGet<ICart[] | null>('/api/v1/shop/cart', { account_id: accountId, openid })
    .then(list => list ?? [])
}

export function addCart(openid: string, productId: number, skuId: number, quantity: number) {
  return httpPost<Record<string, never>>('/api/v1/shop/cart/add', {
    openid,
    product_id: productId,
    sku_id: skuId,
    quantity,
  })
}

export function updateCart(cartId: number, quantity: number) {
  // 后端 cartUpdate 从 query 读取 quantity（不是 body）
  return httpPut<Record<string, never>>(`/api/v1/shop/cart/${cartId}`, undefined, { quantity })
}

export function deleteCart(cartId: number) {
  return httpDelete<Record<string, never>>(`/api/v1/shop/cart/${cartId}`)
}
