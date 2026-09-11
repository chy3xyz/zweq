import { getEnvelope, postEnvelope } from '#ui/api/client';

import { LOG_PATH, logListQuery } from './path';
import type { LogItem, LogListResult } from './types';

export async function listLogs(page: number, pageSize: number, accountId: number): Promise<LogListResult> {
  return getEnvelope<LogListResult>(logListQuery(page, pageSize, accountId));
}

export async function sendCustomerText(accountId: number, openid: string, content: string): Promise<void> {
  await postEnvelope<null>(LOG_PATH.customerText, {
    account_id: accountId,
    openid,
    content,
  });
}

export type { LogItem, LogListResult };
