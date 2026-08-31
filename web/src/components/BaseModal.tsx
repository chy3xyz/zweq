import { type JSX, Show } from 'solid-js';

export type ModalSize = 'sm' | 'md' | 'lg' | 'xl';

interface Props {
  open: boolean;
  title: string;
  onClose: () => void;
  children: JSX.Element;
  size?: ModalSize;
}

const sizeClass: Record<ModalSize, string> = {
  sm: 'max-w-md',
  md: 'max-w-lg',
  lg: 'max-w-2xl',
  xl: 'max-w-4xl',
};

/**
 * Dialog skeleton shared by every admin modal: bordered header with the
 * close affordance, a scrollable body capped at 85vh, so long forms never
 * push their footer off-screen. Keep it chrome-only — layout belongs to the
 * caller (FormModal adds title-description/footer; pickers add toolbars).
 */
function BaseModal(props: Props) {
  return (
    <Show when={props.open}>
      <div class="modal modal-open">
        <div class={`modal-box flex max-h-[85vh] flex-col gap-0 p-0 ${sizeClass[props.size ?? 'md']}`}>
          <div class="flex shrink-0 items-center justify-between gap-3 border-b border-base-200 px-5 py-3.5">
            <h3 class="text-base font-semibold">{props.title}</h3>
            <button
              type="button"
              class="btn btn-circle btn-ghost btn-xs text-base-content/50 hover:text-base-content"
              onClick={props.onClose}
              aria-label="关闭"
            >
              ✕
            </button>
          </div>
          <div class="min-h-0 flex-1 overflow-y-auto px-5 py-4">{props.children}</div>
        </div>
        <button type="button" class="modal-backdrop" aria-label="关闭" onClick={props.onClose} />
      </div>
    </Show>
  );
}

export default BaseModal;
