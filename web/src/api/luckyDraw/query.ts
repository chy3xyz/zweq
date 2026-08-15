import { http } from '#ui/api/client';
import { unwrapEnvelope } from '#ui/api/envelope';

import { configPath, drawRecordQuery, LUCKY_DRAW_PATH } from './path';
import type { DrawRecord, DrawRecordListResult, ManualDrawRequest, ManualDrawResult } from './types';

export async function listDrawRecords(
  accountId: number,
  page: number,
  pageSize: number,
): Promise<DrawRecordListResult> {
  const { data } = await http.get<{ code: number; msg: string; data: DrawRecordListResult }>(
    drawRecordQuery(accountId, page, pageSize),
  );
  return unwrapEnvelope(data);
}

export async function manualDraw(body: ManualDrawRequest): Promise<ManualDrawResult> {
  const { data } = await http.post<{ code: number; msg: string; data: ManualDrawResult }>(
    LUCKY_DRAW_PATH.draw,
    body,
  );
  return unwrapEnvelope(data);
}

export async function getConfig(accountId: number): Promise<string> {
  const { data } = await http.get<{ code: number; msg: string; data: { config: string } }>(
    configPath(accountId),
  );
  return unwrapEnvelope(data).config;
}

export async function setConfig(accountId: number, config: string): Promise<void> {
  const { data } = await http.put<{ code: number; msg: string; data: null }>(configPath(accountId), {
    config,
  });
  unwrapEnvelope(data);
}

export type { DrawRecord, DrawRecordListResult, ManualDrawRequest, ManualDrawResult };
