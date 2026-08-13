import { http } from '#ui/api/client';
import { unwrapEnvelope } from '#ui/api/envelope';

import { MENU_PATH } from './path';
import type { SaveMenuRequest, WechatMenu } from './types';

export async function getMenu(accountId: number): Promise<WechatMenu> {
  const { data } = await http.get<{ code: number; msg: string; data: WechatMenu }>(MENU_PATH.get(accountId));
  return unwrapEnvelope(data);
}

export async function saveMenu(accountId: number, body: SaveMenuRequest): Promise<{ id: number }> {
  const { data } = await http.put<{ code: number; msg: string; data: { id: number } }>(MENU_PATH.save(accountId), body);
  return unwrapEnvelope(data);
}

export async function publishMenu(accountId: number): Promise<{ id: number }> {
  const { data } = await http.post<{ code: number; msg: string; data: { id: number } }>(
    MENU_PATH.publish(accountId),
    {},
  );
  return unwrapEnvelope(data);
}

export async function fetchMenu(accountId: number): Promise<WechatMenu> {
  const { data } = await http.get<{ code: number; msg: string; data: WechatMenu }>(MENU_PATH.fetch(accountId));
  return unwrapEnvelope(data);
}

export async function deleteRemoteMenu(accountId: number): Promise<void> {
  const { data } = await http.delete<{ code: number; msg: string; data: null }>(MENU_PATH.deleteRemote(accountId));
  unwrapEnvelope(data);
}

export type { SaveMenuRequest, WechatMenu };
