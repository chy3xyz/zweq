import { http } from '#ui/api/client';
import { unwrapEnvelope } from '#ui/api/envelope';

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

async function getEnvelope<T>(path: string): Promise<T> {
  const { data } = await http.get<{ code: number; msg: string; data: T }>(path);
  return unwrapEnvelope(data);
}

export async function listProducts(
  accountId: number,
  page: number,
  pageSize: number,
): Promise<PointsProductListResult> {
  return getEnvelope<PointsProductListResult>(productListQuery(accountId, page, pageSize));
}

export async function createProduct(accountId: number, body: CreateProductRequest): Promise<{ id: number }> {
  const { data } = await http.post<{ code: number; msg: string; data: { id: number } }>(
    `${POINTS_PATH.products}?account_id=${accountId}`,
    body,
  );
  return unwrapEnvelope(data);
}

export async function updateProduct(id: number, body: UpdateProductRequest): Promise<{ id: number }> {
  const { data } = await http.put<{ code: number; msg: string; data: { id: number } }>(POINTS_PATH.product(id), body);
  return unwrapEnvelope(data);
}

export async function deleteProduct(id: number): Promise<void> {
  const { data } = await http.delete<{ code: number; msg: string; data: null }>(POINTS_PATH.product(id));
  unwrapEnvelope(data);
}

export async function redeemPoints(accountId: number, body: RedeemRequest): Promise<{ id: number }> {
  const { data } = await http.post<{ code: number; msg: string; data: { id: number } }>(
    `${POINTS_PATH.redeem}?account_id=${accountId}`,
    body,
  );
  return unwrapEnvelope(data);
}

export async function adjustPoints(accountId: number, body: AdjustRequest): Promise<{ id: number }> {
  const { data } = await http.post<{ code: number; msg: string; data: { id: number } }>(
    `${POINTS_PATH.adjust}?account_id=${accountId}`,
    body,
  );
  return unwrapEnvelope(data);
}

export async function listPointsOrders(accountId: number): Promise<PointsOrder[]> {
  return getEnvelope<PointsOrder[]>(orderListQuery(accountId));
}

export type { PointsOrder, PointsProduct, PointsProductListResult };
