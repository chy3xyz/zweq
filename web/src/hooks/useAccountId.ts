import { createEffect } from 'solid-js';

import { useAccount } from '#ui/hooks/useAccount';

/** Global official-account id from the top-bar selector. */
export function useAccountId() {
  const [state] = useAccount();

  const accountId = () => state.selectedId ?? 0;
  const ready = () => accountId() > 0;
  const accountName = () => state.accounts.find((a) => a.id === state.selectedId)?.name ?? '';

  const onAccountChange = (fn: () => void) => {
    createEffect(() => {
      const id = state.selectedId;
      if (id) fn();
    });
  };

  return { accountId, ready, accountName, onAccountChange, accounts: () => state.accounts };
}
