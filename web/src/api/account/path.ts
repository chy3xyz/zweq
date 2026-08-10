import { APP_CONFIG } from '#ui/config';

export const ACCOUNT_PATH = {
  list: `${APP_CONFIG.apiPrefix}/accounts`,
  create: `${APP_CONFIG.apiPrefix}/accounts`,
} as const;

export const accountDetail = (id: number) => `${APP_CONFIG.apiPrefix}/accounts/${id}`;
export const accountWechat = (id: number) => `${APP_CONFIG.apiPrefix}/accounts/${id}/wechat`;

export const accountListQuery = (page: number, pageSize: number, kind?: string) => {
  const params = new URLSearchParams({ page: String(page), page_size: String(pageSize) });
  if (kind) params.set('kind', kind);
  return `${ACCOUNT_PATH.list}?${params.toString()}`;
};
