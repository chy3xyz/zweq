import { getEnvelope, postEnvelope, putEnvelope } from '#ui/api/client';

import { configPath, drawRecordQuery, LUCKY_DRAW_PATH } from './path';
import type { DrawRecord, DrawRecordListResult, ManualDrawRequest, ManualDrawResult } from './types';

export async function listDrawRecords(
  accountId: number,
  page: number,
  pageSize: number,
): Promise<DrawRecordListResult> {
  return getEnvelope<DrawRecordListResult>(
    drawRecordQuery(accountId, page, pageSize),
  );
}

export async function manualDraw(body: ManualDrawRequest): Promise<ManualDrawResult> {
  return postEnvelope<ManualDrawResult>(
    LUCKY_DRAW_PATH.draw,
    body,
  );
}

export async function getConfig(accountId: number): Promise<string> {
  const res = await getEnvelope<{ config: string }>(configPath(accountId));
  return res.config;
}

export async function setConfig(accountId: number, config: string): Promise<void> {
  await putEnvelope<null>(configPath(accountId), {
    config,
  });
}

export type { DrawRecord, DrawRecordListResult, ManualDrawRequest, ManualDrawResult };
