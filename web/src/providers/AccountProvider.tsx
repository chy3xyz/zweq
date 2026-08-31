import { type JSX, createEffect, onMount } from 'solid-js';
import { createStore } from 'solid-js/store';

import { listAccounts } from '#ui/api';
import { APP_CONFIG } from '#ui/config';
import { AccountContext, type AccountActions, type AccountContextValue, type AccountState } from '#ui/context/AccountContext';
import { useAuth } from '#ui/hooks/useAuth';

function readStoredAccountId(): number | null {
  try {
    const raw = localStorage.getItem(APP_CONFIG.storage.accountId);
    if (!raw) return null;
    const id = Number(raw);
    return Number.isFinite(id) && id > 0 ? id : null;
  } catch {
    return null;
  }
}

function persistAccountId(id: number | null) {
  if (id == null) {
    localStorage.removeItem(APP_CONFIG.storage.accountId);
    return;
  }
  localStorage.setItem(APP_CONFIG.storage.accountId, String(id));
}

export function AccountProvider(props: JSX.HTMLAttributes<HTMLElement>) {
  const [auth] = useAuth();
  const [store, setStore] = createStore<AccountState>({
    accounts: [],
    selectedId: readStoredAccountId(),
    loading: true,
  });

  const reload = async () => {
    setStore('loading', true);
    try {
      const res = await listAccounts(1, 100);
      setStore('accounts', res.list);
      const stored = store.selectedId;
      const valid = stored != null && res.list.some((a) => a.id === stored);
      const next = valid ? stored : res.list[0]?.id ?? null;
      setStore('selectedId', next);
      persistAccountId(next);
    } catch {
      // keep previous
    } finally {
      setStore('loading', false);
    }
  };

  onMount(() => {
    if (auth.status === 'verified') void reload();
  });

  createEffect(() => {
    if (auth.status === 'verified') void reload();
  });

  createEffect(() => {
    persistAccountId(store.selectedId);
  });

  const actions: AccountActions = {
    setSelectedId(id) {
      setStore('selectedId', id);
    },
    reload,
  };

  const value: AccountContextValue = [store, actions];

  return <AccountContext.Provider value={value}>{props.children}</AccountContext.Provider>;
}
