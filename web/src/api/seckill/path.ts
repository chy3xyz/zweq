import { APP_CONFIG } from '#ui/config';

const P = `${APP_CONFIG.apiPrefix}/seckills`;

export const SECKILL_PATH = {
  list: P,
  create: P,
  seckill: (id: number) => `${P}/${id}`,
  rush: (id: number) => `${P}/${id}/rush`,
  status: (id: number) => `${P}/${id}/status`,
  orders: `${P}/orders`,
} as const;

export const seckillListQuery = (
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
  return `${SECKILL_PATH.list}?${params.toString()}`;
};

export const seckillOrdersQuery = (
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
  return `${SECKILL_PATH.orders}?${params.toString()}`;
};
