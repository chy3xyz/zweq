import { http } from '#ui/api/client';
import { unwrapEnvelope } from '#ui/api/envelope';

import { LOG_PATH, logListQuery } from './path';
import type { LogItem, LogListResult } from './types';

async function getEnvelope<T>(path: string): Promise<T> {
  const { data } = await http.get<{ code: number; msg: string; data: T }>(path);
  return unwrapEnvelope(data);
}

export async function listLogs(page: number, pageSize: number, accountId: number): Promise<LogListResult> {
  return getEnvelope<LogListResult>(logListQuery(page, pageSize, accountId));
}

export async function sendCustomerText(accountId: number, openid: string, content: string): Promise<void> {
  const { data } = await http.post<{ code: number; msg: string; data: null }>(LOG_PATH.customerText, {
    account_id: accountId,
    openid,
    content,
  });
  unwrapEnvelope(data);
}

export type { LogItem, LogListResult };
