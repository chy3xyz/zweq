import { httpDelete, httpGet, httpPost } from '@/http/http'
import { DEFAULT_ACCOUNT_ID } from '@/utils/env'

// ============ 拼团 ============
export interface IGroupon {
  id: number
  account_id: number
  product_id: number
  group_price: number
  group_size: number
  status: number
}

export interface IGrouponOpenRes {
  team_id: number
}

// ============ 评论 ============
export interface IComment {
  id: number
  product_id: number
  openid: string
  star: number
  content: string
  created_at: number
}

// ============ 收藏 ============
export interface IFavorite {
  id: number
  openid: string
  product_id: number
  created_at: number
}

// ============ 退款 ============
export interface IRefund {
  id: number
  account_id: number
  order_id: number
  openid: string
  reason: string
  amount: number
  status: number
  created_at: number
}

// ============ 邀请有礼 ============
export interface IInviteGift {
  id: number
  account_id: number
  target_count: number
  reward_type: string
  reward_value: number
}

export interface IInviteMy {
  invited: number
  invite_code: string
}

export function listGroupons(accountId: number = DEFAULT_ACCOUNT_ID) {
  return httpGet<IGroupon[] | null>('/api/v1/shop/groupons', { account_id: accountId })
    .then(list => list ?? [])
}

export function openGroupon(grouponId: number, openid: string, addressId: number, skuId: number, accountId: number = DEFAULT_ACCOUNT_ID) {
  return httpPost<IGrouponOpenRes>(`/api/v1/shop/groupons/${grouponId}/open`, {
    account_id: accountId,
    openid,
    address_id: addressId,
    sku_id: skuId,
  })
}

export function listComments(productId: number) {
  return httpGet<IComment[] | null>('/api/v1/shop/comments', { product_id: productId })
    .then(list => list ?? [])
}

export function createComment(productId: number, openid: string, star: number, content: string, orderProductId = 0, accountId: number = DEFAULT_ACCOUNT_ID) {
  return httpPost<Record<string, never>>('/api/v1/shop/comments', {
    account_id: accountId,
    order_product_id: orderProductId,
    product_id: productId,
    openid,
    star,
    content,
  })
}

export function listFavorites(openid: string, accountId: number = DEFAULT_ACCOUNT_ID) {
  return httpGet<IFavorite[] | null>('/api/v1/shop/favorites', { account_id: accountId, openid })
    .then(list => list ?? [])
}

export function addFavorite(openid: string, productId: number, accountId: number = DEFAULT_ACCOUNT_ID) {
  return httpPost<Record<string, never>>('/api/v1/shop/favorites', {
    account_id: accountId,
    openid,
    product_id: productId,
  })
}

export function deleteFavorite(favoriteId: number) {
  return httpDelete<Record<string, never>>(`/api/v1/shop/favorites/${favoriteId}`)
}

export function applyRefund(orderId: number, openid: string, reason: string, accountId: number = DEFAULT_ACCOUNT_ID) {
  return httpPost<Record<string, never>>('/api/v1/shop/refunds', {
    account_id: accountId,
    order_id: orderId,
    openid,
    reason,
  })
}

export function listRefunds(orderId: number) {
  // 后端无退款记录时返回 data:null；归一成 []，避免页面渲染时读 null.length
  return httpGet<IRefund[] | null>('/api/v1/shop/refunds', { order_id: orderId })
    .then(list => list ?? [])
}

export function listInviteGifts(accountId: number = DEFAULT_ACCOUNT_ID) {
  return httpGet<IInviteGift[] | null>('/api/v1/shop/invites/gifts', { account_id: accountId })
    .then(list => list ?? [])
}

export function inviteMy(openid: string, accountId: number = DEFAULT_ACCOUNT_ID) {
  return httpGet<IInviteMy>('/api/v1/shop/invites/my', { account_id: accountId, openid })
}

export function inviteBind(inviterOpenid: string, inviteeOpenid: string, accountId: number = DEFAULT_ACCOUNT_ID) {
  return httpPost<Record<string, never>>('/api/v1/shop/invites/bind', {
    account_id: accountId,
    inviter_openid: inviterOpenid,
    invitee_openid: inviteeOpenid,
  })
}
