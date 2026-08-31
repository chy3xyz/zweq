import { APP_CONFIG } from '#ui/config';

const P = `${APP_CONFIG.apiPrefix}/member-cards`;

export const MEMBER_CARD_PATH = {
  list: P,
  create: P,
  members: `${P}/members`,
  view: `${P}/view`,
  open: `${P}/open`,
  adjust: `${P}/adjust`,
  levelStatus: (id: number) => `${P}/${id}/status`,
} as const;

export const memberLevelsQuery = (
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
  // -1 = 全部（后端约定），0 停用 / 1 启用。
  if (status >= 0) params.set('status', String(status));
  return `${MEMBER_CARD_PATH.list}?${params.toString()}`;
};

export const membersQuery = (
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
  return `${MEMBER_CARD_PATH.members}?${params.toString()}`;
};

export const memberViewQuery = (accountId: number, openid: string) => {
  const params = new URLSearchParams({ account_id: String(accountId), openid });
  return `${MEMBER_CARD_PATH.view}?${params.toString()}`;
};
