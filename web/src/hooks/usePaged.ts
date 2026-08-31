import { createEffect, createMemo, createSignal, onMount } from 'solid-js';

import { toApiError } from '#ui/api';

export interface PagedPayload<T> {
  list: T[];
  total: number;
  page: number;
}

/**
 * Data-driven pagination state (zmsaas-style convergence): one hook owns
 * items/total/page/loading/error plus a monotonic request guard so rapid
 * search or pagination cannot interleave out-of-order responses.
 *
 * `watch` is the standard way to react to filter/account changes — the list
 * reloads from page 1 whenever a tracked value changes, so pages do not need
 * to call `reload(1)` by hand after a search.
 */
export function usePaged<T>(
  loader: (page: number, pageSize: number) => Promise<PagedPayload<T>>,
  initialPageSize = 20,
  /** Re-fetch page 1 when this accessor changes (e.g. filters or account id). */
  watch?: () => unknown,
) {
  const [items, setItems] = createSignal<T[]>([]);
  const [total, setTotal] = createSignal(0);
  const [page, setPage] = createSignal(1);
  const [pageSize, setPageSize] = createSignal(initialPageSize);
  const [loading, setLoading] = createSignal(false);
  const [error, setError] = createSignal<string | null>(null);

  const totalPages = createMemo(() => Math.max(1, Math.ceil(total() / pageSize())));
  let requestSeq = 0;

  const reload = async (targetPage = page()) => {
    const seq = ++requestSeq;
    setLoading(true);
    setError(null);
    try {
      const result = await loader(targetPage, pageSize());
      if (seq !== requestSeq) return;
      setItems(result.list);
      setTotal(result.total);
      setPage(result.page);
    } catch (err) {
      if (seq !== requestSeq) return;
      setError(toApiError(err).message);
    } finally {
      if (seq === requestSeq) setLoading(false);
    }
  };

  /** Re-fetch the current page (used after create/update/delete). */
  const refresh = () => reload(page());

  /** Change page size and restart from page 1. */
  const changePageSize = (size: number) => {
    setPageSize(size);
    void reload(1);
  };

  if (watch) {
    createEffect(() => {
      watch();
      void reload(1);
    });
  } else {
    onMount(() => void reload(1));
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
    refresh,
    setPage,
    setPageSize: changePageSize,
  };
}
