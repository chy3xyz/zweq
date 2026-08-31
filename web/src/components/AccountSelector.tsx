import { For, Show } from 'solid-js';

import { useAccount } from '#ui/hooks/useAccount';

const KIND_LABEL: Record<string, string> = { wechat: '公众号', wxapp: '小程序', app: 'APP' };

function AccountSelector() {
  const [state, actions] = useAccount();

  return (
    <div class="flex items-center gap-2">
      <span class="text-xs text-base-content/50">当前公众号</span>
      <select
        class="select select-bordered select-sm min-w-44"
        value={state.selectedId ?? ''}
        disabled={state.loading || state.accounts.length === 0}
        onChange={(e) => actions.setSelectedId(Number(e.currentTarget.value))}
      >
        <Show when={state.accounts.length === 0}>
          <option value="">暂无账号</option>
        </Show>
        <For each={state.accounts}>
          {(a) => (
            <option value={a.id}>
              {a.name}（{KIND_LABEL[a.kind] ?? a.kind}）
            </option>
          )}
        </For>
      </select>
    </div>
  );
}

export default AccountSelector;
