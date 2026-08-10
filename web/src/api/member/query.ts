import { http } from '#ui/api/client';
import { unwrapEnvelope } from '#ui/api/envelope';

import { fanListQuery } from './path';
import type { FanItem, FanListResult } from './types';

async function getEnvelope<T>(path: string): Promise<T> {
  const { data } = await http.get<{ code: number; msg: string; data: T }>(path);
  return unwrapEnvelope(data);
}

export async function listFans(page: number, pageSize: number, accountId: number, keyword?: string): Promise<FanListResult> {
  return getEnvelope<FanListResult>(fanListQuery(page, pageSize, accountId, keyword));
}

export type { FanItem, FanListResult };
