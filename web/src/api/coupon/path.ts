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

export const couponListQuery = (
  accountId: number,
  page: number,
  pageSize: number,
  keyword = '',
  status = -1,
) => {
  const params = new URLSearchParams({
    account_id: String(accountId),
    page: String(page),
    page_size: String(pageSize),
  });
  if (keyword) params.set('keyword', keyword);
  // -1 = 全部（后端约定），0 下架 / 1 上架。
  if (status >= 0) params.set('status', String(status));
  return `${COUPON_PATH.list}?${params.toString()}`;
};

export const couponUsersQuery = (
  accountId: number,
  page: number,
  pageSize: number,
  keyword = '',
  status = '',
) => {
  const params = new URLSearchParams({
    account_id: String(accountId),
    page: String(page),
    page_size: String(pageSize),
  });
  if (keyword) params.set('keyword', keyword);
  if (status) params.set('status', status);
  return `${COUPON_PATH.users}?${params.toString()}`;
};
