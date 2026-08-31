import { A } from '@solidjs/router';
import { For, Show } from 'solid-js';

import { useAdminNav } from '#ui/hooks/useAdminNav';

function AdminSidebar() {
  const { groups, loading } = useAdminNav();

  return (
    <nav class="flex-1 space-y-3 overflow-y-auto p-3">
      <Show when={loading()} fallback={null}>
        <p class="px-2 text-xs text-base-content/50">菜单加载中…</p>
      </Show>
      <For each={groups()}>
        {(group) => (
          <div>
            <p class="mb-1 px-2 text-xs font-semibold uppercase tracking-wide text-base-content/45">{group.name}</p>
            <For each={group.subgroups}>
              {(sub) => (
                <div class="mb-2">
                  <Show when={sub.name.length > 0}>
                    <p class="mb-0.5 px-2 text-[11px] text-base-content/40">{sub.name}</p>
                  </Show>
                  <For each={sub.items}>
                    {(item) => (
                      <A
                        href={item.href}
                        class="block rounded-lg px-3 py-1.5 text-sm hover:bg-base-300 [&.active]:bg-primary [&.active]:text-primary-content"
                        activeClass="active"
                      >
                        {item.label}
                      </A>
                    )}
                  </For>
                </div>
              )}
            </For>
          </div>
        )}
      </For>
    </nav>
  );
}

export default AdminSidebar;
