import { APP_CONFIG } from '#ui/config';

const P = `${APP_CONFIG.apiPrefix}/shop`;

export const SHOP_PATH = {
  categories: `${P}/categories`,
  products: `${P}/products`,
  adminProducts: `${P}/admin/products`,
  adminOrders: `${P}/admin/orders`,
  product: (id: number) => `${P}/products/${id}`,
} as const;

export const shopProductsQuery = (
  accountId: number,
  page: number,
  pageSize: number,
  keyword = '',
  categoryId = 0,
  status = -1,
) => {
  const params = new URLSearchParams({
    account_id: String(accountId),
    page: String(page),
    page_size: String(pageSize),
  });
  if (keyword) params.set('keyword', keyword);
  if (categoryId) params.set('category_id', String(categoryId));
  // -1 = 全部（后端约定），0 下架 / 1 上架。
  if (status >= 0) params.set('status', String(status));
  return `${SHOP_PATH.adminProducts}?${params.toString()}`;
};

export const shopPublicProductsQuery = (
  accountId: number,
  page: number,
  pageSize: number,
  categoryId = 0,
) => {
  const params = new URLSearchParams({
    account_id: String(accountId),
    page: String(page),
    page_size: String(pageSize),
  });
  if (categoryId) params.set('category_id', String(categoryId));
  return `${SHOP_PATH.products}?${params.toString()}`;
};

export const shopCategoriesQuery = (accountId: number) => {
  const params = new URLSearchParams({ account_id: String(accountId) });
  return `${SHOP_PATH.categories}?${params.toString()}`;
};

export const shopOrdersQuery = (
  accountId: number,
  page: number,
  pageSize: number,
  status = -1,
  openid = '',
) => {
  const params = new URLSearchParams({
    account_id: String(accountId),
    page: String(page),
    page_size: String(pageSize),
    status: String(status),
  });
  if (openid) params.set('openid', openid);
  return `${SHOP_PATH.adminOrders}?${params.toString()}`;
};
