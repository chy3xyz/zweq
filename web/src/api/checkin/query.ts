import { http } from '#ui/api/client';
import { unwrapEnvelope } from '#ui/api/envelope';

import { checkinRecordQuery } from './path';
import type { CheckinRecord, CheckinRecordListResult } from './types';

export async function listCheckinRecords(
  accountId: number,
  page: number,
  pageSize: number,
): Promise<CheckinRecordListResult> {
  const { data } = await http.get<{ code: number; msg: string; data: CheckinRecordListResult }>(
    checkinRecordQuery(accountId, page, pageSize),
  );
  return unwrapEnvelope(data);
}

export type { CheckinRecord, CheckinRecordListResult };
