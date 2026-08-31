import { APP_CONFIG } from '#ui/config';

const P = `${APP_CONFIG.apiPrefix}/distributions`;

export const DISTRIBUTION_PATH = {
  list: P,
  commissions: `${P}/commissions`,
  join: `${P}/join`,
  distribute: `${P}/distribute`,
  withdraw: `${P}/withdraw`,
} as const;

export const distributorsQuery = (
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
  if (status >= 0) params.set('status', String(status));
  return `${DISTRIBUTION_PATH.list}?${params.toString()}`;
};

export const commissionsQuery = (
  accountId: number,
  page: number,
  pageSize: number,
  keyword = '',
  level = -1,
) => {
  const params = new URLSearchParams({
    account_id: String(accountId),
    page: String(page),
    page_size: String(pageSize),
  });
  if (keyword) params.set('keyword', keyword);
  if (level >= 0) params.set('level', String(level));
  return `${DISTRIBUTION_PATH.commissions}?${params.toString()}`;
};
