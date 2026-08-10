import { http } from '#ui/api/client';
import { unwrapEnvelope } from '#ui/api/envelope';

import { ACCOUNT_PATH, accountDetail, accountListQuery, accountWechat } from './path';
import type {
  AccountItem,
  AccountListResult,
  CreateAccountRequest,
  SetWechatConfigRequest,
  UpdateAccountRequest,
  WechatConfigItem,
} from './types';

async function getEnvelope<T>(path: string): Promise<T> {
  const { data } = await http.get<{ code: number; msg: string; data: T }>(path);
  return unwrapEnvelope(data);
}

export async function listAccounts(page: number, pageSize: number, kind?: string): Promise<AccountListResult> {
  return getEnvelope<AccountListResult>(accountListQuery(page, pageSize, kind));
}

export async function createAccount(body: CreateAccountRequest): Promise<{ id: number }> {
  const { data } = await http.post<{ code: number; msg: string; data: { id: number } }>(ACCOUNT_PATH.create, body);
  return unwrapEnvelope(data);
}

export async function updateAccount(id: number, body: UpdateAccountRequest): Promise<void> {
  const { data } = await http.put<{ code: number; msg: string; data: null }>(accountDetail(id), body);
  unwrapEnvelope(data);
}

export async function deleteAccount(id: number): Promise<void> {
  const { data } = await http.delete<{ code: number; msg: string; data: null }>(accountDetail(id));
  unwrapEnvelope(data);
}

export async function getWechatConfig(id: number): Promise<WechatConfigItem | null> {
  return getEnvelope<WechatConfigItem | null>(accountWechat(id));
}

export async function setWechatConfig(id: number, body: SetWechatConfigRequest): Promise<void> {
  const { data } = await http.put<{ code: number; msg: string; data: null }>(accountWechat(id), body);
  unwrapEnvelope(data);
}

export type { AccountItem, AccountListResult };
