import { APP_CONFIG } from '#ui/config';

export const LUCKY_DRAW_PATH = {
  records: `${APP_CONFIG.apiPrefix}/lucky-draw/records`,
  draw: `${APP_CONFIG.apiPrefix}/lucky-draw/draw`,
} as const;

export const drawRecordQuery = (accountId: number, page: number, pageSize: number) => {
  const params = new URLSearchParams({
    account_id: String(accountId),
    page: String(page),
    page_size: String(pageSize),
  });
  return `${LUCKY_DRAW_PATH.records}?${params.toString()}`;
};

export const configPath = (accountId: number) =>
  `${APP_CONFIG.apiPrefix}/accounts/${accountId}/modules/lucky_draw/config`;
