import { httpGet, httpPost } from '@/http/http'
import { DEFAULT_ACCOUNT_ID } from '@/utils/env'
import type { IPaged } from '../shop-product'

export interface ICoupon {
  id: number
  account_id: number
  title: string
  amount: number
  min_amount: number
  total: number
  per_user: number
  start_at: number
  end_at: number
}

export interface ICouponUser {
  id: number
  coupon_id: number
  code: string
  status: string
  created_at: number
  title: string
  amount: number
  min_amount: number
}

export interface IClaimRes {
  code: string
}

export function listCoupons(page: number, pageSize: number, accountId: number = DEFAULT_ACCOUNT_ID) {
  return httpGet<IPaged<ICoupon>>('/api/v1/app/coupons', {
    account_id: accountId,
    page,
    page_size: pageSize,
  })
}

export function claimCoupon(couponId: number, accountId: number = DEFAULT_ACCOUNT_ID) {
  return httpPost<IClaimRes>(`/api/v1/app/coupons/${couponId}/claim`, { account_id: accountId })
}

export function listMyCoupons(page: number, pageSize: number, accountId: number = DEFAULT_ACCOUNT_ID) {
  return httpGet<IPaged<ICouponUser>>('/api/v1/app/my-coupons', {
    account_id: accountId,
    page,
    page_size: pageSize,
  })
}
