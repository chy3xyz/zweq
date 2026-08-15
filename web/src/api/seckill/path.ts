import { APP_CONFIG } from '#ui/config';

const P = `${APP_CONFIG.apiPrefix}/seckills`;

export const SECKILL_PATH = {
  list: P,
  create: P,
  orders: `${P}/orders`,
  rush: (id: number) => `${P}/${id}/rush`,
} as const;

export const seckillListQuery = (accountId: number, page: number, pageSize: number) => {
  const params = new URLSearchParams({
    account_id: String(accountId),
    page: String(page),
    page_size: String(pageSize),
  });
  return `${SECKILL_PATH.list}?${params.toString()}`;
};

export const seckillOrdersQuery = (accountId: number, page: number, pageSize: number) => {
  const params = new URLSearchParams({
    account_id: String(accountId),
    page: String(page),
    page_size: String(pageSize),
  });
  return `${SECKILL_PATH.orders}?${params.toString()}`;
};
