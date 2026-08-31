import { Show, type JSX } from 'solid-js';

import BaseModal, { type ModalSize } from './BaseModal';

interface Props {
  open: boolean;
  title: string;
  /** Show 保存/取消 footer; omit when the form renders its own actions. */
  onSubmit?: (e: SubmitEvent) => void;
  onClose: () => void;
  submitting?: boolean;
  error?: string | null;
  submitLabel?: string;
  cancelLabel?: string;
  size?: ModalSize;
  description?: string;
  children: JSX.Element;
}

/**
 * Standard admin form dialog (the `Add.vue` / `Edit.vue` shell):
 * title + error alert + field slot + 取消/确定 footer with a submitting state.
 * Field markup goes through `FormField`; the chrome (header/body scroll/
 * footer) is shared so every dialog looks and behaves the same.
 */
export default function FormModal(props: Props) {
  return (
    <BaseModal open={props.open} title={props.title} onClose={props.onClose} size={props.size ?? 'md'}>
      <Show when={props.description}>
        <p class="mb-4 text-xs leading-5 text-base-content/60">{props.description}</p>
      </Show>

      <Show when={props.error}>
        <div role="alert" class="alert alert-error mb-4 py-2 text-sm">
          {props.error}
        </div>
      </Show>

      <form
        onSubmit={(e) => {
          e.preventDefault();
          props.onSubmit?.(e);
        }}
        class="flex flex-col gap-4"
      >
        <div class="flex flex-col gap-4">{props.children}</div>

        <Show when={props.onSubmit}>
          <div class="-mx-5 -mb-4 flex justify-end gap-2 border-t border-base-200 bg-base-200/40 px-5 py-3">
            <button type="button" class="btn btn-ghost btn-sm" onClick={props.onClose} disabled={props.submitting}>
              {props.cancelLabel ?? '取消'}
            </button>
            <button type="submit" class="btn btn-primary btn-sm" disabled={props.submitting}>
              <Show when={props.submitting}>
                <span class="loading loading-spinner loading-xs" />
              </Show>
              {props.submitting ? '提交中…' : (props.submitLabel ?? '保存')}
            </button>
          </div>
        </Show>
      </form>
    </BaseModal>
  );
}
