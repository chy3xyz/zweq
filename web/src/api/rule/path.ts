import { APP_CONFIG } from '#ui/config';

export const RULE_PATH = {
  list: `${APP_CONFIG.apiPrefix}/rules`,
  create: `${APP_CONFIG.apiPrefix}/rules`,
} as const;

export const ruleDetail = (id: number) => `${APP_CONFIG.apiPrefix}/rules/${id}`;
export const ruleKeywords = (id: number) => `${APP_CONFIG.apiPrefix}/rules/${id}/keywords`;
export const ruleKeyword = (id: number, kid: number) => `${APP_CONFIG.apiPrefix}/rules/${id}/keywords/${kid}`;
export const ruleReplies = (id: number) => `${APP_CONFIG.apiPrefix}/rules/${id}/replies`;
export const ruleReply = (id: number, rid: number) => `${APP_CONFIG.apiPrefix}/rules/${id}/replies/${rid}`;

export const ruleListQuery = (page: number, pageSize: number, accountId: number) => {
  const params = new URLSearchParams({ page: String(page), page_size: String(pageSize), account_id: String(accountId) });
  return `${RULE_PATH.list}?${params.toString()}`;
};
