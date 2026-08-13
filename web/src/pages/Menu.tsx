import { For, Show, createSignal } from 'solid-js';

import { deleteRemoteMenu, fetchMenu, getMenu, publishMenu, saveMenu } from '#ui/api';
import { useAccounts } from '#ui/hooks/useAccounts';

function Menu() {
  const accounts = useAccounts();
  const accountId = () => accounts.selected() ?? 0;
  const [menuJson, setMenuJson] = createSignal('[]');
  const [success, setSuccess] = createSignal<string | null>(null);
  const [error, setError] = createSignal<string | null>(null);
  const [busy, setBusy] = createSignal(false);

  const load = async (id: number) => {
    if (id === 0) return;
    setSuccess(null);
    setError(null);
    try {
      const m = await getMenu(id);
      setMenuJson(m.menu_json || '[]');
    } catch {
      setMenuJson('[]');
    }
  };

  const onAccountChange = (id: number) => {
    accounts.setSelected(id);
    void load(id);
  };

  const onSave = async () => {
    if (accountId() === 0) return;
    setBusy(true);
    try {
      const buttons = JSON.parse(menuJson());
      await saveMenu(accountId(), { buttons });
      setSuccess('菜单已保存');
    } catch {
      setError('菜单 JSON 格式错误');
    }
    setBusy(false);
  };

  const onPublish = async () => {
    if (accountId() === 0) return;
    setBusy(true);
    try {
      await publishMenu(accountId());
      setSuccess('菜单已发布到微信');
    } catch (err) {
      setError(String(err));
    }
    setBusy(false);
  };

  const onFetch = async () => {
    if (accountId() === 0) return;
    try {
      const m = await fetchMenu(accountId());
      setMenuJson(m.menu_json || '[]');
      setSuccess('已从微信拉取');
    } catch (err) {
      setError(String(err));
    }
  };

  const onDelete = async () => {
    if (accountId() === 0) return;
    try {
      await deleteRemoteMenu(accountId());
      setSuccess('已删除微信菜单');
    } catch (err) {
      setError(String(err));
    }
  };

  return (
    <div class="p-6 space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">公众号菜单</h1>
        <select
          class="select select-bordered"
          onChange={(e) => onAccountChange(Number(e.currentTarget.value))}
        >
          <option value={0}>选择公众号</option>
          <For each={accounts.accounts()}>
            {(a) => <option value={a.id}>{a.name}</option>}
          </For>
        </select>
      </div>

      <Show when={success()}>
        <div class="alert alert-success">{success()}</div>
      </Show>
      <Show when={error()}>
        <div class="alert alert-error">{error()}</div>
      </Show>

      <div class="card bg-base-200 p-4 space-y-3">
        <h2 class="font-semibold">菜单 JSON（buttons 数组）</h2>
        <textarea
          class="textarea textarea-bordered font-mono h-64"
          value={menuJson()}
          onInput={(e) => setMenuJson(e.currentTarget.value)}
        />
        <div class="flex gap-2">
          <button class="btn btn-primary" disabled={busy()} onClick={() => void onSave()}>
            保存
          </button>
          <button class="btn btn-secondary" disabled={busy()} onClick={() => void onPublish()}>
            发布到微信
          </button>
          <button class="btn btn-outline" disabled={busy()} onClick={() => void onFetch()}>
            从微信拉取
          </button>
          <button class="btn btn-outline btn-error" disabled={busy()} onClick={() => void onDelete()}>
            删除微信菜单
          </button>
        </div>
      </div>
    </div>
  );
}

export default Menu;
