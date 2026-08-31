import { createContext } from 'solid-js';

import type { AccountItem } from '#ui/api';

export type AccountState = {
  accounts: AccountItem[];
  selectedId: number | null;
  loading: boolean;
};

export type AccountActions = {
  setSelectedId: (id: number) => void;
  reload: () => Promise<void>;
};

export type AccountContextValue = [AccountState, AccountActions];

export const AccountContext = createContext<AccountContextValue>();
