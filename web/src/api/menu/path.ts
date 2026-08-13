import { APP_CONFIG } from '#ui/config';

const menuPath = (accountId: number) => `${APP_CONFIG.apiPrefix}/accounts/${accountId}/menu`;

export const MENU_PATH = {
  get: (accountId: number) => menuPath(accountId),
  save: (accountId: number) => menuPath(accountId),
  publish: (accountId: number) => `${menuPath(accountId)}/publish`,
  fetch: (accountId: number) => `${menuPath(accountId)}/fetch`,
  deleteRemote: (accountId: number) => menuPath(accountId),
} as const;
