import { getEnvelope, http, postEnvelope } from '#ui/api/client';

import { NOTIFY_PATH, notifyDetail, notifyListQuery, notifyRead } from './path';
import type { NotificationListResult } from './types';

export async function listNotifications(page: number, pageSize: number, unread?: boolean): Promise<NotificationListResult> {
  return getEnvelope<NotificationListResult>(notifyListQuery(page, pageSize, unread));
}

export async function unreadCount(): Promise<number> {
  const data = await getEnvelope<{ unread: number }>(NOTIFY_PATH.unreadCount);
  return data.unread;
}

export async function markRead(id: number): Promise<void> {
  await postEnvelope<null>(notifyRead(id));
}

export async function markAllRead(): Promise<void> {
  await postEnvelope<null>(NOTIFY_PATH.readAll);
}

export async function deleteNotification(id: number): Promise<void> {
  await http.delete(notifyDetail(id));
}
