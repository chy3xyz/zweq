import { APP_CONFIG } from '#ui/config';

const P = `${APP_CONFIG.apiPrefix}/coupons`;

export const COUPON_PATH = {
  list: P,
  create: P,
  coupon: (id: number) => `${P}/${id}`,
  claim: (id: number) => `${P}/${id}/claim`,
  use: `${P}/use`,
  users: `${APP_CONFIG.apiPrefix}/coupon-users`,
} as const;

export const couponListQuery = (accountId: number, page: number, pageSize: number) => {
  const params = new URLSearchParams({
    account_id: String(accountId),
    page: String(page),
    page_size: String(pageSize),
  });
  return `${COUPON_PATH.list}?${params.toString()}`;
};

export const couponUsersQuery = (accountId: number, page: number, pageSize: number) => {
  const params = new URLSearchParams({
    account_id: String(accountId),
    page: String(page),
    page_size: String(pageSize),
  });
  return `${COUPON_PATH.users}?${params.toString()}`;
};
