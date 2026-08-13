import { For, Show, createSignal } from 'solid-js';

import {
  adjustPoints,
  createProduct,
  deleteProduct,
  listPointsOrders,
  listProducts,
  redeemPoints,
  toApiError,
  updateProduct,
  type PointsOrder,
  type PointsProduct,
} from '#ui/api';
import DataTable, { type Column } from '#ui/components/DataTable';
import { useAccounts } from '#ui/hooks/useAccounts';
import { usePaged } from '#ui/hooks/usePaged';
import { formatDateTime } from '#ui/utils';

const PAGE_SIZE = 20;

function Points() {
  const accounts = useAccounts();
  const [success, setSuccess] = createSignal<string | null>(null);
  const [error, setError] = createSignal<string | null>(null);
  const [nameInput, setNameInput] = createSignal('');
  const [pointsInput, setPointsInput] = createSignal(0);
  const [stockInput, setStockInput] = createSignal(0);
  const [openidInput, setOpenidInput] = createSignal('');
  const [deltaInput, setDeltaInput] = createSignal(0);
  const [redeemOpenid, setRedeemOpenid] = createSignal('');
  const [orders, setOrders] = createSignal<PointsOrder[]>([]);

  const accountId = () => accounts.selected() ?? 0;
  const paged = usePaged<PointsProduct>((page, pageSize) => listProducts(accountId(), page, pageSize), PAGE_SIZE);

  const productColumns: Column<PointsProduct>[] = [
    { key: 'name', title: '商品', render: (r) => <span class="font-medium">{r.name}</span> },
    { key: 'points', title: '积分', render: (r) => <span>{r.points}</span> },
    { key: 'stock', title: '库存', render: (r) => <span>{r.stock}</span> },
    {
      key: 'created_at',
      title: '创建时间',
      render: (r) => <span class="text-sm text-base-content/70">{formatDateTime(r.created_at)}</span>,
    },
  ];

  const onAccountChange = (id: number) => {
    accounts.setSelected(id);
    void paged.reload(1);
    void loadOrders(id);
  };

  const onCreate = async (e: SubmitEvent) => {
    e.preventDefault();
    if (accountId() === 0) return;
    setError(null);
    setSuccess(null);
    try {
      await createProduct(accountId(), {
        name: nameInput().trim(),
        points: pointsInput(),
        stock: stockInput(),
      });
      setNameInput('');
      setSuccess('商品已创建');
      void paged.reload(1);
    } catch (err) {
      setError(toApiError(err).message);
    }
  };

  const onRedeem = async (productId: number) => {
    const openid = redeemOpenid().trim();
    if (!openid) {
      setError('请输入粉丝 openid');
      return;
    }
    try {
      await redeemPoints(accountId(), { openid, product_id: productId });
      setSuccess('兑换成功');
    } catch (err) {
      setError(toApiError(err).message);
    }
  };

  const onAdjust = async (e: SubmitEvent) => {
    e.preventDefault();
    if (accountId() === 0) return;
    try {
      await adjustPoints(accountId(), { openid: openidInput().trim(), delta: deltaInput() });
      setSuccess('积分已调整');
      setOpenidInput('');
    } catch (err) {
      setError(toApiError(err).message);
    }
  };

  const onDelete = async (id: number) => {
    try {
      await deleteProduct(id);
      setSuccess('已删除');
      void paged.reload(1);
    } catch (err) {
      setError(toApiError(err).message);
    }
  };

  const loadOrders = async (id: number) => {
    if (id === 0) return;
    try {
      setOrders(await listPointsOrders(id));
    } catch {
      setOrders([]);
    }
  };

  const orderColumns: Column<PointsOrder>[] = [
    { key: 'openid', title: '粉丝', render: (r) => <span class="font-mono text-xs">{r.openid}</span> },
    { key: 'product_name', title: '商品', render: (r) => <span>{r.product_name}</span> },
    { key: 'points', title: '积分', render: (r) => <span>{r.points}</span> },
    {
      key: 'created_at',
      title: '时间',
      render: (r) => <span class="text-sm text-base-content/70">{formatDateTime(r.created_at)}</span>,
    },
  ];

  return (
    <div class="p-6 space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">积分商城</h1>
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
        <h2 class="font-semibold">新建商品</h2>
        <div class="flex gap-2">
          <input
            class="input input-bordered flex-1"
            placeholder="商品名"
            value={nameInput()}
            onInput={(e) => setNameInput(e.currentTarget.value)}
          />
          <input
            class="input input-bordered w-28"
            type="number"
            placeholder="积分"
            value={pointsInput()}
            onInput={(e) => setPointsInput(Number(e.currentTarget.value))}
          />
          <input
            class="input input-bordered w-28"
            type="number"
            placeholder="库存"
            value={stockInput()}
            onInput={(e) => setStockInput(Number(e.currentTarget.value))}
          />
          <button class="btn btn-primary" type="submit">
            创建
          </button>
        </div>
      </form>

      <DataTable
        columns={productColumns}
        rows={paged.items()}
        rowKey={(r) => r.id}
        total={paged.total()}
        page={paged.page()}
        totalPages={paged.totalPages()}
        loading={paged.loading()}
        error={paged.error()}
        emptyText="暂无商品"
        onPageChange={(p) => void paged.reload(p)}
        actions={(row) => (
          <div class="flex gap-1">
            <button class="btn btn-xs btn-outline btn-primary" onClick={() => void onRedeem(row.id)}>
              兑换
            </button>
            <button class="btn btn-xs btn-outline btn-error" onClick={() => void onDelete(row.id)}>
              删除
            </button>
          </div>
        )}
      />

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <form onSubmit={onAdjust} class="card bg-base-200 p-4 space-y-3">
          <h2 class="font-semibold">调整积分</h2>
          <div class="flex gap-2">
            <input
              class="input input-bordered flex-1"
              placeholder="粉丝 openid"
              value={openidInput()}
              onInput={(e) => setOpenidInput(e.currentTarget.value)}
            />
            <input
              class="input input-bordered w-28"
              type="number"
              placeholder="增减"
              value={deltaInput()}
              onInput={(e) => setDeltaInput(Number(e.currentTarget.value))}
            />
            <button class="btn btn-primary" type="submit">
              调整
            </button>
          </div>
        </form>

        <div class="card bg-base-200 p-4 space-y-3">
          <h2 class="font-semibold">兑换（先填 openid 再点商品「兑换」）</h2>
          <input
            class="input input-bordered"
            placeholder="粉丝 openid"
            value={redeemOpenid()}
            onInput={(e) => setRedeemOpenid(e.currentTarget.value)}
          />
        </div>
      </div>

      <div class="card bg-base-200 p-4">
        <h2 class="font-semibold mb-3">兑换订单</h2>
        <DataTable
          columns={orderColumns}
          rows={orders()}
          rowKey={(r) => r.id}
          total={orders().length}
          page={1}
          totalPages={1}
          loading={false}
          error={null}
          emptyText="暂无订单"
          onPageChange={() => {}}
        />
      </div>
    </div>
  );
}

export default Points;
