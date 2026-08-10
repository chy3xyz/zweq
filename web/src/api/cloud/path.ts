import { APP_CONFIG } from '#ui/config';

export const CLOUD_PATH = {
  licenses: `${APP_CONFIG.apiPrefix}/cloud/licenses`,
  verify: `${APP_CONFIG.apiPrefix}/cloud/licenses/verify`,
  market: `${APP_CONFIG.apiPrefix}/cloud/market`,
} as const;

export const licenseRevoke = (id: number) => `${APP_CONFIG.apiPrefix}/cloud/licenses/${id}/revoke`;
export const marketInstall = (name: string) => `${APP_CONFIG.apiPrefix}/cloud/market/${name}/install`;

export const licenseListQuery = (page: number, pageSize: number) => {
  const params = new URLSearchParams({ page: String(page), page_size: String(pageSize) });
  return `${CLOUD_PATH.licenses}?${params.toString()}`;
};

export const marketListQuery = (page: number, pageSize: number) => {
  const params = new URLSearchParams({ page: String(page), page_size: String(pageSize) });
  return `${CLOUD_PATH.market}?${params.toString()}`;
};
