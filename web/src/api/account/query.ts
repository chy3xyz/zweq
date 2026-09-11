import { deleteEnvelope, getEnvelope, postEnvelope, putEnvelope } from '#ui/api/client';

import { ACCOUNT_PATH, accountDetail, accountListQuery, accountWechat } from './path';
import type {
  AccountItem,
  AccountListResult,
  CreateAccountRequest,
  SetWechatConfigRequest,
  UpdateAccountRequest,
  WechatConfigItem,
} from './types';

export async function listAccounts(
  page: number,
  pageSize: number,
  kind?: string,
  keyword = '',
  status = '',
): Promise<AccountListResult> {
  return getEnvelope<AccountListResult>(accountListQuery(page, pageSize, kind, keyword, status));
}

export async function createAccount(body: CreateAccountRequest): Promise<{ id: number }> {
  return postEnvelope<{ id: number }>(ACCOUNT_PATH.create, body);
}

export async function updateAccount(id: number, body: UpdateAccountRequest): Promise<void> {
  await putEnvelope<null>(accountDetail(id), body);
}

export async function deleteAccount(id: number): Promise<void> {
  await deleteEnvelope<null>(accountDetail(id));
}

export async function getWechatConfig(id: number): Promise<WechatConfigItem | null> {
  return getEnvelope<WechatConfigItem | null>(accountWechat(id));
}

export async function setWechatConfig(id: number, body: SetWechatConfigRequest): Promise<void> {
  await putEnvelope<null>(accountWechat(id), body);
}

export type { AccountItem, AccountListResult };
