import { deleteEnvelope, getEnvelope, postEnvelope, putEnvelope } from '#ui/api/client';

import { orderListQuery, POINTS_PATH, productListQuery } from './path';
import type {
  AdjustRequest,
  CreateProductRequest,
  PointsOrder,
  PointsProduct,
  PointsProductListResult,
  RedeemRequest,
  UpdateProductRequest,
} from './types';

export async function listProducts(
  accountId: number,
  page: number,
  pageSize: number,
  keyword = '',
  status = -1,
): Promise<PointsProductListResult> {
  return getEnvelope<PointsProductListResult>(
    productListQuery(accountId, page, pageSize, keyword, status),
  );
}

export async function createProduct(accountId: number, body: CreateProductRequest): Promise<{ id: number }> {
  return postEnvelope<{ id: number }>(
    `${POINTS_PATH.products}?account_id=${accountId}`,
    body,
  );
}

export async function updateProduct(id: number, body: UpdateProductRequest): Promise<{ id: number }> {
  return putEnvelope<{ id: number }>(POINTS_PATH.product(id), body);
}

export async function deleteProduct(id: number): Promise<void> {
  await deleteEnvelope<null>(POINTS_PATH.product(id));
}

export async function redeemPoints(accountId: number, body: RedeemRequest): Promise<{ id: number }> {
  return postEnvelope<{ id: number }>(
    `${POINTS_PATH.redeem}?account_id=${accountId}`,
    body,
  );
}

export async function adjustPoints(accountId: number, body: AdjustRequest): Promise<{ id: number }> {
  return postEnvelope<{ id: number }>(
    `${POINTS_PATH.adjust}?account_id=${accountId}`,
    body,
  );
}

/// 后端返回 `data = { items: [...] }`（非分页信封），此处归一为数组。
export async function listPointsOrders(accountId: number): Promise<PointsOrder[]> {
  const res = await getEnvelope<{ items?: PointsOrder[] }>(orderListQuery(accountId));
  return res.items ?? [];
}

export type { PointsOrder, PointsProduct, PointsProductListResult };
