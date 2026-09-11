import { getEnvelope } from '#ui/api/client';

import { checkinRecordQuery } from './path';
import type { CheckinRecord, CheckinRecordListResult } from './types';

export async function listCheckinRecords(
  accountId: number,
  page: number,
  pageSize: number,
): Promise<CheckinRecordListResult> {
  return getEnvelope<CheckinRecordListResult>(
    checkinRecordQuery(accountId, page, pageSize),
  );
}

export type { CheckinRecord, CheckinRecordListResult };
