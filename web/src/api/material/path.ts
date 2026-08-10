import { APP_CONFIG } from '#ui/config';

export const MATERIAL_PATH = {
  news: `${APP_CONFIG.apiPrefix}/materials/news`,
  files: `${APP_CONFIG.apiPrefix}/materials/files`,
} as const;

export const newsDetail = (id: number) => `${APP_CONFIG.apiPrefix}/materials/news/${id}`;
export const fileDetail = (id: number) => `${APP_CONFIG.apiPrefix}/materials/files/${id}`;

export const pagedQuery = (path: string, page: number, pageSize: number, accountId: number, extra?: string) => {
  const params = new URLSearchParams({ page: String(page), page_size: String(pageSize), account_id: String(accountId) });
  if (extra) params.set('kind', extra);
  return `${path}?${params.toString()}`;
};
