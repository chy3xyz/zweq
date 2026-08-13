import { For, Show, createSignal } from 'solid-js';

import { listCheckinRecords, type CheckinRecord } from '#ui/api';
import DataTable, { type Column } from '#ui/components/DataTable';
import { useAccounts } from '#ui/hooks/useAccounts';
import { usePaged } from '#ui/hooks/usePaged';
import { formatDateTime } from '#ui/utils';

const PAGE_SIZE = 20;

function Checkin() {
  const accounts = useAccounts();
  const accountId = () => accounts.selected() ?? 0;
  const paged = usePaged<CheckinRecord>(
    (page, pageSize) => listCheckinRecords(accountId(), page, pageSize),
    PAGE_SIZE,
  );

  const columns: Column<CheckinRecord>[] = [
    { key: 'openid', title: '粉丝', render: (r) => <span class="font-mono text-xs">{r.openid}</span> },
    { key: 'points', title: '获得积分', render: (r) => <span>{r.points}</span> },
    {
      key: 'created_at',
      title: '签到时间',
      render: (r) => <span class="text-sm text-base-content/70">{formatDateTime(r.created_at)}</span>,
    },
  ];

  return (
    <div class="p-6 space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">签到记录</h1>
        <select
          class="select select-bordered"
          onChange={(e) => {
            accounts.setSelected(Number(e.currentTarget.value));
            void paged.reload(1);
          }}
        >
          <option value={0}>选择公众号</option>
          <For each={accounts.accounts()}>
            {(a) => <option value={a.id}>{a.name}</option>}
          </For>
        </select>
      </div>

      <Show when={accountId() === 0}>
        <div class="alert alert-info">请先选择公众号查看签到记录</div>
      </Show>

      <DataTable
        columns={columns}
        rows={paged.items()}
        rowKey={(r) => r.id}
        total={paged.total()}
        page={paged.page()}
        totalPages={paged.totalPages()}
        loading={paged.loading()}
        error={paged.error()}
        emptyText="暂无签到记录"
        onPageChange={(p) => void paged.reload(p)}
      />
    </div>
  );
}

export default Checkin;
