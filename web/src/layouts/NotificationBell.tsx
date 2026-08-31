import { A } from '@solidjs/router';
import { For, Show, createSignal, onCleanup, onMount } from 'solid-js';

import {
  deleteNotification,
  listNotifications,
  markAllRead,
  markRead,
  toApiError,
  unreadCount,
  type NotificationItem,
} from '#ui/api';
import { formatDateTime } from '#ui/utils';

function NotificationBell() {
  const [open, setOpen] = createSignal(false);
  const [unread, setUnread] = createSignal(0);
  const [items, setItems] = createSignal<NotificationItem[]>([]);

  const refresh = async () => {
    try {
      const [count, result] = await Promise.all([unreadCount(), listNotifications(1, 8)]);
      setUnread(count);
      setItems(result.list);
    } catch {
      // keep previous state on transient errors
    }
  };

  onMount(() => {
    void refresh();
    const timer = window.setInterval(() => void refresh(), 30_000);
    onCleanup(() => window.clearInterval(timer));
  });

  const onMarkRead = async (id: number) => {
    try {
      await markRead(id);
      await refresh();
    } catch (err) {
      window.alert(toApiError(err).message);
    }
  };

  const onMarkAll = async () => {
    try {
      await markAllRead();
      await refresh();
    } catch (err) {
      window.alert(toApiError(err).message);
    }
  };

  const onDelete = async (id: number) => {
    try {
      await deleteNotification(id);
      await refresh();
    } catch (err) {
      window.alert(toApiError(err).message);
    }
  };

  return (
    <div class="relative">
      <button
        type="button"
        class="btn btn-ghost btn-circle btn-sm relative"
        onClick={() => {
          setOpen(!open());
          if (!open()) void refresh();
        }}
        aria-label="通知"
      >
        <span class="text-base">🔔</span>
        <Show when={unread() > 0}>
          <span class="badge badge-error badge-xs absolute -top-0.5 -right-0.5">
            {unread() > 99 ? '99+' : unread()}
          </span>
        </Show>
      </button>

      <Show when={open()}>
        <div class="absolute right-0 z-50 mt-2 w-80 rounded-lg border border-base-300 bg-base-100 shadow-xl">
          <div class="flex items-center justify-between border-b border-base-300 px-3 py-2">
            <span class="text-sm font-semibold">通知</span>
            <button type="button" class="btn btn-ghost btn-xs" onClick={onMarkAll}>
              全部已读
            </button>
          </div>
          <div class="max-h-80 overflow-y-auto">
            <Show
              when={items().length > 0}
              fallback={<p class="px-3 py-6 text-center text-sm text-base-content/50">暂无通知</p>}
            >
              <For each={items()}>
                {(item) => (
                  <div class={`border-b border-base-200 px-3 py-2 ${item.read ? 'opacity-60' : ''}`}>
                    <div class="flex items-start justify-between gap-2">
                      <div class="min-w-0">
                        <p class="truncate text-sm font-medium">{item.title}</p>
                        <p class="truncate text-xs text-base-content/60">{item.body}</p>
                        <p class="mt-0.5 text-xs text-base-content/40">{formatDateTime(item.created_at)}</p>
                      </div>
                      <div class="flex shrink-0 gap-1">
                        <Show when={!item.read}>
                          <button type="button" class="btn btn-ghost btn-xs" onClick={() => onMarkRead(item.id)}>
                            已读
                          </button>
                        </Show>
                        <button type="button" class="btn btn-ghost btn-xs text-error" onClick={() => onDelete(item.id)}>
                          删除
                        </button>
                      </div>
                    </div>
                  </div>
                )}
              </For>
            </Show>
          </div>
        </div>
      </Show>
    </div>
  );
}

export default NotificationBell;
