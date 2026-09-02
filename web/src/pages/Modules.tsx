import { For, Show, createEffect, createSignal } from 'solid-js';

import {
  bindModule,
  getModuleConfig,
  listAccountModules,
  listModules,
  registerModule,
  toApiError,
  unbindModule,
  updateModule,
  updateModuleConfig,
  type BindingItem,
  type ModuleItem,
  type UpdateModuleRequest,
} from '#ui/api';
import AccountRequiredBanner from '#ui/components/AccountRequiredBanner';
import AdminCrudPage from '#ui/components/AdminCrudPage';
import DataTable, { type Column } from '#ui/components/DataTable';
import FormField from '#ui/components/FormField';
import FormModal from '#ui/components/FormModal';
import SearchBar, { type SearchField, type SearchValues } from '#ui/components/SearchBar';
import Tabs from '#ui/components/Tabs';
import { useAccountId, useFeedback, usePaged } from '#ui/hooks';
import { formatDateTime } from '#ui/utils';

const TABS = ['模块列表', '账号绑定', '模块配置'] as const;
type Tab = (typeof TABS)[number];

const PAGE_SIZE = 20;

const MODULE_STATUS_OPTIONS = [
  { value: '', label: '全部' },
  { value: 'active', label: '启用' },
  { value: 'disabled', label: '停用' },
];

const SEARCH_FIELDS: SearchField[] = [
  { kind: 'text', key: 'keyword', label: '模块名/名称', placeholder: '输入关键字' },
  { kind: 'select', key: 'status', label: '状态', options: MODULE_STATUS_OPTIONS },
];

interface ModuleFormState {
  name: string;
  title: string;
  version: string;
  status: 'active' | 'disabled';
}

interface BindFormState {
  module: string;
  status: 'active' | 'disabled';
}

