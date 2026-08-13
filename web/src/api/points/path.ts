import { APP_CONFIG } from '#ui/config';

const P = `${APP_CONFIG.apiPrefix}/points`;

export const POINTS_PATH = {
  products: `${P}/products`,
  product: (id: number) => `${P}/products/${id}`,
  redeem: `${P}/redeem`,
  adjust: `${P}/adjust`,
  orders: `${P}/orders`,
} as const;

export const productListQuery = (accountId: number, page: number, pageSize: number) => {
  const params = new URLSearchParams({
    account_id: String(accountId),
    page: String(page),
    page_size: String(pageSize),
  });
  return `${POINTS_PATH.products}?${params.toString()}`;
};

export const orderListQuery = (accountId: number) => {
  const params = new URLSearchParams({ account_id: String(accountId) });
  return `${POINTS_PATH.orders}?${params.toString()}`;
};
