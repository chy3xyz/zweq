import { deleteEnvelope, getEnvelope, postEnvelope, putEnvelope } from '#ui/api/client';

import { MENU_PATH } from './path';
import type { SaveMenuRequest, WechatMenu } from './types';

export async function getMenu(accountId: number): Promise<WechatMenu> {
  return getEnvelope<WechatMenu>(MENU_PATH.get(accountId));
}

export async function saveMenu(accountId: number, body: SaveMenuRequest): Promise<{ id: number }> {
  return putEnvelope<{ id: number }>(MENU_PATH.save(accountId), body);
}

export async function publishMenu(accountId: number): Promise<{ id: number }> {
  return postEnvelope<{ id: number }>(
    MENU_PATH.publish(accountId),
    {},
  );
}

export async function fetchMenu(accountId: number): Promise<WechatMenu> {
  return getEnvelope<WechatMenu>(MENU_PATH.fetch(accountId));
}

export async function deleteRemoteMenu(accountId: number): Promise<void> {
  await deleteEnvelope<null>(MENU_PATH.deleteRemote(accountId));
}

export type { SaveMenuRequest, WechatMenu };
