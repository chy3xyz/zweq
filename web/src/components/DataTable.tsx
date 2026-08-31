import { For, Show, type JSX } from 'solid-js';

import Pagination from './Pagination';

export interface Column<T> {
  key: string;
  title: string;
  render: (row: T) => JSX.Element;
  class?: string;
  headerClass?: string;
}

interface DataTableProps<T> {
  columns: Column<T>[];
  rows: T[];
  rowKey: (row: T) => string | number;
  total: number;
  page: number;
  totalPages: number;
  loading: boolean;
  error: string | null;
  emptyText?: string;
  onPageChange: (page: number) => void;
  pageSize?: number;
  onPageSizeChange?: (size: number) => void;
  actions?: (row: T) => JSX.Element;
  actionsTitle?: string;
}

/**
 * Data-driven table (zmsaas-style): columns config + rows + pagination state
 * from `usePaged`, with shared loading/empty/error rendering.
 */
export default function DataTable<T>(props: DataTableProps<T>) {
  const columnCount = () => props.columns.length + (props.actions ? 1 : 0);

  return (
    <div class="space-y-4">
      <Show when={props.error}>
        <div role="alert" class="alert alert-error py-2 text-sm">
          {props.error}
        </div>
      </Show>

      <div class="relative overflow-x-auto rounded-lg border border-base-300">
        <table class="table" classList={{ 'opacity-50': props.loading }}>
          <thead>
            <tr>
              <For each={props.columns}>{(col) => <th class={col.headerClass}>{col.title}</th>}</For>
              <Show when={props.actions}>
                <th class="sticky right-0 bg-base-100 text-right">{props.actionsTitle ?? '操作'}</th>
              </Show>
            </tr>
          </thead>
          <tbody>
            <Show when={props.rows.length === 0 && !props.loading}>
              <tr>
                <td colspan={columnCount()} class="py-10 text-center text-base-content/50">
                  {props.emptyText ?? '暂无数据'}
                </td>
              </tr>
            </Show>
            <For each={props.rows}>
              {(row) => (
                <tr class="hover">
                  <For each={props.columns}>{(col) => <td class={col.class}>{col.render(row)}</td>}</For>
                  <Show when={props.actions}>
                    <td class="sticky right-0 bg-base-100 text-right">
                      <div class="flex justify-end gap-1">{props.actions!(row)}</div>
                    </td>
                  </Show>
                </tr>
              )}
            </For>
          </tbody>
        </table>

        <Show when={props.loading}>
          <div class="pointer-events-none absolute inset-0 flex items-center justify-center bg-base-100/40">
            <span class="loading loading-spinner loading-md text-primary" />
          </div>
        </Show>
      </div>

      <Pagination
        page={props.page}
        totalPages={props.totalPages}
        total={props.total}
        pageSize={props.pageSize ?? 20}
        loading={props.loading}
        onPageChange={props.onPageChange}
        onPageSizeChange={props.onPageSizeChange}
      />
    </div>
  );
}
