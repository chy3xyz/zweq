import { For, Show, createSignal } from 'solid-js';

import {
  listShopOrders,
  shipShopOrder,
  toApiError,
  type ShopOrderItem,
} from '#ui/api';
import DataTable, { type Column } from '#ui/components/DataTable';
import { useAccounts } from '#ui/hooks/useAccounts';
import { usePaged } from '#ui/hooks/usePaged';
import { formatDateTime } from '#ui/utils';

const PAGE_SIZE = 20;
const yuan = (fen: number) => (fen / 100).toFixed(2);
const STATUS: Record<number, { label: string; cls: string }> = {
  0: { label: '待支付', cls: 'text-warning' },
  1: { label: '已支付', cls: 'text-info' },
  2: { label: '已发货', cls: 'text-primary' },
  3: { label: '已完成', cls: 'text-success' },
  4: { label: '已取消', cls: 'text-base-content/50' },
};

function ShopOrders() {
  const accounts = useAccounts();
  const [success, setSuccess] = createSignal<string | null>(null);
  const [error, setError] = createSignal<string | null>(null);
  const [statusFilter, setStatusFilter] = createSignal(-1);

  const accountId = () => accounts.selected() ?? 0;
  const paged = usePaged<ShopOrderItem>(
    (page, pageSize) => listShopOrders(accountId(), page, pageSize, statusFilter()),
    PAGE_SIZE,
  );

  const columns: Column<ShopOrderItem>[] = [
    { key: 'order_no', title: '订单号', render: (r) => <span class="font-mono text-xs">{r.order_no}</span> },
    { key: 'openid', title: '买家', render: (r) => <span class="font-mono text-xs">{r.openid}</span> },
    {
      key: 'pay_amount',
      title: '实付',
      render: (r) => <span class="text-error font-semibold">¥{yuan(r.pay_amount)}</span>,
    },
    {
      key: 'status',
      title: '状态',
      render: (r) => <span class={STATUS[r.status]?.cls ?? ''}>{STATUS[r.status]?.label ?? r.status}</span>,
    },
    {
      key: 'created_at',
      title: '下单时间',
      render: (r) => <span class="text-sm text-base-content/70">{formatDateTime(r.created_at)}</span>,
    },
  ];

  const onAccountChange = (id: number) => {
    accounts.setSelected(id);
    void paged.reload(1);
  };

  const onShip = async (row: ShopOrderItem) => {
    const company = prompt('快递公司', '顺丰') ?? '';
    const no = prompt('快递单号', '') ?? '';
    if (!no) return;
    try {
      await shipShopOrder(row.id, company, no);
      setSuccess('已发货');
      void paged.reload(1);
    } catch (err) {
      setError(toApiError(err).message);
    }
  };

  return (
    <div class="p-6 space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">订单管理</h1>
        <select
          class="select select-bordered"
          onChange={(e) => onAccountChange(Number(e.currentTarget.value))}
        >
          <option value={0}>选择公众号</option>
          <For each={accounts.accounts()}>
            {(a) => <option value={a.id}>{a.name}</option>}
          </For>
        </select>
      </div>

      <Show when={success()}>
        <div class="alert alert-success">{success()}</div>
      </Show>
      <Show when={error()}>
        <div class="alert alert-error">{error()}</div>
      </Show>

      <div class="flex gap-2">
        {[-1, 0, 1, 2, 3, 4].map((s) => (
          <button
            class={`btn btn-xs ${statusFilter() === s ? 'btn-primary' : 'btn-outline'}`}
            onClick={() => {
              setStatusFilter(s);
              void paged.reload(1);
            }}
          >
            {s === -1 ? '全部' : STATUS[s]?.label ?? s}
          </button>
        ))}
      </div>

      <DataTable
        columns={columns}
        rows={paged.items()}
        rowKey={(r) => r.id}
        total={paged.total()}
        page={paged.page()}
        totalPages={paged.totalPages()}
        loading={paged.loading()}
        error={paged.error()}
        emptyText="暂无订单"
        onPageChange={(p) => void paged.reload(p)}
        actions={(row) => (
          <Show when={row.status === 1}>
            <button class="btn btn-xs btn-outline btn-primary" onClick={() => void onShip(row)}>
              发货
            </button>
          </Show>
        )}
      />
    </div>
  );
}

export default ShopOrders;
