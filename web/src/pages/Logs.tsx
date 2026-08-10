import { For, Show } from 'solid-js';

import { listLogs, type LogItem } from '#ui/api';
import DataTable, { type Column } from '#ui/components/DataTable';
import { useAccounts } from '#ui/hooks/useAccounts';
import { usePaged } from '#ui/hooks/usePaged';
import { formatDateTime } from '#ui/utils';

const PAGE_SIZE = 20;

function Logs() {
  const accounts = useAccounts();
  const accountId = () => accounts.selected() ?? 0;

  const paged = usePaged<LogItem>((page, pageSize) => listLogs(page, pageSize, accountId()), PAGE_SIZE);

  const onAccountChange = (id: number) => {
    accounts.setSelected(id);
    void paged.reload(1);
  };

  const columns: Column<LogItem>[] = [
    { key: 'id', title: 'ID', render: (l) => <span class="font-mono text-xs">{l.id}</span> },
    {
      key: 'msg_type',
      title: '类型',
      render: (l) => (
        <span class="badge badge-sm badge-ghost">
          {l.msg_type}
          {l.event && ` / ${l.event}`}
        </span>
      ),
    },
    { key: 'openid', title: '粉丝', render: (l) => <span class="font-mono text-xs">{l.openid.slice(0, 20)}</span> },
    { key: 'content', title: '消息内容', render: (l) => <span class="max-w-[240px] truncate text-sm">{l.content}</span> },
    {
      key: 'reply_content',
      title: '回复',
      render: (l) => (
        <span class={`max-w-[240px] truncate text-sm ${l.reply_content ? '' : 'text-base-content/40'}`}>
          {l.reply_content || '-'}
        </span>
      ),
    },
    { key: 'created_at', title: '时间', render: (l) => <span class="text-sm text-base-content/70">{formatDateTime(l.created_at)}</span> },
  ];

  return (
    <div class="space-y-4">
      <div>
        <h2 class="text-xl font-semibold">消息日志</h2>
        <p class="text-sm text-base-content/60">微信公众号服务器回调日志</p>
      </div>

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

      <DataTable
        columns={columns}
        rows={paged.items()}
        rowKey={(l) => l.id}
        total={paged.total()}
        page={paged.page()}
        totalPages={paged.totalPages()}
        loading={paged.loading()}
        error={paged.error()}
        emptyText="暂无日志"
        onPageChange={(p) => void paged.reload(p)}
      />
    </div>
  );
}

export default Logs;
