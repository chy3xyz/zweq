import { useContext } from 'solid-js';

import { AccountContext } from '#ui/context/AccountContext';

export function useAccount() {
  const ctx = useContext(AccountContext);
  if (!ctx) throw new Error('useAccount must be used within AccountProvider');
  return ctx;
}
