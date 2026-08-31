import { useAccount } from '#ui/hooks/useAccount';

/**
 * Reads the global top-bar account context (legacy name kept for existing pages).
 * Do not render per-page account selectors — use the header switcher.
 */
export function useAccounts() {
  const [state, actions] = useAccount();
  return {
    accounts: () => state.accounts,
    selected: () => state.selectedId,
    setSelected: actions.setSelectedId,
    loading: () => state.loading,
  };
}
