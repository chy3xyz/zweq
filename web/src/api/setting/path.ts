import { APP_CONFIG } from '#ui/config';

const P = `${APP_CONFIG.apiPrefix}/settings`;

export const SETTING_PATH = {
  list: P,
  create: P,
  item: (key: string) => `${P}/${encodeURIComponent(key)}`,
} as const;

export const settingListQuery = (page: number, pageSize: number) => {
  const params = new URLSearchParams({
    page: String(page),
    page_size: String(pageSize),
  });
  return `${SETTING_PATH.list}?${params.toString()}`;
};
