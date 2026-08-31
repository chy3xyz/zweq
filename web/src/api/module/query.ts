import { http } from '#ui/api/client';
import { unwrapEnvelope } from '#ui/api/envelope';

import { accountModule, accountModules, MODULE_PATH, moduleListQuery } from './path';
import type { AdminNavItem, BindingItem, BindModuleRequest, ModuleItem, ModuleListResult, RegisterModuleRequest } from './types';

async function getEnvelope<T>(path: string): Promise<T> {
  const { data } = await http.get<{ code: number; msg: string; data: T }>(path);
  return unwrapEnvelope(data);
}

export async function listModules(page: number, pageSize: number): Promise<ModuleListResult> {
  return getEnvelope<ModuleListResult>(moduleListQuery(page, pageSize));
}

export async function registerModule(body: RegisterModuleRequest): Promise<{ id: number }> {
  const { data } = await http.post<{ code: number; msg: string; data: { id: number } }>(MODULE_PATH.create, body);
  return unwrapEnvelope(data);
}

export async function listAccountModules(accountId: number): Promise<BindingItem[]> {
  const res = await getEnvelope<{ items: BindingItem[] }>(accountModules(accountId));
  return res.items;
}

export async function bindModule(accountId: number, body: BindModuleRequest): Promise<{ id: number }> {
  const { data } = await http.put<{ code: number; msg: string; data: { id: number } }>(accountModules(accountId), body);
  return unwrapEnvelope(data);
}

export async function unbindModule(accountId: number, module: string): Promise<void> {
  const { data } = await http.delete<{ code: number; msg: string; data: null }>(accountModule(accountId, module));
  unwrapEnvelope(data);
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
