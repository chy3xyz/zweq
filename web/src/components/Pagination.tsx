import { For, Show, createMemo, createSignal } from 'solid-js';

export const DEFAULT_PAGE_SIZES = [10, 20, 50, 100];

interface Props {
  page: number;
  totalPages: number;
  total: number;
  pageSize: number;
  loading: boolean;
  pageSizes?: number[];
  onPageChange: (page: number) => void;
  onPageSizeChange?: (size: number) => void;
}

/** Window of page numbers around the current page (max 5 entries). */
function pageWindow(page: number, totalPages: number): number[] {
  const span = Math.min(5, totalPages);
  let start = Math.max(1, page - Math.floor(span / 2));
  const end = Math.min(totalPages, start + span - 1);
  start = Math.max(1, end - span + 1);
  return Array.from({ length: end - start + 1 }, (_, i) => start + i);
}

/**
 * Standard admin pager (el-pagination-like): total count, page-size select,
 * first/prev/numbered/next/last navigation and a jump box.
 */
export default function Pagination(props: Props) {
  const [jump, setJump] = createSignal('');
  const sizes = () => props.pageSizes ?? DEFAULT_PAGE_SIZES;
  const pages = createMemo(() => pageWindow(props.page, props.totalPages));

  const goto = (target: number) => {
    const next = Math.min(props.totalPages, Math.max(1, target));
    if (next !== props.page && !props.loading) props.onPageChange(next);
  };

  const submitJump = (e: SubmitEvent | KeyboardEvent) => {
    e.preventDefault();
    const value = Number(jump());
    if (!Number.isInteger(value) || value < 1) return;
    goto(value);
    setJump('');
  };

  return (
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div class="flex items-center gap-3 text-sm text-base-content/60">
        <span>共 {props.total} 条</span>
        <Show when={props.onPageSizeChange}>
          <label class="flex items-center gap-1">
            每页
            <select
              class="select select-bordered select-xs w-20"
              value={props.pageSize}
              disabled={props.loading}
              onChange={(e) => props.onPageSizeChange?.(Number(e.currentTarget.value))}
            >
              <For each={sizes()}>{(size) => <option value={size}>{size}</option>}</For>
            </select>
            条
          </label>
        </Show>
      </div>

      <div class="flex items-center gap-1">
        <button
          type="button"
          class="btn btn-xs"
          disabled={props.page <= 1 || props.loading}
          onClick={() => goto(1)}
        >
          首页
        </button>
        <button
          type="button"
          class="btn btn-xs"
          disabled={props.page <= 1 || props.loading}
          onClick={() => goto(props.page - 1)}
        >
          上一页
        </button>
        <For each={pages()}>
          {(p) => (
            <button
              type="button"
              class={`btn btn-xs ${p === props.page ? 'btn-primary' : ''}`}
              disabled={props.loading}
              onClick={() => goto(p)}
            >
              {p}
            </button>
          )}
        </For>
        <button
          type="button"
          class="btn btn-xs"
          disabled={props.page >= props.totalPages || props.loading}
          onClick={() => goto(props.page + 1)}
        >
          下一页
        </button>
        <button
          type="button"
          class="btn btn-xs"
          disabled={props.page >= props.totalPages || props.loading}
          onClick={() => goto(props.totalPages)}
        >
          末页
        </button>
        <form class="ml-2 flex items-center gap-1" onSubmit={submitJump}>
          <span class="text-xs text-base-content/60">跳至</span>
          <input
            class="input input-bordered input-xs w-14"
            value={jump()}
            onInput={(e) => setJump(e.currentTarget.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') submitJump(e);
            }}
          />
          <span class="text-xs text-base-content/60">页</span>
        </form>
      </div>
    </div>
  );
}
