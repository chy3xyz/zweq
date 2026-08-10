import { For, Show, createSignal } from 'solid-js';

import {
  createAccount,
  deleteAccount,
  getWechatConfig,
  listAccounts,
  setWechatConfig,
  toApiError,
  updateAccount,
  type AccountItem,
  type AccountKind,
} from '#ui/api';
import DataTable, { type Column } from '#ui/components/DataTable';
import { usePaged } from '#ui/hooks/usePaged';
import { formatDateTime } from '#ui/utils';

const PAGE_SIZE = 20;
const KIND_LABEL: Record<AccountKind, string> = { wechat: '公众号', wxapp: '小程序', app: 'APP' };

function Accounts() {
  const [creating, setCreating] = createSignal(false);
  const [success, setSuccess] = createSignal<string | null>(null);
  const [nameInput, setNameInput] = createSignal('');
  const [kindInput, setKindInput] = createSignal<AccountKind>('wechat');

  // WeChat config editor (inline panel)
  const [editing, setEditing] = createSignal<AccountItem | null>(null);
  const [wechatAppid, setWechatAppid] = createSignal('');
  const [wechatToken, setWechatToken] = createSignal('');
  const [wechatSecret, setWechatSecret] = createSignal('');
  const [savingWechat, setSavingWechat] = createSignal(false);

  const paged = usePaged<AccountItem>((page, pageSize) => listAccounts(page, pageSize), PAGE_SIZE);

  const onCreate = async (e: SubmitEvent) => {
    e.preventDefault();
    if (creating()) return;
    setCreating(true);
    setSuccess(null);
    try {
      await createAccount({ name: nameInput().trim(), kind: kindInput() });
      setNameInput('');
      setSuccess('账号已创建');
      void paged.reload(1);
    } catch (err) {
      window.alert(toApiError(err).message);
    } finally {
      setCreating(false);
    }
  };

  const openWechat = async (account: AccountItem) => {
    setEditing(account);
    setWechatAppid('');
    setWechatToken('');
    setWechatSecret('');
    try {
      const cfg = await getWechatConfig(account.id);
      if (cfg) {
        setWechatAppid(cfg.appid);
        setWechatToken(cfg.token);
      }
    } catch {
      // ignore — leave fields empty
    }
  };

  const onSaveWechat = async (e: SubmitEvent) => {
    e.preventDefault();
    const account = editing();
    if (!account || savingWechat()) return;
    setSavingWechat(true);
    try {
      await setWechatConfig(account.id, {
        appid: wechatAppid().trim(),
        token: wechatToken().trim(),
        secret: wechatSecret().trim() || undefined,
      });
      setSuccess(`账号「${account.name}」微信配置已保存`);
      setEditing(null);
    } catch (err) {
      window.alert(toApiError(err).message);
    } finally {
      setSavingWechat(false);
    }
  };

  const onToggle = async (account: AccountItem) => {
    if (!window.confirm(`确定${account.status === 'active' ? '停用' : '启用'}账号「${account.name}」吗？`)) return;
    try {
      await updateAccount(account.id, { status: account.status === 'active' ? 'disabled' : 'active' });
      setSuccess(`账号「${account.name}」已${account.status === 'active' ? '停用' : '启用'}`);
      void paged.reload();
    } catch (err) {
      window.alert(toApiError(err).message);
    }
  };

  const onDelete = async (account: AccountItem) => {
    if (!window.confirm(`确定删除账号「${account.name}」吗？该操作不可恢复。`)) return;
    try {
      await deleteAccount(account.id);
      setSuccess(`账号「${account.name}」已删除`);
      void paged.reload();
    } catch (err) {
      window.alert(toApiError(err).message);
    }
  };

  const columns: Column<AccountItem>[] = [
    { key: 'id', title: 'ID', render: (a) => <span class="font-mono text-xs">{a.id}</span> },
    { key: 'name', title: '名称', render: (a) => <span class="font-medium">{a.name}</span> },
    {
      key: 'kind',
      title: '类型',
      render: (a) => <span class="badge badge-sm badge-ghost">{KIND_LABEL[a.kind]}</span>,
    },
    {
      key: 'status',
      title: '状态',
      render: (a) => (
        <span class={`badge badge-sm ${a.status === 'active' ? 'badge-success' : 'badge-outline'}`}>
          {a.status === 'active' ? '启用' : '停用'}
        </span>
      ),
    },
    {
      key: 'created_at',
      title: '创建时间',
      render: (a) => <span class="text-sm text-base-content/70">{formatDateTime(a.created_at)}</span>,
    },
  ];

  return (
    <div class="space-y-4">
      <div>
        <h2 class="text-xl font-semibold">账号管理</h2>
        <p class="text-sm text-base-content/60">平台账号（公众号 / 小程序 / APP）与微信服务器配置</p>
      </div>

      <form onSubmit={onCreate} class="flex items-end gap-2">
        <label class="form-control w-full max-w-xs">
          <span class="label-text mb-1">账号名称</span>
          <input
            type="text"
            class="input input-bordered input-sm"
            placeholder="例如：我的公众号"
            value={nameInput()}
            onInput={(e) => setNameInput(e.currentTarget.value)}
            required
          />
        </label>
        <label class="form-control">
          <span class="label-text mb-1">类型</span>
          <select
            class="select select-bordered select-sm"
            value={kindInput()}
            onChange={(e) => setKindInput(e.currentTarget.value as AccountKind)}
          >
            <option value="wechat">公众号</option>
            <option value="wxapp">小程序</option>
            <option value="app">APP</option>
          </select>
        </label>
        <button type="submit" class="btn btn-primary btn-sm" disabled={creating()}>
          {creating() ? '创建中…' : '创建账号'}
        </button>
      </form>

      <Show when={success()}>
        <div role="alert" class="alert alert-success py-2 text-sm">
          {success()}
        </div>
      </Show>

      <Show when={editing()}>
        {(account) => (
          <form onSubmit={onSaveWechat} class="rounded-lg border border-base-300 bg-base-200/40 p-4 space-y-3">
            <div class="flex items-center justify-between">
              <span class="text-sm font-semibold">
                微信配置 — {account().name}（<span class="font-mono">{account().id}</span>）
              </span>
              <button type="button" class="btn btn-ghost btn-xs" onClick={() => setEditing(null)}>
                关闭
              </button>
            </div>
            <div class="grid grid-cols-1 gap-3 md:grid-cols-2">
              <label class="form-control">
                <span class="label-text mb-1">AppID</span>
                <input
                  type="text"
                  class="input input-bordered input-sm"
                  value={wechatAppid()}
                  onInput={(e) => setWechatAppid(e.currentTarget.value)}
                  required
                />
              </label>
              <label class="form-control">
                <span class="label-text mb-1">Token</span>
                <input
                  type="text"
                  class="input input-bordered input-sm"
                  value={wechatToken()}
                  onInput={(e) => setWechatToken(e.currentTarget.value)}
                  required
                />
              </label>
              <label class="form-control">
                <span class="label-text mb-1">AppSecret（留空保持不变）</span>
                <input
                  type="password"
                  class="input input-bordered input-sm"
                  value={wechatSecret()}
                  onInput={(e) => setWechatSecret(e.currentTarget.value)}
                />
              </label>
            </div>
            <button type="submit" class="btn btn-primary btn-sm" disabled={savingWechat()}>
              {savingWechat() ? '保存中…' : '保存微信配置'}
            </button>
          </form>
        )}
      </Show>

      <DataTable
        columns={columns}
        rows={paged.items()}
        rowKey={(a) => a.id}
        total={paged.total()}
        page={paged.page()}
        totalPages={paged.totalPages()}
        loading={paged.loading()}
        error={paged.error()}
        emptyText="暂无账号"
        onPageChange={(p) => void paged.reload(p)}
        actions={(account) => (
          <div class="flex gap-1">
            <button type="button" class="btn btn-ghost btn-xs" onClick={() => void openWechat(account)}>
              微信配置
            </button>
            <button
              type="button"
              class={`btn btn-ghost btn-xs ${account.status === 'active' ? 'text-error' : ''}`}
              onClick={() => onToggle(account)}
            >
              {account.status === 'active' ? '停用' : '启用'}
            </button>
            <button type="button" class="btn btn-ghost btn-xs text-error" onClick={() => onDelete(account)}>
              删除
            </button>
          </div>
        )}
      />
    </div>
  );
}

export default Accounts;
