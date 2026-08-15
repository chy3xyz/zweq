import { APP_CONFIG } from '#ui/config';

const P = `${APP_CONFIG.apiPrefix}/votes`;

export const VOTE_PATH = {
  list: P,
  create: P,
  results: (id: number) => `${P}/${id}/results`,
  cast: (id: number) => `${P}/${id}/vote`,
} as const;

export const voteListQuery = (accountId: number, page: number, pageSize: number) => {
  const params = new URLSearchParams({
    account_id: String(accountId),
    page: String(page),
    page_size: String(pageSize),
  });
  return `${VOTE_PATH.list}?${params.toString()}`;
};
