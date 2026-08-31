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
 * Field markup stays with the caller; only the chrome is shared.
 */
export default function FormModal(props: Props) {
  return (
    <BaseModal open={props.open} title={props.title} onClose={props.onClose} size={props.size ?? 'md'}>
      <Show when={props.description}>
        <p class="mb-3 text-sm text-base-content/60">{props.description}</p>
      </Show>

      <Show when={props.error}>
        <div role="alert" class="alert alert-error mb-3 py-2 text-sm">
          {props.error}
        </div>
      </Show>

      <form
        onSubmit={(e) => {
          e.preventDefault();
          props.onSubmit?.(e);
        }}
        class="space-y-3"
      >
        {props.children}

        <Show when={props.onSubmit}>
          <div class="modal-action mt-5">
            <button type="button" class="btn btn-sm" onClick={props.onClose} disabled={props.submitting}>
              {props.cancelLabel ?? '取消'}
            </button>
            <button type="submit" class="btn btn-primary btn-sm" disabled={props.submitting}>
              {props.submitting ? '提交中…' : (props.submitLabel ?? '保存')}
            </button>
          </div>
        </Show>
      </form>
    </BaseModal>
  );
}
