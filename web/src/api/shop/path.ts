import { APP_CONFIG } from '#ui/config';

const P = `${APP_CONFIG.apiPrefix}/shop`;

export const SHOP_PATH = {
  categories: `${P}/categories`,
  products: `${P}/products`,
  adminProducts: `${P}/admin/products`,
  product: (id: number) => `${P}/products/${id}`,
} as const;

export const shopProductsQuery = (
  accountId: number,
  page: number,
  pageSize: number,
  keyword = '',
) => {
  const params = new URLSearchParams({
    account_id: String(accountId),
    page: String(page),
    page_size: String(pageSize),
  });
  if (keyword) params.set('keyword', keyword);
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
