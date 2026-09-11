import { deleteEnvelope, getEnvelope, postEnvelope, putEnvelope } from '#ui/api/client';

import { accountModule, accountModuleConfig, accountModules, MODULE_PATH, moduleListQuery } from './path';
import type { AdminNavItem, BindingItem, BindModuleRequest, ModuleConfigResponse, ModuleItem, ModuleListResult, RegisterModuleRequest, UpdateModuleConfigRequest, UpdateModuleRequest } from './types';

export async function listModules(page: number, pageSize: number, keyword?: string): Promise<ModuleListResult> {
  return getEnvelope<ModuleListResult>(moduleListQuery(page, pageSize, keyword));
}

export async function registerModule(body: RegisterModuleRequest): Promise<{ id: number }> {
  return postEnvelope<{ id: number }>(MODULE_PATH.create, body);
}

export async function updateModule(id: number, body: UpdateModuleRequest): Promise<{ id: number }> {
  return putEnvelope<{ id: number }>(MODULE_PATH.update(id), body);
}

export async function listAccountModules(accountId: number): Promise<BindingItem[]> {
  const res = await getEnvelope<{ items: BindingItem[] }>(accountModules(accountId));
  return res.items;
}

export async function bindModule(accountId: number, body: BindModuleRequest): Promise<{ id: number }> {
  return putEnvelope<{ id: number }>(accountModules(accountId), body);
}

export async function unbindModule(accountId: number, module: string): Promise<void> {
  await deleteEnvelope<null>(accountModule(accountId, module));
}

export async function getModuleConfig(accountId: number, module: string): Promise<ModuleConfigResponse> {
  return getEnvelope<ModuleConfigResponse>(accountModuleConfig(accountId, module));
}

export async function updateModuleConfig(
  accountId: number,
  module: string,
  body: UpdateModuleConfigRequest,
): Promise<{ id: number }> {
  return putEnvelope<{ id: number }>(accountModuleConfig(accountId, module), body);
}

export async function getAdminNav(accountId?: number | null): Promise<AdminNavItem[]> {
  const params = new URLSearchParams();
  if (accountId != null && accountId > 0) params.set('account_id', String(accountId));
  const qs = params.toString();
  const path = qs ? `${MODULE_PATH.adminNav}?${qs}` : MODULE_PATH.adminNav;
  const res = await getEnvelope<{ items: AdminNavItem[] }>(path);
  return res.items;
}

export type { AdminNavItem, BindingItem, ModuleItem, ModuleListResult };
