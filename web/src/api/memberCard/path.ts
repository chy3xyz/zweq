import { APP_CONFIG } from '#ui/config';

const P = `${APP_CONFIG.apiPrefix}/member-cards`;

export const MEMBER_CARD_PATH = {
  list: P,
  create: P,
  members: `${P}/members`,
  view: `${P}/view`,
  open: `${P}/open`,
  adjust: `${P}/adjust`,
} as const;

export const memberLevelsQuery = (accountId: number, page: number, pageSize: number) => {
  const params = new URLSearchParams({
    account_id: String(accountId),
    page: String(page),
    page_size: String(pageSize),
  });
  return `${MEMBER_CARD_PATH.list}?${params.toString()}`;
};

export const membersQuery = (accountId: number, page: number, pageSize: number) => {
  const params = new URLSearchParams({
    account_id: String(accountId),
    page: String(page),
    page_size: String(pageSize),
  });
  return `${MEMBER_CARD_PATH.members}?${params.toString()}`;
};

export const memberViewQuery = (accountId: number, openid: string) => {
  const params = new URLSearchParams({ account_id: String(accountId), openid });
  return `${MEMBER_CARD_PATH.view}?${params.toString()}`;
};
