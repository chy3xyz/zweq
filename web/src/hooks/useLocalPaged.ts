import { createEffect, createMemo, createSignal, onMount } from 'solid-js';

import { toApiError } from '#ui/api';

interface Options<T> {
  /** Current keyword; changing it resets to page 1. */
  keyword?: () => string;
  /** Keyword matcher; receives the trimmed, lower-cased keyword. */
  match?: (row: T, keyword: string) => boolean;
  /**
   * Extra reactive predicate (e.g. a status/type select). Reads signals
   * directly — it runs inside a memo, so it is tracked.
   */
  filter?: (row: T) => boolean;
  /** Tracked by the "back to page 1" effect; pass the whole filter state. */
  resetKey?: () => unknown;
  /** Skip fetching while false (e.g. before an account is selected). */
  enabled?: () => boolean;
  pageSize?: number;
  /** Re-fetch when this accessor changes (e.g. selected account). */
  watch?: () => unknown;
}

/**
 * Client-side paged list for the many modules whose backend exposes
 * `(account_id, page, page_size)` but no keyword filter (coupon, points,
 * seckill, member-card, distribution, account, tenant, ...).
 *
 * Rows are fetched once in a windowed request, then searched and paginated
 * locally — which keeps the standard 搜索 / 分页 UX honest instead of
 * filtering only the visible page. Only use it for small reference tables.
 */
export function useLocalPaged<T>(loader: () => Promise<T[]>, options: Options<T> = {}) {
  const [rows, setRows] = createSignal<T[]>([]);
  const [page, setPage] = createSignal(1);
  const [pageSize, setPageSize] = createSignal(options.pageSize ?? 20);
  const [loading, setLoading] = createSignal(false);
  const [error, setError] = createSignal<string | null>(null);

  const keyword = createMemo(() => options.keyword?.().trim().toLowerCase() ?? '');

  const filtered = createMemo(() => {
    const kw = keyword();
    const predicate = options.filter;
    return rows().filter((row) => {
      if (kw && options.match && !options.match(row, kw)) return false;
      if (predicate && !predicate(row)) return false;
      return true;
    });
  });

  const total = createMemo(() => filtered().length);
  const totalPages = createMemo(() => Math.max(1, Math.ceil(total() / pageSize())));
  const items = createMemo(() => {
    const current = Math.min(page(), totalPages());
    const start = (current - 1) * pageSize();
    return filtered().slice(start, start + pageSize());
  });

  const reload = async () => {
    if (options.enabled && !options.enabled()) {
      setRows([]);
      setError(null);
      return;
    }
    setLoading(true);
    setError(null);
    try {
      setRows((await loader()) ?? []);
    } catch (err) {
      setRows([]);
      setError(toApiError(err).message);
    } finally {
      setLoading(false);
    }
  };

  const changePageSize = (size: number) => {
    setPageSize(size);
    setPage(1);
  };

  createEffect(() => {
    if (options.resetKey) options.resetKey();
    else keyword();
    setPage(1);
  });

  if (options.watch) {
    createEffect(() => {
      options.watch!();
      void reload();
    });
  } else {
    onMount(() => void reload());
  }

  return {
    items,
    total,
    page,
    pageSize,
    totalPages,
    loading,
    error,
    reload,
    refresh: reload,
    setPage,
    setPageSize: changePageSize,
  };
}
