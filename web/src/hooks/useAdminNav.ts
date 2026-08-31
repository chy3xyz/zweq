import { createMemo, createResource } from 'solid-js';

import { getAdminNav } from '#ui/api/module/query';
import type { AdminNavItem } from '#ui/api/module/types';
import { useAccount } from '#ui/hooks/useAccount';

export type NavGroup = {
  name: string;
  subgroups: {
    name: string;
    items: AdminNavItem[];
  }[];
};

function groupNavItems(items: AdminNavItem[]): NavGroup[] {
  const groups = new Map<string, Map<string, AdminNavItem[]>>();

  for (const item of items) {
    if (!groups.has(item.group)) groups.set(item.group, new Map());
    const subs = groups.get(item.group)!;
    if (!subs.has(item.subgroup)) subs.set(item.subgroup, []);
    subs.get(item.subgroup)!.push(item);
  }

  return [...groups.entries()].map(([name, subs]) => ({
    name,
    subgroups: [...subs.entries()].map(([subName, subItems]) => ({
      name: subName,
      items: subItems.sort((a: AdminNavItem, b: AdminNavItem) => a.order - b.order),
    })),
  }));
}

export function useAdminNav() {
  const [accountState] = useAccount();
  const accountId = createMemo(() => accountState.selectedId);

  const [nav] = createResource(accountId, (id) => getAdminNav(id));

  const groups = createMemo(() =>
    groupNavItems((nav() ?? []).slice().sort((a: AdminNavItem, b: AdminNavItem) => a.order - b.order)),
  );

  return { nav, groups, loading: () => nav.loading, error: () => nav.error };
}
