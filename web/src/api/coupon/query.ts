import { http } from '#ui/api/client';
import { unwrapEnvelope } from '#ui/api/envelope';

import { couponListQuery, couponUsersQuery, COUPON_PATH } from './path';
import type {
  CouponItem,
  CouponListResult,
  CouponUserItem,
  CouponUserListResult,
  CreateCouponRequest,
} from './types';

export async function listCoupons(
  accountId: number,
  page: number,
  pageSize: number,
): Promise<CouponListResult> {
  const { data } = await http.get<{ code: number; msg: string; data: CouponListResult }>(
    couponListQuery(accountId, page, pageSize),
  );
  return unwrapEnvelope(data);
}

export async function createCoupon(body: CreateCouponRequest): Promise<{ id: number }> {
  const { data } = await http.post<{ code: number; msg: string; data: { id: number } }>(
    COUPON_PATH.create,
    body,
  );
  return unwrapEnvelope(data);
}

export async function deleteCoupon(id: number): Promise<void> {
  const { data } = await http.delete<{ code: number; msg: string; data: null }>(COUPON_PATH.coupon(id));
  unwrapEnvelope(data);
}

export async function claimCoupon(id: number, openid: string): Promise<{ code: string }> {
  const { data } = await http.post<{ code: number; msg: string; data: { code: string } }>(
    COUPON_PATH.claim(id),
    { openid },
  );
  return unwrapEnvelope(data);
}

export async function useCoupon(code: string): Promise<void> {
  const { data } = await http.post<{ code: number; msg: string; data: null }>(COUPON_PATH.use, { code });
  unwrapEnvelope(data);
}

export async function listCouponUsers(
  accountId: number,
  page: number,
  pageSize: number,
): Promise<CouponUserListResult> {
  const { data } = await http.get<{ code: number; msg: string; data: CouponUserListResult }>(
    couponUsersQuery(accountId, page, pageSize),
  );
  return unwrapEnvelope(data);
}

export type { CouponItem, CouponListResult, CouponUserItem, CouponUserListResult, CreateCouponRequest };
