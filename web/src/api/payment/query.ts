import { getEnvelope, postEnvelope } from '#ui/api/client';

import { PAY_PATH, pagedQuery, payRechargeComplete, walletQuery } from './path';
import type { OrderItem, OrderListResult, RechargeRequest, WalletItem, WithdrawItem, WithdrawListResult, WithdrawRequest } from './types';

export async function createRechargeOrder(body: RechargeRequest): Promise<OrderItem> {
  return postEnvelope<OrderItem>(PAY_PATH.recharge, body);
}

export async function completeRecharge(orderNo: string): Promise<void> {
  await postEnvelope<null>(payRechargeComplete(orderNo));
}

export async function getWallet(accountId: number, fanId: number): Promise<WalletItem> {
  return getEnvelope<WalletItem>(walletQuery(accountId, fanId));
}

export async function listOrders(page: number, pageSize: number, accountId: number): Promise<OrderListResult> {
  return getEnvelope<OrderListResult>(pagedQuery(PAY_PATH.orders, page, pageSize, accountId));
}

export async function createWithdraw(body: WithdrawRequest): Promise<{ id: number }> {
  return postEnvelope<{ id: number }>(PAY_PATH.withdraws, body);
}

export async function listWithdraws(page: number, pageSize: number, accountId: number): Promise<WithdrawListResult> {
  return getEnvelope<WithdrawListResult>(pagedQuery(PAY_PATH.withdraws, page, pageSize, accountId));
}

export type { OrderItem, WithdrawItem };
