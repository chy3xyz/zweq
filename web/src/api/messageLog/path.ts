import { APP_CONFIG } from '#ui/config';

export const LOG_PATH = {
  list: `${APP_CONFIG.apiPrefix}/message-logs`,
} as const;

export const logListQuery = (page: number, pageSize: number, accountId: number) => {
  const params = new URLSearchParams({ page: String(page), page_size: String(pageSize), account_id: String(accountId) });
  return `${LOG_PATH.list}?${params.toString()}`;
};
