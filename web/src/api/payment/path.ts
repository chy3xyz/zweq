import { APP_CONFIG } from '#ui/config';

export const PAY_PATH = {
  recharge: `${APP_CONFIG.apiPrefix}/pay/recharge`,
  wallet: `${APP_CONFIG.apiPrefix}/pay/wallet`,
  orders: `${APP_CONFIG.apiPrefix}/pay/orders`,
  withdraws: `${APP_CONFIG.apiPrefix}/pay/withdraws`,
} as const;

export const payRechargeComplete = (orderNo: string) => `${APP_CONFIG.apiPrefix}/pay/recharge/${orderNo}/complete`;

export const pagedQuery = (path: string, page: number, pageSize: number, accountId: number) => {
  const params = new URLSearchParams({ page: String(page), page_size: String(pageSize), account_id: String(accountId) });
  return `${path}?${params.toString()}`;
};

export const walletQuery = (accountId: number, fanId: number) => {
  const params = new URLSearchParams({ account_id: String(accountId), fan_id: String(fanId) });
  return `${PAY_PATH.wallet}?${params.toString()}`;
};
