import { getEnvelope, postEnvelope, putEnvelope } from '#ui/api/client';

import { TENANT_PATH, tenantDetail, tenantListQuery } from './path';
import type { CreateTenantRequest, TenantItem, TenantListResult, UpdateTenantRequest } from './types';

export async function listTenants(
  page: number,
  pageSize: number,
  keyword = '',
  status = '',
): Promise<TenantListResult> {
  return getEnvelope<TenantListResult>(tenantListQuery(page, pageSize, keyword, status));
}

export async function createTenant(body: CreateTenantRequest): Promise<{ id: number }> {
  return postEnvelope<{ id: number }>(TENANT_PATH.create, body);
}

export async function updateTenant(id: number, body: UpdateTenantRequest): Promise<void> {
  await putEnvelope<null>(tenantDetail(id), body);
}

export type { TenantItem, TenantListResult };
