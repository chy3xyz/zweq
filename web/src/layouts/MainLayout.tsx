import { type JSX } from 'solid-js';

import AccountSelector from '#ui/components/AccountSelector';
import AdminSidebar from '#ui/components/AdminSidebar';
import UserMenu from '#ui/components/UserMenu';
import NotificationBell from '#ui/layouts/NotificationBell';

function MainLayout(props: { children?: JSX.Element }) {
  return (
    <div class="flex h-screen overflow-hidden bg-base-100">
      <aside class="flex w-60 shrink-0 flex-col border-r border-base-300 bg-base-200">
        <div class="flex h-16 items-center gap-2 border-b border-base-300 px-4">
          <span class="text-lg font-bold">Zweq</span>
          <span class="badge badge-xs badge-ghost">管理后台</span>
        </div>
        <AdminSidebar />
      </aside>

      <div class="flex flex-1 flex-col overflow-hidden">
        <header class="flex h-16 items-center justify-between gap-4 border-b border-base-300 px-6">
          <h1 class="text-base font-semibold text-base-content/80">控制台</h1>
          <div class="flex items-center gap-4">
            <AccountSelector />
            <NotificationBell />
            <UserMenu />
          </div>
        </header>
        <main class="flex-1 overflow-y-auto bg-base-100/50 p-6">{props.children}</main>
      </div>
    </div>
  );
}

export default MainLayout;
