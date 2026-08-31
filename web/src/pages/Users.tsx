import { createSignal } from 'solid-js';

import { deleteUser, listUsers, revokeUserSessions, type AuthUser } from '#ui/api';
import AdminCrudPage from '#ui/components/AdminCrudPage';
import DataTable, { type Column } from '#ui/components/DataTable';
import SearchBar, { type SearchField, type SearchValues } from '#ui/components/SearchBar';
import UserFormModal, { type UserFormTarget } from '#ui/components/UserFormModal';
import { useAuth, useFeedback, usePaged } from '#ui/hooks';
import { formatDateTime } from '#ui/utils';

const SEARCH_FIELDS: SearchField[] = [
  { kind: 'text', key: 'keyword', label: '姓名 / 邮箱', placeholder: '输入关键字后查询' },
];

function Users() {
  const [auth] = useAuth();
  const feedback = useFeedback();
  const [filters, setFilters] = createSignal<SearchValues>({});

  const [modalOpen, setModalOpen] = createSignal(false);
  const [modalMode, setModalMode] = createSignal<UserFormTarget>('create');
  const [modalUser, setModalUser] = createSignal<AuthUser | null>(null);

  const paged = usePaged<AuthUser>(
    (page, pageSize) => listUsers(page, pageSize, filters().keyword?.trim() || undefined),
    20,
    () => filters(),
  );

  const isSelf = (user: AuthUser) => user.id === auth.user?.id;

  const openCreate = () => {
    setModalMode('create');
    setModalUser(null);
    setModalOpen(true);
  };

  const openEdit = (user: AuthUser) => {
    setModalMode('edit');
    setModalUser(user);
    setModalOpen(true);
  };

  const onRemove = (user: AuthUser) =>
    feedback.runAction({
      confirm: {
        title: '删除用户',
        message: `确定删除用户「${user.name}」吗？此操作不可恢复。`,
        danger: true,
      },
      action: () => deleteUser(user.id),
      success: '用户已删除',
      onDone: () => void paged.refresh(),
    });

  const onRevoke = (user: AuthUser) =>
    feedback.runAction({
      confirm: {
        title: '踢下线',
        message: `确定将「${user.name}」踢下线？其所有登录将立即失效。`,
        danger: true,
      },
      action: () => revokeUserSessions(user.id),
      success: '已踢下线',
    });

  const columns: Column<AuthUser>[] = [
    { key: 'id', title: 'ID', render: (u) => <span class="font-mono text-xs">{u.id}</span> },
    { key: 'name', title: '姓名', render: (u) => u.name },
    { key: 'email', title: '邮箱', render: (u) => <span class="text-sm">{u.email}</span> },
    {
      key: 'admin',
      title: '角色',
      render: (u) => (
        <span class={`badge badge-sm ${u.admin ? 'badge-primary' : 'badge-ghost'}`}>
          {u.admin ? '管理员' : '用户'}
        </span>
      ),
    },
    {
      key: 'verified',
      title: '状态',
      render: (u) => (
        <span class={`badge badge-sm ${u.verified ? 'badge-success' : 'badge-outline'}`}>
          {u.verified ? '已验证' : '未验证'}
        </span>
      ),
    },
    {
      key: 'tenant_id',
      title: '租户',
      render: (u) => <span class="badge badge-sm badge-ghost font-mono">{u.tenant_id}</span>,
    },
    {
      key: 'created_at',
      title: '创建时间',
      render: (u) => <span class="text-sm text-base-content/70">{formatDateTime(u.created_at)}</span>,
    },
  ];

  return (
    <AdminCrudPage
      title="用户管理"
      total={paged.total()}
      onCreate={openCreate}
      createLabel="新建用户"
      onRefresh={() => void paged.refresh()}
      extra={
        <a href="/api/v1/users/export" download="users.csv" class="btn btn-outline btn-sm">
          导出 CSV
        </a>
      }
      search={<SearchBar fields={SEARCH_FIELDS} loading={paged.loading()} onSearch={setFilters} />}
    >
      <DataTable
        columns={columns}
        rows={paged.items()}
        rowKey={(u) => u.id}
        total={paged.total()}
        page={paged.page()}
        totalPages={paged.totalPages()}
        pageSize={paged.pageSize()}
        loading={paged.loading()}
        error={paged.error()}
        emptyText="暂无用户"
        onPageChange={(p) => void paged.reload(p)}
        onPageSizeChange={(size) => paged.setPageSize(size)}
        actions={(user) => (
          <>
            <button type="button" class="btn btn-ghost btn-xs" onClick={() => openEdit(user)} disabled={isSelf(user)}>
              编辑
            </button>
            <button
              type="button"
              class="btn btn-ghost btn-xs text-error"
              onClick={() => void onRemove(user)}
              disabled={isSelf(user)}
            >
              删除
            </button>
            <button
              type="button"
              class="btn btn-ghost btn-xs text-warning"
              onClick={() => void onRevoke(user)}
              disabled={isSelf(user)}
            >
              踢下线
            </button>
          </>
        )}
      />

      <UserFormModal
        open={modalOpen()}
        mode={modalMode()}
        user={modalUser()}
        onClose={() => setModalOpen(false)}
        onSaved={() => {
          feedback.toast(modalMode() === 'create' ? '用户已创建' : '用户已更新');
          void paged.refresh();
        }}
      />
    </AdminCrudPage>
  );
}

export default Users;
