import { useNavigate } from '@solidjs/router';
import { For, Show, createSignal } from 'solid-js';

import ChangePasswordModal from '#ui/components/ChangePasswordModal';
import { ROUTE_PATH } from '#ui/constants';
import { useAuth } from '#ui/hooks';
import { useAccount } from '#ui/hooks/useAccount';

function UserMenu() {
  const navigate = useNavigate();
  const [auth, actions] = useAuth();
  const [accountState, accountActions] = useAccount();
  const [open, setOpen] = createSignal(false);
  const [pwOpen, setPwOpen] = createSignal(false);
  const [switchOpen, setSwitchOpen] = createSignal(false);

  const closeAll = () => {
    setOpen(false);
    setSwitchOpen(false);
  };

  return (
    <div class="relative">
      <button
        type="button"
        class="btn btn-ghost btn-sm gap-2"
        onClick={() => setOpen(!open())}
        aria-haspopup="menu"
      >
        <span class="flex h-7 w-7 items-center justify-center rounded-full bg-primary/15 text-xs font-semibold text-primary">
          {(auth.user?.name ?? '?').slice(0, 1)}
        </span>
        <span class="max-w-28 truncate">{auth.user?.name ?? '-'}</span>
        <span class="text-xs opacity-50">▾</span>
      </button>

      <Show when={open()}>
        <div class="absolute right-0 z-50 mt-2 w-52 rounded-lg border border-base-300 bg-base-100 py-1 shadow-xl">
          <div class="border-b border-base-200 px-3 py-2 text-xs text-base-content/60">
            {auth.user?.email}
          </div>
          <button
            type="button"
            class="flex w-full px-3 py-2 text-left text-sm hover:bg-base-200"
            onClick={() => {
              closeAll();
              navigate(ROUTE_PATH.profile);
            }}
          >
            个人信息
          </button>
          <button
            type="button"
            class="flex w-full px-3 py-2 text-left text-sm hover:bg-base-200"
            onClick={() => setSwitchOpen(!switchOpen())}
          >
            切换公众号
          </button>
          <Show when={switchOpen()}>
            <div class="border-y border-base-200 bg-base-200/40 px-3 py-2">
              <select
                class="select select-bordered select-xs w-full"
                value={accountState.selectedId ?? ''}
                onChange={(e) => accountActions.setSelectedId(Number(e.currentTarget.value))}
              >
                <For each={accountState.accounts}>
                  {(a) => <option value={a.id}>{a.name}</option>}
                </For>
              </select>
            </div>
          </Show>
          <button
            type="button"
            class="flex w-full px-3 py-2 text-left text-sm hover:bg-base-200"
            onClick={() => {
              closeAll();
              setPwOpen(true);
            }}
          >
            修改密码
          </button>
          <button
            type="button"
            class="flex w-full px-3 py-2 text-left text-sm text-error hover:bg-base-200"
            onClick={() => {
              closeAll();
              void actions.logout();
            }}
          >
            退出登录
          </button>
        </div>
      </Show>

      <ChangePasswordModal open={pwOpen()} onClose={() => setPwOpen(false)} />
    </div>
  );
}

export default UserMenu;
