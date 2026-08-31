import { createSignal } from 'solid-js';

import { listFans, type FanItem } from '#ui/api';
import AccountRequiredBanner from '#ui/components/AccountRequiredBanner';
import AdminCrudPage from '#ui/components/AdminCrudPage';
import DataTable, { type Column } from '#ui/components/DataTable';
import { useAccountId } from '#ui/hooks/useAccountId';
import { usePaged } from '#ui/hooks/usePaged';
import { formatDateTime } from '#ui/utils';

const PAGE_SIZE = 20;

function Fans() {
  const { accountId } = useAccountId();
  const [keyword, setKeyword] = createSignal('');
  const [searchInput, setSearchInput] = createSignal('');

  const paged = usePaged<FanItem>(
    (page, pageSize) => listFans(page, pageSize, accountId(), keyword().trim() || undefined),
    PAGE_SIZE,
    accountId,
  );

  const onSearch = (e: SubmitEvent) => {
    e.preventDefault();
    setKeyword(searchInput());
    void paged.reload(1);
  };

  const columns: Column<FanItem>[] = [
    { key: 'id', title: 'ID', render: (f) => <span class="font-mono text-xs">{f.id}</span> },
    { key: 'nickname', title: '昵称', render: (f) => <span class="font-medium">{f.nickname || '-'}</span> },
    { key: 'openid', title: 'OpenID', render: (f) => <span class="font-mono text-xs">{f.openid.slice(0, 24)}…</span> },
    {
      key: 'subscribed',
      title: '状态',
      render: (f) => (
        <span class={`badge badge-sm ${f.subscribed ? 'badge-success' : 'badge-outline'}`}>
          {f.subscribed ? '已关注' : '已取关'}
        </span>
      ),
    },
    {
      key: 'created_at',
      title: '首次关注',
      render: (f) => <span class="text-sm text-base-content/70">{formatDateTime(f.created_at)}</span>,
    },
  ];

  return (
    <AdminCrudPage
      title="粉丝管理"
      description="公众号关注粉丝，微信回调自动同步（使用顶栏当前公众号）"
      total={paged.total()}
    >
      <AccountRequiredBanner />

      <form onSubmit={onSearch} class="mb-4 flex flex-wrap items-end gap-2">
        <label class="form-control min-w-48 flex-1">
          <span class="label-text mb-1 text-xs">搜索</span>
          <input
            type="text"
            class="input input-bordered input-sm w-full"
            placeholder="昵称 / OpenID"
            value={searchInput()}
            onInput={(e) => setSearchInput(e.currentTarget.value)}
          />
        </label>
        <button type="submit" class="btn btn-primary btn-sm" disabled={paged.loading() || accountId() <= 0}>
          查询
        </button>
      </form>

      <DataTable
        columns={columns}
        rows={paged.items()}
        rowKey={(f) => f.id}
        total={paged.total()}
        page={paged.page()}
        totalPages={paged.totalPages()}
        loading={paged.loading()}
        error={paged.error()}
        emptyText="暂无粉丝"
        onPageChange={(p) => void paged.reload(p)}
      />
    </AdminCrudPage>
  );
}

export default Fans;
