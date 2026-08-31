import { createSignal } from 'solid-js';

import { deleteAccount, listAccounts, updateAccount, type AccountItem, type AccountKind } from '#ui/api';
import AccountCreateModal, { AccountWechatModal } from '#ui/components/AccountFormModal';
import AdminCrudPage from '#ui/components/AdminCrudPage';
import DataTable, { type Column } from '#ui/components/DataTable';
import SearchBar, { type SearchField, type SearchValues } from '#ui/components/SearchBar';
import { useFeedback, usePaged } from '#ui/hooks';
import { formatDateTime } from '#ui/utils';

const KIND_LABEL: Record<AccountKind, string> = { wechat: '公众号', wxapp: '小程序', app: 'APP' };

const SEARCH_FIELDS: SearchField[] = [
  { kind: 'text', key: 'keyword', label: '账号名称', placeholder: '输入名称关键字' },
  {
    kind: 'select',
    key: 'kind',
    label: '类型',
    options: [
      { value: '', label: '全部' },
      { value: 'wechat', label: '公众号' },
      { value: 'wxapp', label: '小程序' },
      { value: 'app', label: 'APP' },
    ],
  },
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

function Accounts() {
  const feedback = useFeedback();
  const [filters, setFilters] = createSignal<SearchValues>({});
  const [createOpen, setCreateOpen] = createSignal(false);
  const [wechatOpen, setWechatOpen] = createSignal(false);
  const [wechatAccount, setWechatAccount] = createSignal<AccountItem | null>(null);

  const paged = usePaged<AccountItem>(
    (page, pageSize) =>
      listAccounts(
        page,
        pageSize,
        filters().kind || undefined,
        filters().keyword?.trim() ?? '',
        filters().status ?? '',
      ),
    20,
    () => filters(),
  );

  const openWechat = (account: AccountItem) => {
    setWechatAccount(account);
    setWechatOpen(true);
  };

  const onToggle = (account: AccountItem) => {
    const disabling = account.status === 'active';
    return feedback.runAction({
      confirm: {
        title: disabling ? '停用账号' : '启用账号',
        message: `确定${disabling ? '停用' : '启用'}账号「${account.name}」吗？`,
        danger: disabling,
      },
      action: () => updateAccount(account.id, { status: disabling ? 'disabled' : 'active' }),
      success: `账号「${account.name}」已${disabling ? '停用' : '启用'}`,
      onDone: () => void paged.refresh(),
    });
  };

  const onDelete = (account: AccountItem) =>
    feedback.runAction({
      confirm: {
        title: '删除账号',
        message: `确定删除账号「${account.name}」吗？该操作不可恢复。`,
        danger: true,
      },
      action: () => deleteAccount(account.id),
      success: `账号「${account.name}」已删除`,
      onDone: () => void paged.refresh(),
    });

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
    <AdminCrudPage
      title="账号管理"
      description="平台账号（公众号 / 小程序 / APP）与微信服务器配置"
      total={paged.total()}
      onCreate={() => setCreateOpen(true)}
      createLabel="新增账号"
      onRefresh={() => void paged.refresh()}
      search={<SearchBar fields={SEARCH_FIELDS} loading={paged.loading()} onSearch={setFilters} />}
    >
      <DataTable
        columns={columns}
        rows={paged.items()}
        rowKey={(a) => a.id}
        total={paged.total()}
        page={paged.page()}
        totalPages={paged.totalPages()}
        pageSize={paged.pageSize()}
        loading={paged.loading()}
        error={paged.error()}
        emptyText="暂无账号"
        onPageChange={(p) => void paged.reload(p)}
        onPageSizeChange={(size) => paged.setPageSize(size)}
        actions={(account) => (
          <>
            <button type="button" class="btn btn-ghost btn-xs" onClick={() => openWechat(account)}>
              编辑配置
            </button>
            <button
              type="button"
              class={`btn btn-ghost btn-xs ${account.status === 'active' ? 'text-error' : ''}`}
              onClick={() => void onToggle(account)}
            >
              {account.status === 'active' ? '停用' : '启用'}
            </button>
            <button type="button" class="btn btn-ghost btn-xs text-error" onClick={() => void onDelete(account)}>
              删除
            </button>
          </>
        )}
      />

      <AccountCreateModal
        open={createOpen()}
        onClose={() => setCreateOpen(false)}
        onSaved={() => {
          feedback.toast('账号已创建');
          void paged.refresh();
        }}
      />
      <AccountWechatModal
        open={wechatOpen()}
        account={wechatAccount()}
        onClose={() => setWechatOpen(false)}
        onSaved={() => {
          feedback.toast(`账号「${wechatAccount()?.name ?? ''}」微信配置已保存`);
          void paged.refresh();
        }}
      />
    </AdminCrudPage>
  );
}

export default Accounts;
