import { deleteEnvelope, getEnvelope, postEnvelope, putEnvelope } from '#ui/api/client';

import { seckillListQuery, seckillOrdersQuery, SECKILL_PATH } from './path';
import type {
  CreateSeckillRequest,
  SeckillActivityItem,
  SeckillListResult,
  SeckillOrderItem,
  UpdateSeckillRequest,
} from './types';

export async function listSeckills(
  accountId: number,
  page: number,
  pageSize: number,
  keyword = '',
  status = -1,
): Promise<SeckillListResult> {
  return getEnvelope<SeckillListResult>(
    seckillListQuery(accountId, page, pageSize, keyword, status),
  );
}

export async function createSeckill(body: CreateSeckillRequest): Promise<{ id: number }> {
  return postEnvelope<{ id: number }>(
    SECKILL_PATH.create,
    body,
  );
}

export async function getSeckill(id: number): Promise<SeckillActivityItem> {
  return getEnvelope<SeckillActivityItem>(
    SECKILL_PATH.seckill(id),
  );
}

export async function updateSeckill(
  id: number,
  body: UpdateSeckillRequest,
): Promise<{ id: number }> {
  return putEnvelope<{ id: number }>(
    SECKILL_PATH.seckill(id),
    body,
  );
}

export async function deleteSeckill(id: number): Promise<void> {
  await deleteEnvelope<null>(
    SECKILL_PATH.seckill(id),
  );
}

export async function rushSeckill(id: number, openid: string, quantity = 1): Promise<void> {
  await postEnvelope<null>(SECKILL_PATH.rush(id), {
    openid,
    quantity,
  });
}

export async function setSeckillStatus(id: number, status: number): Promise<void> {
  await putEnvelope<null>(
    SECKILL_PATH.status(id),
    { status },
  );
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
  return getEnvelope<SeckillOrderListResult>(
    seckillOrdersQuery(accountId, page, pageSize, keyword),
  );
}

export type {
  CreateSeckillRequest,
  SeckillActivityItem,
  SeckillListResult,
  SeckillOrderItem,
  UpdateSeckillRequest,
};
