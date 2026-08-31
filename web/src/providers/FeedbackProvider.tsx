import { For, Show, createSignal, onCleanup, type JSX } from 'solid-js';

import { toApiError } from '#ui/api';
import BaseModal from '#ui/components/BaseModal';
import {
  FeedbackContext,
  type ConfirmOptions,
  type FeedbackActions,
  type ToastKind,
} from '#ui/context/FeedbackContext';

interface Toast {
  id: number;
  kind: ToastKind;
  message: string;
}

interface PendingConfirm extends ConfirmOptions {
  resolve: (value: boolean) => void;
}

const TOAST_MS = 2600;

const alertClass: Record<ToastKind, string> = {
  success: 'alert-success',
  error: 'alert-error',
  info: 'alert-info',
};

/**
 * Global feedback host: replaces the `window.alert` / `window.confirm` calls
 * scattered across admin pages with toasts and a promise-based confirm dialog.
 */
export function FeedbackProvider(props: { children?: JSX.Element }) {
  const [toasts, setToasts] = createSignal<Toast[]>([]);
  const [pending, setPending] = createSignal<PendingConfirm | null>(null);
  let nextId = 0;
  const timers = new Set<ReturnType<typeof setTimeout>>();

  onCleanup(() => {
    timers.forEach(clearTimeout);
    timers.clear();
  });

  const toast: FeedbackActions['toast'] = (message, kind = 'success') => {
    const id = ++nextId;
    setToasts((prev) => [...prev, { id, kind, message }]);
    const timer = setTimeout(() => {
      setToasts((prev) => prev.filter((t) => t.id !== id));
      timers.delete(timer);
    }, TOAST_MS);
    timers.add(timer);
  };

  const confirm: FeedbackActions['confirm'] = (options) => {
    const opts = typeof options === 'string' ? { message: options } : options;
    return new Promise<boolean>((resolve) => {
      setPending({ ...opts, resolve });
    });
  };

  const settle = (value: boolean) => {
    const current = pending();
    setPending(null);
    current?.resolve(value);
  };

  const runAction: FeedbackActions['runAction'] = async ({ confirm: gate, action, success, onDone }) => {
    if (gate != null && !(await confirm(gate))) return;
    try {
      await action();
      if (success) toast(success);
      onDone?.();
    } catch (err) {
      toast(toApiError(err).message, 'error');
    }
  };

  const value: FeedbackActions = { toast, confirm, runAction };

  return (
    <FeedbackContext.Provider value={value}>
      {props.children}

      <div class="toast toast-top toast-center z-[100] w-full max-w-sm">
        <For each={toasts()}>
          {(item) => (
            <div class={`alert ${alertClass[item.kind]} shadow-lg`}>
              <span class="text-sm">{item.message}</span>
            </div>
          )}
        </For>
      </div>

      <Show when={pending()}>
        {(dialog) => (
          <BaseModal open title={dialog().title ?? '提示'} onClose={() => settle(false)} size="sm">
            <p class="text-sm">{dialog().message}</p>
            <div class="modal-action">
              <button type="button" class="btn btn-sm" onClick={() => settle(false)}>
                {dialog().cancelText ?? '取消'}
              </button>
              <button
                type="button"
                class={`btn btn-sm ${dialog().danger ? 'btn-error' : 'btn-primary'}`}
                onClick={() => settle(true)}
              >
                {dialog().confirmText ?? '确定'}
              </button>
            </div>
          </BaseModal>
        )}
      </Show>
    </FeedbackContext.Provider>
  );
}
