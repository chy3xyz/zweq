import { http } from '#ui/api/client';
import { unwrapEnvelope } from '#ui/api/envelope';

import { logListQuery } from './path';
import type { LogItem, LogListResult } from './types';

async function getEnvelope<T>(path: string): Promise<T> {
  const { data } = await http.get<{ code: number; msg: string; data: T }>(path);
  return unwrapEnvelope(data);
}

export async function listLogs(page: number, pageSize: number, accountId: number): Promise<LogListResult> {
  return getEnvelope<LogListResult>(logListQuery(page, pageSize, accountId));
}

export type { LogItem, LogListResult };
