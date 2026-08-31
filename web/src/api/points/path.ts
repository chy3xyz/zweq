import { APP_CONFIG } from '#ui/config';

const P = `${APP_CONFIG.apiPrefix}/points`;

export const POINTS_PATH = {
  products: `${P}/products`,
  product: (id: number) => `${P}/products/${id}`,
  redeem: `${P}/redeem`,
  adjust: `${P}/adjust`,
  orders: `${P}/orders`,
} as const;

export const productListQuery = (
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
  return `${POINTS_PATH.products}?${params.toString()}`;
};

export const orderListQuery = (accountId: number) => {
  const params = new URLSearchParams({ account_id: String(accountId) });
  return `${POINTS_PATH.orders}?${params.toString()}`;
};
