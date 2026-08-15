import { For, Show, createSignal } from 'solid-js';

import {
  createSeckill,
  listSeckillOrders,
  listSeckills,
  rushSeckill,
  toApiError,
  type SeckillActivityItem,
  type SeckillOrderItem,
} from '#ui/api';
import DataTable, { type Column } from '#ui/components/DataTable';
import { useAccounts } from '#ui/hooks/useAccounts';
import { usePaged } from '#ui/hooks/usePaged';
import { formatDateTime } from '#ui/utils';

const PAGE_SIZE = 20;

const yuan = (fen: number) => (fen / 100).toFixed(2);

function Seckill() {
  const accounts = useAccounts();
  const [success, setSuccess] = createSignal<string | null>(null);
  const [error, setError] = createSignal<string | null>(null);
  const [title, setTitle] = createSignal('');
  const [price, setPrice] = createSignal(9900);
  const [originalPrice, setOriginalPrice] = createSignal(19900);
  const [stock, setStock] = createSignal(100);
  const [rushOpenid, setRushOpenid] = createSignal('');

  const accountId = () => accounts.selected() ?? 0;
  const paged = usePaged<SeckillActivityItem>(
    (page, pageSize) => listSeckills(accountId(), page, pageSize),
    PAGE_SIZE,
  );
  const orders = usePaged<SeckillOrderItem>(
    (page, pageSize) => listSeckillOrders(accountId(), page, pageSize),
    PAGE_SIZE,
  );

  const columns: Column<SeckillActivityItem>[] = [
    { key: 'title', title: '活动', render: (r) => <span class="font-medium">{r.title}</span> },
    {
      key: 'price',
      title: '秒杀价',
      render: (r) => <span class="text-error font-semibold">¥{yuan(r.price)}</span>,
    },
    {
      key: 'original_price',
      title: '原价',
      render: (r) => <span class="line-through text-base-content/50">¥{yuan(r.original_price)}</span>,
    },
    {
      key: 'stock',
      title: '库存',
      render: (r) => (
        <span class={r.sold >= r.stock ? 'text-error' : ''}>
          {r.stock - r.sold} / {r.stock}
        </span>
      ),
    },
    { key: 'per_user', title: '限购', render: (r) => <span>{r.per_user} 件</span> },
    {
      key: 'created_at',
      title: '创建时间',
      render: (r) => <span class="text-sm text-base-content/70">{formatDateTime(r.created_at)}</span>,
    },
  ];

  const orderColumns: Column<SeckillOrderItem>[] = [
    { key: 'openid', title: '粉丝', render: (r) => <span class="font-mono text-xs">{r.openid}</span> },
    { key: 'quantity', title: '数量', render: (r) => <span>{r.quantity}</span> },
    {
      key: 'created_at',
      title: '抢购时间',
      render: (r) => <span class="text-sm text-base-content/70">{formatDateTime(r.created_at)}</span>,
    },
  ];

  const onAccountChange = (id: number) => {
    accounts.setSelected(id);
    void paged.reload(1);
    void orders.reload(1);
  };

  const onCreate = async (e: SubmitEvent) => {
    e.preventDefault();
    if (accountId() === 0) return;
    setError(null);
    setSuccess(null);
    try {
      await createSeckill({
        account_id: accountId(),
        title: title().trim(),
        price: price(),
        original_price: originalPrice(),
        stock: stock(),
        per_user: 1,
      });
      setTitle('');
      setSuccess('秒杀活动已创建');
      void paged.reload(1);
    } catch (err) {
      setError(toApiError(err).message);
    }
  };

  const onRush = async (row: SeckillActivityItem) => {
    const openid = rushOpenid().trim();
    if (!openid) {
      setError('请输入粉丝 openid');
      return;
    }
    try {
      await rushSeckill(row.id, openid, 1);
      setSuccess('抢购成功');
      void paged.reload(1);
      void orders.reload(1);
    } catch (err) {
      setError(toApiError(err).message);
    }
  };

  return (
    <div class="p-6 space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">秒杀</h1>
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

      <form onSubmit={onCreate} class="card bg-base-200 p-4 space-y-3">
        <h2 class="font-semibold">新建秒杀活动</h2>
        <div class="flex flex-wrap gap-2">
          <input
            class="input input-bordered flex-1 min-w-40"
            placeholder="活动名"
            value={title()}
            onInput={(e) => setTitle(e.currentTarget.value)}
          />
          <input
            class="input input-bordered w-28"
            type="number"
            placeholder="秒杀价(分)"
            value={price()}
            onInput={(e) => setPrice(Number(e.currentTarget.value))}
          />
          <input
            class="input input-bordered w-28"
            type="number"
            placeholder="原价(分)"
            value={originalPrice()}
            onInput={(e) => setOriginalPrice(Number(e.currentTarget.value))}
          />
          <input
            class="input input-bordered w-28"
            type="number"
            placeholder="库存"
            value={stock()}
            onInput={(e) => setStock(Number(e.currentTarget.value))}
          />
          <button class="btn btn-primary" type="submit">
            创建
          </button>
        </div>
      </form>

      <div class="card bg-base-200 p-4 space-y-3">
        <h2 class="font-semibold">手动抢购</h2>
        <div class="flex flex-wrap gap-2">
          <input
            class="input input-bordered flex-1 min-w-40"
            placeholder="粉丝 openid（先填再点活动「抢购」）"
            value={rushOpenid()}
            onInput={(e) => setRushOpenid(e.currentTarget.value)}
          />
        </div>
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
        emptyText="暂无秒杀活动"
        onPageChange={(p) => void paged.reload(p)}
        actions={(row) => (
          <button class="btn btn-xs btn-outline btn-primary" onClick={() => void onRush(row)}>
            抢购
          </button>
        )}
      />

      <div class="card bg-base-200 p-4">
        <h2 class="font-semibold mb-3">抢购记录</h2>
        <DataTable
          columns={orderColumns}
          rows={orders.items()}
          rowKey={(r) => r.id}
          total={orders.total()}
          page={orders.page()}
          totalPages={orders.totalPages()}
          loading={orders.loading()}
          error={orders.error()}
          emptyText="暂无抢购记录"
          onPageChange={(p) => void orders.reload(p)}
        />
      </div>
    </div>
  );
}

export default Seckill;
