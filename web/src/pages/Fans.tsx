import { For, Show, createSignal } from 'solid-js';

import { listFans, type FanItem } from '#ui/api';
import DataTable, { type Column } from '#ui/components/DataTable';
import { useAccounts } from '#ui/hooks/useAccounts';
import { usePaged } from '#ui/hooks/usePaged';
import { formatDateTime } from '#ui/utils';

const PAGE_SIZE = 20;

function Fans() {
  const accounts = useAccounts();
  const [keyword, setKeyword] = createSignal('');
  const accountId = () => accounts.selected() ?? 0;

  const paged = usePaged<FanItem>(
    (page, pageSize) => listFans(page, pageSize, accountId(), keyword().trim() || undefined),
    PAGE_SIZE,
  );

  const onAccountChange = (id: number) => {
    accounts.setSelected(id);
    void paged.reload(1);
  };

  const onSearch = (e: SubmitEvent) => {
    e.preventDefault();
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
    <div class="space-y-4">
      <div>
        <h2 class="text-xl font-semibold">粉丝管理</h2>
        <p class="text-sm text-base-content/60">公众号关注粉丝，微信回调自动同步</p>
      </div>

      <div class="flex items-end gap-2">
        <label class="form-control w-full max-w-xs">
          <span class="label-text mb-1">选择账号</span>
          <select class="select select-bordered select-sm" value={accountId()} onChange={(e) => onAccountChange(Number(e.currentTarget.value))}>
            <For each={accounts.accounts()}>
              {(a) => (
                <option value={a.id}>
                  {a.name}（{a.id}）
                </option>
              )}
            </For>
          </select>
        </label>
        <form onSubmit={onSearch} class="flex items-end gap-2">
          <label class="form-control">
            <span class="label-text mb-1">搜索</span>
            <input
              type="text"
              class="input input-bordered input-sm"
              placeholder="昵称 / OpenID"
              value={keyword()}
              onInput={(e) => setKeyword(e.currentTarget.value)}
            />
          </label>
          <button type="submit" class="btn btn-primary btn-sm">
            搜索
          </button>
        </form>
      </div>

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
    </div>
  );
}

export default Fans;