function Modules() {
  const feedback = useFeedback();
  const { accountId, onAccountChange } = useAccountId();
  const [tab, setTab] = createSignal<Tab>('模块列表');
  const [filters, setFilters] = createSignal<SearchValues>({});

  const paged = usePaged<ModuleItem>(
    (page, pageSize) => listModules(page, pageSize, filters().keyword?.trim()),
    PAGE_SIZE,
    () => filters(),
  );

  const [bindings, setBindings] = createSignal<BindingItem[]>([]);
  const [bindingsLoading, setBindingsLoading] = createSignal(false);

  const reloadBindings = async () => {
    const id = accountId();
    if (id === 0) {
      setBindings([]);
      return;
    }
    setBindingsLoading(true);
    try {
      setBindings(await listAccountModules(id));
    } catch (err) {
      feedback.toast(toApiError(err).message, 'error');
      setBindings([]);
    } finally {
      setBindingsLoading(false);
    }
  };

  onAccountChange(() => {
    void reloadBindings();
  });

  createEffect(() => {
    const t = tab();
    if (t === '账号绑定' || t === '模块配置') {
      void reloadBindings();
    }
  });

  // Module create/edit modal
  const [moduleModalOpen, setModuleModalOpen] = createSignal(false);
  const [editingModule, setEditingModule] = createSignal<ModuleItem | null>(null);
  const [moduleForm, setModuleForm] = createSignal<ModuleFormState>({
    name: '',
    title: '',
    version: '1.0.0',
    status: 'active',
  });
  const [moduleSubmitting, setModuleSubmitting] = createSignal(false);
  const [moduleError, setModuleError] = createSignal<string | null>(null);

  const openCreateModule = () => {
    setEditingModule(null);
    setModuleForm({ name: '', title: '', version: '1.0.0', status: 'active' });
    setModuleError(null);
    setModuleModalOpen(true);
  };

  const openEditModule = (m: ModuleItem) => {
    setEditingModule(m);
    setModuleForm({ name: m.name, title: m.title, version: m.version, status: m.status });
    setModuleError(null);
    setModuleModalOpen(true);
  };

  const setModuleField = <K extends keyof ModuleFormState>(key: K, value: ModuleFormState[K]) => {
    setModuleForm((prev) => ({ ...prev, [key]: value }));
  };

  const onModuleSubmit = async (e: SubmitEvent) => {
    e.preventDefault();
    if (moduleSubmitting()) return;
    setModuleSubmitting(true);
    setModuleError(null);
    try {
      const editing = editingModule();
      if (editing) {
        const body: UpdateModuleRequest = {
          title: moduleForm().title.trim(),
          version: moduleForm().version.trim(),
          status: moduleForm().status,
        };
        await updateModule(editing.id, body);
      } else {
        await registerModule({
          name: moduleForm().name.trim(),
          title: moduleForm().title.trim(),
          version: moduleForm().version.trim(),
        });
      }
      setModuleModalOpen(false);
      feedback.toast(editing ? `模块「${moduleForm().name}」已更新` : '模块已创建', 'success');
      void paged.refresh();
    } catch (err) {
      const status = (err as { response?: { status?: number } }).response?.status;
      if (status === 404) {
        setModuleError('该模块已不存在，请刷新列表后重试');
      } else {
        setModuleError(toApiError(err).message);
      }
    } finally {
      setModuleSubmitting(false);
    }
  };

  // Bind modal
  const [bindModalOpen, setBindModalOpen] = createSignal(false);
  const [allModules, setAllModules] = createSignal<ModuleItem[]>([]);
  const [bindForm, setBindForm] = createSignal<BindFormState>({ module: '', status: 'active' });
  const [bindSubmitting, setBindSubmitting] = createSignal(false);
  const [bindError, setBindError] = createSignal<string | null>(null);

  const openBindModal = async () => {
    setBindForm({ module: '', status: 'active' });
    setBindError(null);
    setBindModalOpen(true);
    try {
      const res = await listModules(1, 100);
      setAllModules(res.list);
    } catch (err) {
      setBindError(toApiError(err).message);
    }
  };

  const setBindField = <K extends keyof BindFormState>(key: K, value: BindFormState[K]) => {
    setBindForm((prev) => ({ ...prev, [key]: value }));
  };

  const onBindSubmit = async (e: SubmitEvent) => {
    e.preventDefault();
    if (bindSubmitting() || accountId() === 0) return;
    setBindSubmitting(true);
    setBindError(null);
    try {
      await bindModule(accountId(), { module: bindForm().module, status: bindForm().status });
      setBindModalOpen(false);
      feedback.toast(`模块「${bindForm().module}」已绑定`, 'success');
      void reloadBindings();
      void paged.refresh();
    } catch (err) {
      setBindError(toApiError(err).message);
    } finally {
      setBindSubmitting(false);
    }
  };

  const onUnbind = (b: BindingItem) =>
    feedback.runAction({
      confirm: { title: '解绑模块', message: `确定解绑模块「${b.module}」吗？`, danger: true },
      action: () => unbindModule(accountId(), b.module),
      success: `模块「${b.module}」已解绑`,
      onDone: () => {
        void reloadBindings();
        void paged.refresh();
      },
    });

  // Config modal
  const [configModalOpen, setConfigModalOpen] = createSignal(false);
  const [configuringModule, setConfiguringModule] = createSignal<BindingItem | null>(null);
  const [configText, setConfigText] = createSignal('');
  const [configSubmitting, setConfigSubmitting] = createSignal(false);
  const [configError, setConfigError] = createSignal<string | null>(null);

  const openConfigModal = async (b: BindingItem) => {
    if (accountId() === 0) return;
    setConfiguringModule(b);
    setConfigText('');
    setConfigError(null);
    setConfigModalOpen(true);
    try {
      const res = await getModuleConfig(accountId(), b.module);
      setConfigText(res.config);
    } catch (err) {
      setConfigError(toApiError(err).message);
    }
  };

  const onConfigSubmit = async (e: SubmitEvent) => {
    e.preventDefault();
    if (configSubmitting() || accountId() === 0 || !configuringModule()) return;
    setConfigSubmitting(true);
    setConfigError(null);
    try {
      JSON.parse(configText());
      await updateModuleConfig(accountId(), configuringModule()!.module, { config: configText() });
      setConfigModalOpen(false);
      feedback.toast(`模块「${configuringModule()!.module}」配置已保存`, 'success');
    } catch (err) {
      setConfigError(err instanceof SyntaxError ? `JSON 格式错误：${err.message}` : toApiError(err).message);
    } finally {
      setConfigSubmitting(false);
    }
  };

  const moduleColumns: Column<ModuleItem>[] = [
    { key: 'name', title: '模块', render: (m) => <span class="font-mono text-sm">{m.name}</span> },
    { key: 'title', title: '名称', render: (m) => <span class="font-medium">{m.title}</span> },
    {
      key: 'version',
      title: '版本',
      render: (m) => <span class="badge badge-sm badge-ghost">{m.version}</span>,
    },
    {
      key: 'status',
      title: '状态',
      render: (m) => (
        <span class={`badge badge-sm ${m.status === 'active' ? 'badge-success' : 'badge-outline'}`}>
          {m.status === 'active' ? '启用' : '停用'}
        </span>
      ),
    },
    {
      key: 'updated_at',
      title: '更新时间',
      render: (m) => <span class="text-sm text-base-content/70">{formatDateTime(m.updated_at)}</span>,
    },
  ];

  const bindingColumns: Column<BindingItem>[] = [
    { key: 'module', title: '模块', render: (b) => <span class="font-mono text-sm">{b.module}</span> },
    {
      key: 'status',
      title: '状态',
      render: (b) => (
        <span class={`badge badge-sm ${b.status === 'active' ? 'badge-success' : 'badge-outline'}`}>
          {b.status === 'active' ? '启用' : '停用'}
        </span>
      ),
    },
  ];

  return (
    <div class="space-y-4">
      <div>
        <h2 class="text-xl font-semibold">模块管理</h2>
        <p class="text-sm text-base-content/60">内置模块注册表 + 账号绑定 + 模块配置</p>
      </div>

      <AccountRequiredBanner />

      <Tabs tabs={[...TABS]} active={tab()} onChange={setTab} />

      <Show when={tab() === '模块列表'}>
        <AdminCrudPage
          title="模块列表"
          description="管理平台内置模块注册表"
          total={paged.total()}
          onCreate={openCreateModule}
          createLabel="新增模块"
          onRefresh={() => void paged.refresh()}
          search={<SearchBar fields={SEARCH_FIELDS} loading={paged.loading()} onSearch={setFilters} />}
        >
          <DataTable
            columns={moduleColumns}
            rows={paged.items()}
            rowKey={(m) => m.id}
            total={paged.total()}
            page={paged.page()}
            totalPages={paged.totalPages()}
            pageSize={paged.pageSize()}
            loading={paged.loading()}
            error={paged.error()}
            emptyText="暂无模块"
            onPageChange={(p) => void paged.reload(p)}
            onPageSizeChange={(size) => paged.setPageSize(size)}
            actions={(m) => (
              <button type="button" class="btn btn-ghost btn-xs" onClick={() => openEditModule(m)}>
                编辑
              </button>
            )}
          />
        </AdminCrudPage>
      </Show>

      <Show when={tab() === '账号绑定'}>
        <AdminCrudPage
          title="账号绑定"
          description="管理当前账号的模块绑定"
          total={bindings().length}
          onCreate={openBindModal}
          createLabel="绑定模块"
          onRefresh={() => void reloadBindings()}
        >
          <DataTable
            columns={bindingColumns}
            rows={bindings()}
            rowKey={(b) => b.id}
            total={bindings().length}
            page={1}
            totalPages={1}
            loading={bindingsLoading()}
            error={null}
            emptyText="该账号未绑定模块"
            onPageChange={() => {}}
            actions={(b) => (
              <button type="button" class="btn btn-ghost btn-xs text-error" onClick={() => void onUnbind(b)}>
                解绑
              </button>
            )}
          />
        </AdminCrudPage>
      </Show>

      <Show when={tab() === '模块配置'}>
        <AdminCrudPage
          title="模块配置"
          description="为当前账号的已绑定模块编辑 JSON 配置"
          total={bindings().length}
          onRefresh={() => void reloadBindings()}
        >
          <div class="space-y-2">
            <For each={bindings()}>
              {(b) => (
                <div class="flex items-center justify-between rounded-lg border border-base-300 bg-base-100 px-4 py-3">
                  <div class="flex items-center gap-3">
                    <span class="font-mono text-sm">{b.module}</span>
                    <span class={`badge badge-sm ${b.status === 'active' ? 'badge-success' : 'badge-outline'}`}>
                      {b.status === 'active' ? '启用' : '停用'}
                    </span>
                  </div>
                  <button type="button" class="btn btn-ghost btn-xs" onClick={() => void openConfigModal(b)}>
                    配置
                  </button>
                </div>
              )}
            </For>
            <Show when={bindings().length === 0 && !bindingsLoading()}>
              <p class="py-10 text-center text-base-content/50">该账号未绑定模块</p>
            </Show>
          </div>
        </AdminCrudPage>
      </Show>

      <FormModal
        open={moduleModalOpen()}
        title={editingModule() ? '编辑模块' : '新增模块'}
        onSubmit={onModuleSubmit}
        onClose={() => setModuleModalOpen(false)}
        submitting={moduleSubmitting()}
        error={moduleError()}
        size="md"
      >
        <FormField label="模块名" required>
          <input
            type="text"
            class="input input-bordered input-sm w-full"
            placeholder="shop"
            value={moduleForm().name}
            onInput={(e) => setModuleField('name', e.currentTarget.value)}
            disabled={!!editingModule()}
            required
          />
        </FormField>
        <FormField label="名称" required>
          <input
            type="text"
            class="input input-bordered input-sm w-full"
            placeholder="商城"
            value={moduleForm().title}
            onInput={(e) => setModuleField('title', e.currentTarget.value)}
            required
          />
        </FormField>
        <FormField label="版本">
          <input
            type="text"
            class="input input-bordered input-sm w-full"
            value={moduleForm().version}
            onInput={(e) => setModuleField('version', e.currentTarget.value)}
          />
        </FormField>
        <FormField label="状态">
          <select
            class="select select-bordered select-sm w-full"
            value={moduleForm().status}
            onChange={(e) => setModuleField('status', e.currentTarget.value as 'active' | 'disabled')}
          >
            <option value="active">启用</option>
            <option value="disabled">停用</option>
          </select>
        </FormField>
      </FormModal>

      <FormModal
        open={bindModalOpen()}
        title="绑定模块"
        onSubmit={onBindSubmit}
        onClose={() => setBindModalOpen(false)}
        submitting={bindSubmitting()}
        error={bindError()}
        size="md"
      >
        <FormField label="模块" required>
          <select
            class="select select-bordered select-sm w-full"
            value={bindForm().module}
            onChange={(e) => setBindField('module', e.currentTarget.value)}
            required
          >
            <option value="">请选择模块</option>
            <For each={allModules()}>
              {(m) => <option value={m.name}>{m.title} ({m.name})</option>}
            </For>
          </select>
        </FormField>
        <FormField label="状态">
          <select
            class="select select-bordered select-sm w-full"
            value={bindForm().status}
            onChange={(e) => setBindField('status', e.currentTarget.value as 'active' | 'disabled')}
          >
            <option value="active">启用</option>
            <option value="disabled">停用</option>
          </select>
        </FormField>
      </FormModal>

      <FormModal
        open={configModalOpen()}
        title={`配置模块：${configuringModule()?.module ?? ''}`}
        onSubmit={onConfigSubmit}
        onClose={() => setConfigModalOpen(false)}
        submitting={configSubmitting()}
        error={configError()}
        size="lg"
      >
        <FormField label="JSON 配置" hint="请填写合法的 JSON，保存时会校验格式">
          <textarea
            class="textarea textarea-bordered w-full font-mono text-sm"
            rows={12}
            value={configText()}
            onInput={(e) => setConfigText(e.currentTarget.value)}
            placeholder="{}"
          />
        </FormField>
      </FormModal>
    </div>
  );
}

export default Modules;
