import { http } from '#ui/api/client';
import { unwrapEnvelope } from '#ui/api/envelope';

import { seckillListQuery, seckillOrdersQuery, SECKILL_PATH } from './path';
import type {
  CreateSeckillRequest,
  SeckillActivityItem,
  SeckillListResult,
  SeckillOrderItem,
} from './types';

export async function listSeckills(
  accountId: number,
  page: number,
  pageSize: number,
  keyword = '',
  status = -1,
): Promise<SeckillListResult> {
  const { data } = await http.get<{ code: number; msg: string; data: SeckillListResult }>(
    seckillListQuery(accountId, page, pageSize, keyword, status),
  );
  return unwrapEnvelope(data);
}

export async function createSeckill(body: CreateSeckillRequest): Promise<{ id: number }> {
  const { data } = await http.post<{ code: number; msg: string; data: { id: number } }>(
    SECKILL_PATH.create,
    body,
  );
  return unwrapEnvelope(data);
}

export async function rushSeckill(id: number, openid: string, quantity = 1): Promise<void> {
  const { data } = await http.post<{ code: number; msg: string; data: null }>(SECKILL_PATH.rush(id), {
    openid,
    quantity,
  });
  unwrapEnvelope(data);
}

export async function setSeckillStatus(id: number, status: number): Promise<void> {
  const { data } = await http.put<{ code: number; msg: string; data: null }>(
    SECKILL_PATH.status(id),
    { status },
  );
  unwrapEnvelope(data);
}

export interface SeckillOrderListResult {
  list: SeckillOrderItem[];
  total: number;
  page: number;
  pageSize: number;
}

export async function listSeckillOrders(
  accountId: number,
  page: number,
  pageSize: number,
  keyword = '',
): Promise<SeckillOrderListResult> {
  const { data } = await http.get<{ code: number; msg: string; data: SeckillOrderListResult }>(
    seckillOrdersQuery(accountId, page, pageSize, keyword),
  );
  return unwrapEnvelope(data);
}

export type { CreateSeckillRequest, SeckillActivityItem, SeckillListResult, SeckillOrderItem };
