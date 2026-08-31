import { createSignal } from 'solid-js';

import { createTenant, listTenants, updateTenant, type TenantItem } from '#ui/api';
import AdminCrudPage from '#ui/components/AdminCrudPage';
import DataTable, { type Column } from '#ui/components/DataTable';
import FormModal from '#ui/components/FormModal';
import SearchBar, { type SearchField, type SearchValues } from '#ui/components/SearchBar';
import { useFeedback, usePaged } from '#ui/hooks';
import { formatDateTime } from '#ui/utils';

const SEARCH_FIELDS: SearchField[] = [
  { kind: 'text', key: 'keyword', label: '租户名称', placeholder: '输入名称关键字' },
  {
    kind: 'select',
    key: 'status',
    label: '状态',
    options: [
      { value: '', label: '全部' },
      { value: 'active', label: '启用' },
      { value: 'disabled', label: '停用' },
    ],
  },
];

function Tenants() {
  const feedback = useFeedback();
  const [filters, setFilters] = createSignal<SearchValues>({});
  const [createOpen, setCreateOpen] = createSignal(false);
  const [name, setName] = createSignal('');
  const [submitting, setSubmitting] = createSignal(false);
  const [error, setError] = createSignal<string | null>(null);

  const paged = usePaged<TenantItem>(
    (page, pageSize) =>
      listTenants(page, pageSize, filters().keyword?.trim() ?? '', filters().status ?? ''),
    20,
    () => filters(),
  );

  const onSubmit = async () => {
    if (submitting()) return;
    setSubmitting(true);
    setError(null);
    try {
      await createTenant({ name: name().trim() });
      setCreateOpen(false);
      setName('');
      feedback.toast('租户已创建');
      void paged.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : '创建失败，请稍后重试');
    } finally {
      setSubmitting(false);
    }
  };

  const onToggle = (tenant: TenantItem) => {
    const disabling = tenant.status === 'active';
    return feedback.runAction({
      confirm: {
        title: disabling ? '停用租户' : '启用租户',
        message: `确定${disabling ? '停用' : '启用'}租户「${tenant.name}」吗？`,
        danger: disabling,
      },
      action: () => updateTenant(tenant.id, { status: disabling ? 'disabled' : 'active' }),
      success: `租户「${tenant.name}」已${disabling ? '停用' : '启用'}`,
      onDone: () => void paged.refresh(),
    });
  };

  const columns: Column<TenantItem>[] = [
    { key: 'id', title: 'ID', render: (t) => <span class="font-mono text-xs">{t.id}</span> },
    { key: 'name', title: '名称', render: (t) => <span class="font-medium">{t.name}</span> },
    {
      key: 'status',
      title: '状态',
      render: (t) => (
        <span class={`badge badge-sm ${t.status === 'active' ? 'badge-success' : 'badge-outline'}`}>
          {t.status === 'active' ? '启用' : '停用'}
        </span>
      ),
    },
    {
      key: 'created_at',
      title: '创建时间',
      render: (t) => <span class="text-sm text-base-content/70">{formatDateTime(t.created_at)}</span>,
    },
  ];

  return (
    <AdminCrudPage
      title="租户管理"
      description="多租户隔离：每个租户拥有独立的用户与数据"
      total={paged.total()}
      onCreate={() => {
        setName('');
        setError(null);
        setCreateOpen(true);
      }}
      createLabel="新增租户"
      onRefresh={() => void paged.reload()}
      search={<SearchBar fields={SEARCH_FIELDS} loading={paged.loading()} onSearch={setFilters} />}
    >
      <DataTable
        columns={columns}
        rows={paged.items()}
        rowKey={(t) => t.id}
        total={paged.total()}
        page={paged.page()}
        totalPages={paged.totalPages()}
        pageSize={paged.pageSize()}
        loading={paged.loading()}
        error={paged.error()}
        emptyText="暂无租户"
        onPageChange={(p) => void paged.reload(p)}
        onPageSizeChange={(size) => paged.setPageSize(size)}
        actions={(tenant) => (
          <button
            type="button"
            class={`btn btn-ghost btn-xs ${tenant.status === 'active' ? 'text-error' : ''}`}
            onClick={() => void onToggle(tenant)}
          >
            {tenant.status === 'active' ? '停用' : '启用'}
          </button>
        )}
      />

      <FormModal
        open={createOpen()}
        title="新增租户"
        onSubmit={onSubmit}
        onClose={() => setCreateOpen(false)}
        submitting={submitting()}
        error={error()}
        submitLabel="创建"
        size="sm"
      >
        <label class="form-control w-full">
          <span class="label-text mb-1">租户名称</span>
          <input
            type="text"
            class="input input-bordered input-sm"
            placeholder="例如：Acme Inc"
            value={name()}
            onInput={(e) => setName(e.currentTarget.value)}
            required
          />
        </label>
      </FormModal>
    </AdminCrudPage>
  );
}

export default Tenants;
