import { http } from '#ui/api/client';
import { unwrapEnvelope } from '#ui/api/envelope';

import { SETTING_PATH, settingListQuery } from './path';
import type { SettingItem, SettingListResult, UpdateSettingRequest } from './types';

export async function listSettings(page: number, pageSize: number): Promise<SettingListResult> {
  const { data } = await http.get<{ code: number; msg: string; data: SettingListResult }>(
    settingListQuery(page, pageSize),
  );
  return unwrapEnvelope(data);
}

export async function getSetting(key: string): Promise<SettingItem | null> {
  const { data } = await http.get<{ code: number; msg: string; data: SettingItem | null }>(
    SETTING_PATH.item(key),
  );
  return unwrapEnvelope(data);
}

export async function setSetting(
  key: string,
  body: UpdateSettingRequest,
): Promise<{ id: number }> {
  const { data } = await http.put<{ code: number; msg: string; data: { id: number } }>(
    SETTING_PATH.item(key),
    body,
  );
  return unwrapEnvelope(data);
}

export async function deleteSetting(key: string): Promise<void> {
  const { data } = await http.delete<{ code: number; msg: string; data: null }>(
    SETTING_PATH.item(key),
  );
  unwrapEnvelope(data);
}
