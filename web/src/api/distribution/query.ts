import { http } from '#ui/api/client';
import { unwrapEnvelope } from '#ui/api/envelope';

import { commissionsQuery, distributorsQuery, DISTRIBUTION_PATH } from './path';
import type {
  CommissionItem,
  CommissionListResult,
  DistributeRequest,
  DistributorItem,
  DistributorListResult,
  DistributorWithdrawRequest,
  JoinDistributorRequest,
} from './types';

export async function listDistributors(
  accountId: number,
  page: number,
  pageSize: number,
  keyword = '',
  status = -1,
): Promise<DistributorListResult> {
  const { data } = await http.get<{ code: number; msg: string; data: DistributorListResult }>(
    distributorsQuery(accountId, page, pageSize, keyword, status),
  );
  return unwrapEnvelope(data);
}

export async function listCommissions(
  accountId: number,
  page: number,
  pageSize: number,
  keyword = '',
  level = -1,
): Promise<CommissionListResult> {
  const { data } = await http.get<{ code: number; msg: string; data: CommissionListResult }>(
    commissionsQuery(accountId, page, pageSize, keyword, level),
  );
  return unwrapEnvelope(data);
}

export async function joinDistributor(accountId: number, body: JoinDistributorRequest): Promise<void> {
  const { data } = await http.post<{ code: number; msg: string; data: null }>(DISTRIBUTION_PATH.join, body);
  unwrapEnvelope(data);
}

export async function distributeCommission(
  accountId: number,
  body: DistributeRequest,
): Promise<{ count: number }> {
  const { data } = await http.post<{ code: number; msg: string; data: { count: number } }>(
    DISTRIBUTION_PATH.distribute,
    body,
  );
  return unwrapEnvelope(data);
}

export async function withdrawCommission(
  accountId: number,
  body: DistributorWithdrawRequest,
): Promise<void> {
  const { data } = await http.post<{ code: number; msg: string; data: null }>(DISTRIBUTION_PATH.withdraw, body);
  unwrapEnvelope(data);
}

export type {
  CommissionItem,
  CommissionListResult,
  DistributeRequest,
  DistributorItem,
  DistributorListResult,
  DistributorWithdrawRequest,
  JoinDistributorRequest,
};
