import { deleteEnvelope, getEnvelope, putEnvelope } from '#ui/api/client';

import { SETTING_PATH, settingListQuery } from './path';
import type { SettingItem, SettingListResult, UpdateSettingRequest } from './types';

export async function listSettings(page: number, pageSize: number): Promise<SettingListResult> {
  return getEnvelope<SettingListResult>(
    settingListQuery(page, pageSize),
  );
}

export async function getSetting(key: string): Promise<SettingItem | null> {
  return getEnvelope<SettingItem | null>(
    SETTING_PATH.item(key),
  );
}

export async function setSetting(
  key: string,
  body: UpdateSettingRequest,
): Promise<{ id: number }> {
  return putEnvelope<{ id: number }>(
    SETTING_PATH.item(key),
    body,
  );
}

export async function deleteSetting(key: string): Promise<void> {
  await deleteEnvelope<null>(
    SETTING_PATH.item(key),
  );
}
