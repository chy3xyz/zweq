import { Show, type JSX } from 'solid-js';

interface Props {
  label: string;
  required?: boolean;
  /** Muted one-liner under the control. */
  hint?: string;
  /** Extra label-side content (e.g. a "选择图片" button). */
  labelExtra?: JSX.Element;
  class?: string;
  children: JSX.Element;
}

/**
 * Uniform form field wrapper for modal forms: small medium-weight label with
 * a required marker, the control, and an optional hint line. Every modal
 * form field should use this so dialogs look consistent.
 */
function FormField(props: Props) {
  return (
    <div class={props.class ?? 'w-full'}>
      <div class="mb-1 flex items-center justify-between gap-2">
        <span class="flex items-center gap-1 text-xs font-medium text-base-content/70">
          {props.label}
          <Show when={props.required}>
            <span class="text-error" aria-hidden>
              *
            </span>
          </Show>
        </span>
        <Show when={props.labelExtra}>{props.labelExtra}</Show>
      </div>
      {props.children}
      <Show when={props.hint}>
        <p class="mt-1 text-xs text-base-content/50">{props.hint}</p>
      </Show>
    </div>
  );
}

export default FormField;
