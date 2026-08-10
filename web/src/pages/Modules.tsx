import { For, Show, createSignal } from 'solid-js';

import {
  bindModule,
  listAccountModules,
  listModules,
  registerModule,
  toApiError,
  unbindModule,
  type BindingItem,
  type ModuleItem,
} from '#ui/api';
import DataTable, { type Column } from '#ui/components/DataTable';
import { useAccounts } from '#ui/hooks/useAccounts';
import { usePaged } from '#ui/hooks/usePaged';
import { formatDateTime } from '#ui/utils';

const PAGE_SIZE = 20;

function Modules() {
  const accounts = useAccounts();
  const [success, setSuccess] = createSignal<string | null>(null);
  const [name, setName] = createSignal('');
  const [title, setTitle] = createSignal('');
  const [version, setVersion] = createSignal('1.0.0');
  const [bindings, setBindings] = createSignal<BindingItem[]>([]);
  const [moduleInput, setModuleInput] = createSignal('');

  const paged = usePaged<ModuleItem>((page, pageSize) => listModules(page, pageSize), PAGE_SIZE);
  const accountId = () => accounts.selected() ?? 0;

  const reloadBindings = async (id: number) => {
    if (id === 0) return;
    try {
      setBindings(await listAccountModules(id));
    } catch {
      setBindings([]);
    }
  };

  const onAccountChange = (id: number) => {
    accounts.setSelected(id);
    void reloadBindings(id);
  };

  const onRegister = async (e: SubmitEvent) => {
    e.preventDefault();
    setSuccess(null);
    try {
      await registerModule({ name: name().trim(), title: title().trim(), version: version().trim() });
      setName('');
      setTitle('');
      setSuccess('模块已注册');
      void paged.reload(1);
    } catch (err) {
      window.alert(toApiError(err).message);
    }
  };

  const onBind = async () => {
    const mod = moduleInput().trim();
    if (!mod || accountId() === 0) return;
    try {
      await bindModule(accountId(), { module: mod });
      setModuleInput('');
      setSuccess(`模块 ${mod} 已绑定`);
      await reloadBindings(accountId());
      void paged.reload();
    } catch (err) {
      window.alert(toApiError(err).message);
    }
  };

  const onUnbind = async (b: BindingItem) => {
    if (!window.confirm(`确定解绑模块「${b.module}」吗？`)) return;
    try {
      await unbindModule(accountId(), b.module);
      await reloadBindings(accountId());
    } catch (err) {
      window.alert(toApiError(err).message);
    }
  };

  const columns: Column<ModuleItem>[] = [
    { key: 'name', title: '模块', render: (m) => <span class="font-mono text-sm">{m.name}</span> },
    { key: 'title', title: '名称', render: (m) => <span class="font-medium">{m.title}</span> },
    { key: 'version', title: '版本', render: (m) => <span class="badge badge-sm badge-ghost">{m.version}</span> },
    { key: 'status', title: '状态', render: (m) => <span class={`badge badge-sm ${m.status === 'active' ? 'badge-success' : 'badge-outline'}`}>{m.status === 'active' ? '启用' : '停用'}</span> },
    { key: 'updated_at', title: '更新时间', render: (m) => <span class="text-sm text-base-content/70">{formatDateTime(m.updated_at)}</span> },
  ];

  return (
    <div class="space-y-4">
      <div>
        <h2 class="text-xl font-semibold">模块管理</h2>
        <p class="text-sm text-base-content/60">内置模块注册表 + 账号绑定（微擎 addon 安装的 Zig 等价物）</p>
      </div>

      <form onSubmit={onRegister} class="flex items-end gap-2">
        <label class="form-control">
          <span class="label-text mb-1">模块名</span>
          <input type="text" class="input input-bordered input-sm w-32" placeholder="shop" value={name()} onInput={(e) => setName(e.currentTarget.value)} required />
        </label>
        <label class="form-control">
          <span class="label-text mb-1">名称</span>
          <input type="text" class="input input-bordered input-sm w-32" placeholder="商城" value={title()} onInput={(e) => setTitle(e.currentTarget.value)} required />
        </label>
        <label class="form-control">
          <span class="label-text mb-1">版本</span>
          <input type="text" class="input input-bordered input-sm w-24" value={version()} onInput={(e) => setVersion(e.currentTarget.value)} />
        </label>
        <button type="submit" class="btn btn-primary btn-sm">注册模块</button>
      </form>

      <Show when={success()}>
        <div role="alert" class="alert alert-success py-2 text-sm">
          {success()}
        </div>
      </Show>

      <div class="grid grid-cols-1 gap-4 lg:grid-cols-3">
        <div class="lg:col-span-2">
          <DataTable
            columns={columns}
            rows={paged.items()}
            rowKey={(m) => m.id}
            total={paged.total()}
            page={paged.page()}
            totalPages={paged.totalPages()}
            loading={paged.loading()}
            error={paged.error()}
            emptyText="暂无模块"
            onPageChange={(p) => void paged.reload(p)}
          />
        </div>

        <div class="rounded-lg border border-base-300 bg-base-200/40 p-4 space-y-3">
          <div>
            <span class="text-sm font-semibold">账号模块绑定</span>
            <select class="select select-bordered select-sm mt-2 w-full" value={accountId()} onChange={(e) => onAccountChange(Number(e.currentTarget.value))}>
              <For each={accounts.accounts()}>
                {(a) => (
                  <option value={a.id}>
                    {a.name}（{a.id}）
                  </option>
                )}
              </For>
            </select>
          </div>
          <div class="flex items-end gap-2">
            <input type="text" class="input input-bordered input-sm flex-1" placeholder="模块名" value={moduleInput()} onInput={(e) => setModuleInput(e.currentTarget.value)} />
            <button type="button" class="btn btn-primary btn-sm" onClick={onBind}>
              绑定
            </button>
          </div>
          <div class="space-y-1">
            <For each={bindings()}>
              {(b) => (
                <div class="flex items-center justify-between rounded bg-base-100 px-2 py-1 text-sm">
                  <span class="font-mono">{b.module}</span>
                  <button type="button" class="btn btn-ghost btn-xs text-error" onClick={() => onUnbind(b)}>
                    解绑
                  </button>
                </div>
              )}
            </For>
            <Show when={bindings().length === 0}>
              <p class="text-xs text-base-content/50">该账号未绑定模块</p>
            </Show>
          </div>
        </div>
      </div>
    </div>
  );
}

export default Modules;
