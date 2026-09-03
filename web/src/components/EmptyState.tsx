import { Show, type JSX } from 'solid-js';

interface EmptyStateProps {
  /** Optional leading symbol (e.g. an icon), rendered above the title. */
  icon?: JSX.Element;
  /** Primary line describing the missing content. */
  title: string;
  /** Optional secondary line rendered under the title. */
  description?: string;
  /** Optional action slot (e.g. a 新增 button), rendered below the description. */
  action?: JSX.Element;
}

/**
 * Reusable empty-state placeholder: symbol + title + optional description +
 * action slot. Use in place of inline "暂无数据" text inside cards or page content.
 */
export default function EmptyState(props: EmptyStateProps) {
  return (
    <div class="flex flex-col items-center justify-center gap-3 px-6 py-16 text-center">
      <Show when={props.icon}>
        <div class="text-base-content/30">{props.icon}</div>
      </Show>
      <div class="space-y-1">
        <p class="text-base-content/70">{props.title}</p>
        <Show when={props.description}>
          <p class="text-sm text-base-content/50">{props.description}</p>
        </Show>
      </div>
      <Show when={props.action}>
        <div class="mt-1">{props.action}</div>
      </Show>
    </div>
  );
}
