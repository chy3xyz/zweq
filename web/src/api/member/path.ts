import { APP_CONFIG } from '#ui/config';

export const FAN_PATH = {
  list: `${APP_CONFIG.apiPrefix}/fans`,
} as const;

export const fanDetail = (id: number) => `${APP_CONFIG.apiPrefix}/fans/${id}`;

export const fanListQuery = (page: number, pageSize: number, accountId: number, keyword?: string) => {
  const params = new URLSearchParams({ page: String(page), page_size: String(pageSize), account_id: String(accountId) });
  if (keyword) params.set('keyword', keyword);
  return `${FAN_PATH.list}?${params.toString()}`;
};
