import { deleteEnvelope, getEnvelope, postEnvelope, putEnvelope } from '#ui/api/client';

import { couponListQuery, couponUsersQuery, COUPON_PATH } from './path';
import type {
  CouponItem,
  CouponListResult,
  CouponUserItem,
  CouponUserListResult,
  CreateCouponRequest,
  UpdateCouponRequest,
} from './types';

export async function listCoupons(
  accountId: number,
  page: number,
  pageSize: number,
  keyword = '',
  status = -1,
): Promise<CouponListResult> {
  return getEnvelope<CouponListResult>(
    couponListQuery(accountId, page, pageSize, keyword, status),
  );
}

export async function setCouponStatus(id: number, status: number): Promise<void> {
  await putEnvelope<null>(
    `${COUPON_PATH.coupon(id)}/status`,
    { status },
  );
}

export async function createCoupon(body: CreateCouponRequest): Promise<{ id: number }> {
  return postEnvelope<{ id: number }>(
    COUPON_PATH.create,
    body,
  );
}

export async function getCoupon(id: number): Promise<CouponItem> {
  return getEnvelope<CouponItem>(COUPON_PATH.coupon(id));
}

export async function updateCoupon(id: number, body: UpdateCouponRequest): Promise<{ id: number }> {
  return putEnvelope<{ id: number }>(
    COUPON_PATH.coupon(id),
    body,
  );
}

export async function deleteCoupon(id: number): Promise<void> {
  await deleteEnvelope<null>(COUPON_PATH.coupon(id));
}

export async function claimCoupon(id: number, openid: string): Promise<{ code: string }> {
  return postEnvelope<{ code: string }>(
    COUPON_PATH.claim(id),
    { openid },
  );
}

export async function useCoupon(code: string): Promise<void> {
  await postEnvelope<null>(COUPON_PATH.use, { code });
}

export async function listCouponUsers(
  accountId: number,
  page: number,
  pageSize: number,
  keyword = '',
  status = '',
): Promise<CouponUserListResult> {
  return getEnvelope<CouponUserListResult>(
    couponUsersQuery(accountId, page, pageSize, keyword, status),
  );
}

export type { CouponItem, CouponListResult, CouponUserItem, CouponUserListResult, CreateCouponRequest, UpdateCouponRequest };
