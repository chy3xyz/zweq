import { createSignal, onMount } from 'solid-js';

import { listAccounts, type AccountItem } from '#ui/api';

/** Loads site accounts and exposes a selected account id (first by default). */
export function useAccounts() {
  const [accounts, setAccounts] = createSignal<AccountItem[]>([]);
  const [loading, setLoading] = createSignal(true);
  const [selected, setSelected] = createSignal<number | null>(null);

  const reload = async () => {
    try {
      const res = await listAccounts(1, 100);
      setAccounts(res.list);
      setSelected((cur) => cur ?? (res.list.length > 0 ? res.list[0].id : null));
    } catch {
      // keep previous state on transient errors
    } finally {
      setLoading(false);
    }
  };

  onMount(() => void reload());

  return { accounts, selected, setSelected, loading };
}
