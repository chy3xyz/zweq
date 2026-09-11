import { getEnvelope, postEnvelope } from '#ui/api/client';

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
  return getEnvelope<DistributorListResult>(
    distributorsQuery(accountId, page, pageSize, keyword, status),
  );
}

export async function listCommissions(
  accountId: number,
  page: number,
  pageSize: number,
  keyword = '',
  level = -1,
): Promise<CommissionListResult> {
  return getEnvelope<CommissionListResult>(
    commissionsQuery(accountId, page, pageSize, keyword, level),
  );
}

export async function joinDistributor(accountId: number, body: JoinDistributorRequest): Promise<void> {
  await postEnvelope<null>(DISTRIBUTION_PATH.join, body);
}

export async function distributeCommission(
  accountId: number,
  body: DistributeRequest,
): Promise<{ count: number }> {
  return postEnvelope<{ count: number }>(
    DISTRIBUTION_PATH.distribute,
    body,
  );
}

export async function withdrawCommission(
  accountId: number,
  body: DistributorWithdrawRequest,
): Promise<void> {
  await postEnvelope<null>(DISTRIBUTION_PATH.withdraw, body);
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
