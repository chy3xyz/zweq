import { Show, type JSX } from 'solid-js';

interface Props {
  title: string;
  description?: string;
  total?: number;
  /** Rendered in the header action row, before 新增 (e.g. 导出、分类管理). */
  extra?: JSX.Element;
  onCreate?: () => void;
  createLabel?: string;
  onRefresh?: () => void;
  /** Filter bar slot; rendered in its own card above the content card. */
  search?: JSX.Element;
  children?: JSX.Element;
}

/**
 * Standard admin page shell (`common-seach-wrap` + `common-level-rail` +
 * content equivalent): header with actions, optional filter card, content card.
 */
export default function AdminCrudPage(props: Props) {
  return (
    <div class="space-y-4">
      <div class="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 class="text-xl font-semibold">{props.title}</h2>
          <Show when={props.description}>
            <p class="text-sm text-base-content/60">{props.description}</p>
          </Show>
          <Show when={props.total != null}>
            <p class="text-xs text-base-content/50">共 {props.total} 条</p>
          </Show>
        </div>
        <div class="flex items-center gap-2">
          {props.extra}
          <Show when={props.onRefresh}>
            <button
              type="button"
              class="btn btn-outline btn-sm"
              onClick={props.onRefresh}
              aria-label="刷新"
            >
              刷新
            </button>
          </Show>
          <Show when={props.onCreate}>
            <button type="button" class="btn btn-primary btn-sm" onClick={props.onCreate}>
              {props.createLabel ?? '新增'}
            </button>
          </Show>
        </div>
      </div>

      <Show when={props.search}>
        <div class="rounded-box border border-base-300 bg-base-100 p-4">{props.search}</div>
      </Show>

      <div class="rounded-box border border-base-300 bg-base-100 p-4">{props.children}</div>
    </div>
  );
}
