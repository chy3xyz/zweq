import { APP_CONFIG } from '#ui/config';

export const MODULE_PATH = {
  list: `${APP_CONFIG.apiPrefix}/modules`,
  create: `${APP_CONFIG.apiPrefix}/modules`,
  adminNav: `${APP_CONFIG.apiPrefix}/admin/nav`,
} as const;

export const accountModules = (accountId: number) => `${APP_CONFIG.apiPrefix}/accounts/${accountId}/modules`;
export const accountModule = (accountId: number, module: string) =>
  `${APP_CONFIG.apiPrefix}/accounts/${accountId}/modules/${module}`;
export const accountModuleConfig = (accountId: number, module: string) =>
  `${APP_CONFIG.apiPrefix}/accounts/${accountId}/modules/${module}/config`;

export const moduleListQuery = (page: number, pageSize: number, keyword?: string) => {
  const params = new URLSearchParams({ page: String(page), page_size: String(pageSize) });
  if (keyword?.trim()) params.set('keyword', keyword.trim());
  return `${MODULE_PATH.list}?${params.toString()}`;
};
