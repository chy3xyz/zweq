import { APP_CONFIG } from '#ui/config';

export const CHECKIN_PATH = {
  records: `${APP_CONFIG.apiPrefix}/checkin/records`,
} as const;

export const checkinRecordQuery = (accountId: number, page: number, pageSize: number) => {
  const params = new URLSearchParams({
    account_id: String(accountId),
    page: String(page),
    page_size: String(pageSize),
  });
  return `${CHECKIN_PATH.records}?${params.toString()}`;
};
