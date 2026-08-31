import { type JSX, Show } from 'solid-js';

interface Props {
  open: boolean;
  title: string;
  onClose: () => void;
  children: JSX.Element;
  size?: ModalSize;
}

export type ModalSize = 'sm' | 'md' | 'lg' | 'xl';

const sizeClass: Record<ModalSize, string> = {
  sm: 'max-w-md',
  md: 'max-w-lg',
  lg: 'max-w-2xl',
  xl: 'max-w-4xl',
};

function BaseModal(props: Props) {
  return (
    <Show when={props.open}>
      <div class="modal modal-open">
        <div class={`modal-box ${sizeClass[props.size ?? 'md']}`}>
          <div class="mb-4 flex items-center justify-between gap-3">
            <h3 class="text-lg font-bold">{props.title}</h3>
            <button type="button" class="btn btn-ghost btn-sm btn-circle" onClick={props.onClose} aria-label="关闭">
              ✕
            </button>
          </div>
          {props.children}
        </div>
        <button type="button" class="modal-backdrop" aria-label="关闭" onClick={props.onClose} />
      </div>
    </Show>
  );
}

export default BaseModal;
