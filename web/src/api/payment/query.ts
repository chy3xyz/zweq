import { http } from '#ui/api/client';
import { unwrapEnvelope } from '#ui/api/envelope';

import { PAY_PATH, pagedQuery, payRechargeComplete, walletQuery } from './path';
import type { OrderItem, OrderListResult, RechargeRequest, WalletItem, WithdrawItem, WithdrawListResult, WithdrawRequest } from './types';

async function getEnvelope<T>(path: string): Promise<T> {
  const { data } = await http.get<{ code: number; msg: string; data: T }>(path);
  return unwrapEnvelope(data);
}

export async function createRechargeOrder(body: RechargeRequest): Promise<OrderItem> {
  const { data } = await http.post<{ code: number; msg: string; data: OrderItem }>(PAY_PATH.recharge, body);
  return unwrapEnvelope(data);
}

export async function completeRecharge(orderNo: string): Promise<void> {
  const { data } = await http.post<{ code: number; msg: string; data: null }>(payRechargeComplete(orderNo));
  unwrapEnvelope(data);
}

export async function getWallet(accountId: number, fanId: number): Promise<WalletItem> {
  return getEnvelope<WalletItem>(walletQuery(accountId, fanId));
}

export async function listOrders(page: number, pageSize: number, accountId: number): Promise<OrderListResult> {
  return getEnvelope<OrderListResult>(pagedQuery(PAY_PATH.orders, page, pageSize, accountId));
}

export async function createWithdraw(body: WithdrawRequest): Promise<{ id: number }> {
  const { data } = await http.post<{ code: number; msg: string; data: { id: number } }>(PAY_PATH.withdraws, body);
  return unwrapEnvelope(data);
}

export async function listWithdraws(page: number, pageSize: number, accountId: number): Promise<WithdrawListResult> {
  return getEnvelope<WithdrawListResult>(pagedQuery(PAY_PATH.withdraws, page, pageSize, accountId));
}

export type { OrderItem, WithdrawItem };
