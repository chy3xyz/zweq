import { For, Show, createSignal } from 'solid-js';

import {
  completeRecharge,
  createRechargeOrder,
  createWithdraw,
  getWallet,
  listOrders,
  listWithdraws,
  toApiError,
  type OrderItem,
  type WithdrawItem,
} from '#ui/api';
import DataTable, { type Column } from '#ui/components/DataTable';
import { useAccounts } from '#ui/hooks/useAccounts';
import { usePaged } from '#ui/hooks/usePaged';
import { formatDateTime } from '#ui/utils';

const PAGE_SIZE = 20;

function Payments() {
  const accounts = useAccounts();
  const [success, setSuccess] = createSignal<string | null>(null);
  const [fanId, setFanId] = createSignal(0);
  const [amount, setAmount] = createSignal(0);
  const [walletBalance, setWalletBalance] = createSignal<number | null>(null);

  const accountId = () => accounts.selected() ?? 0;
  const orders = usePaged<OrderItem>((page, pageSize) => listOrders(page, pageSize, accountId()), PAGE_SIZE);
  const withdraws = usePaged<WithdrawItem>((page, pageSize) => listWithdraws(page, pageSize, accountId()), PAGE_SIZE);

  const onAccountChange = (id: number) => {
    accounts.setSelected(id);
    setWalletBalance(null);
    void orders.reload(1);
    void withdraws.reload(1);
    void refreshWallet(id);
  };

  const refreshWallet = async (id: number) => {
    if (id === 0) return;
    try {
      const w = await getWallet(id, fanId());
      setWalletBalance(w.balance);
    } catch {
      setWalletBalance(0);
    }
  };

  const onRecharge = async (e: SubmitEvent) => {
    e.preventDefault();
    if (accountId() === 0) return;
    setSuccess(null);
    try {
      const order = await createRechargeOrder({ account_id: accountId(), fan_id: fanId(), amount: amount() });
      // 当前 channel=mock：立即标记已支付入账。
      await completeRecharge(order.order_no);
      setSuccess(`充值成功，订单 ${order.order_no}`);
      void refreshWallet(accountId());
      void orders.reload(1);
    } catch (err) {
      window.alert(toApiError(err).message);
    }
  };

  const onWithdraw = async (e: SubmitEvent) => {
    e.preventDefault();
    if (accountId() === 0) return;
    setSuccess(null);
    try {
      await createWithdraw({ account_id: accountId(), fan_id: fanId(), amount: amount() });
      setSuccess('提现申请已提交');
      void withdraws.reload(1);
    } catch (err) {
      window.alert(toApiError(err).message);
    }
  };

  const orderColumns: Column<OrderItem>[] = [
    { key: 'order_no', title: '订单号', render: (o) => <span class="font-mono text-xs">{o.order_no}</span> },
    { key: 'amount', title: '金额(分)', render: (o) => <span class="font-medium">{(o.amount / 100).toFixed(2)} 元</span> },
    { key: 'channel', title: '渠道', render: (o) => <span class="badge badge-sm badge-ghost">{o.channel}</span> },
    {
      key: 'status',
      title: '状态',
      render: (o) => (
        <span class={`badge badge-sm ${o.status === 'paid' ? 'badge-success' : 'badge-outline'}`}>
          {o.status === 'paid' ? '已支付' : o.status}
        </span>
      ),
    },
    {
      key: 'created_at',
      title: '时间',
      render: (o) => <span class="text-sm text-base-content/70">{formatDateTime(o.created_at)}</span>,
    },
  ];

  const withdrawColumns: Column<WithdrawItem>[] = [
    { key: 'id', title: 'ID', render: (w) => <span class="font-mono text-xs">{w.id}</span> },
    { key: 'amount', title: '金额(分)', render: (w) => <span class="font-medium">{(w.amount / 100).toFixed(2)} 元</span> },
    { key: 'status', title: '状态', render: (w) => <span class="badge badge-sm badge-ghost">{w.status}</span> },
    {
      key: 'created_at',
      title: '时间',
      render: (w) => <span class="text-sm text-base-content/70">{formatDateTime(w.created_at)}</span>,
    },
  ];

  return (
    <div class="space-y-4">
      <div>
        <h2 class="text-xl font-semibold">充值支付</h2>
        <p class="text-sm text-base-content/60">会员充值（当前 channel=mock，下单即入账）与提现</p>
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

      <div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <form onSubmit={onRecharge} class="rounded-lg border border-base-300 bg-base-200/40 p-4 space-y-3">
          <div class="flex items-center justify-between">
            <span class="text-sm font-semibold">会员充值</span>
            <Show when={walletBalance() !== null}>
              <span class="badge badge-success">钱包余额：{(walletBalance() ?? 0) / 100} 元</span>
            </Show>
          </div>
          <div class="flex items-end gap-2">
            <label class="form-control">
              <span class="label-text mb-1">粉丝 ID</span>
              <input type="number" class="input input-bordered input-sm w-32" value={fanId()} onInput={(e) => setFanId(Number(e.currentTarget.value))} required />
            </label>
            <label class="form-control">
              <span class="label-text mb-1">金额（分）</span>
              <input type="number" class="input input-bordered input-sm w-32" value={amount()} onInput={(e) => setAmount(Number(e.currentTarget.value))} min={1} required />
            </label>
            <button type="submit" class="btn btn-primary btn-sm">
              充值
            </button>
          </div>
        </form>

        <form onSubmit={onWithdraw} class="rounded-lg border border-base-300 bg-base-200/40 p-4 space-y-3">
          <span class="text-sm font-semibold">申请提现</span>
          <div class="flex items-end gap-2">
            <label class="form-control">
              <span class="label-text mb-1">粉丝 ID</span>
              <input type="number" class="input input-bordered input-sm w-32" value={fanId()} onInput={(e) => setFanId(Number(e.currentTarget.value))} required />
            </label>
            <label class="form-control">
              <span class="label-text mb-1">金额（分）</span>
              <input type="number" class="input input-bordered input-sm w-32" value={amount()} onInput={(e) => setAmount(Number(e.currentTarget.value))} min={1} required />
            </label>
            <button type="submit" class="btn btn-outline btn-sm">
              提现
            </button>
          </div>
        </form>
      </div>

      <Show when={success()}>
        <div role="alert" class="alert alert-success py-2 text-sm">
          {success()}
        </div>
      </Show>

      <div>
        <h3 class="mb-2 text-sm font-semibold">充值订单</h3>
        <DataTable
          columns={orderColumns}
          rows={orders.items()}
          rowKey={(o) => o.id}
          total={orders.total()}
          page={orders.page()}
          totalPages={orders.totalPages()}
          loading={orders.loading()}
          error={orders.error()}
          emptyText="暂无订单"
          onPageChange={(p) => void orders.reload(p)}
        />
      </div>

      <div>
        <h3 class="mb-2 text-sm font-semibold">提现记录</h3>
        <DataTable
          columns={withdrawColumns}
          rows={withdraws.items()}
          rowKey={(w) => w.id}
          total={withdraws.total()}
          page={withdraws.page()}
          totalPages={withdraws.totalPages()}
          loading={withdraws.loading()}
          error={withdraws.error()}
          emptyText="暂无提现记录"
          onPageChange={(p) => void withdraws.reload(p)}
        />
      </div>
    </div>
  );
}

export default Payments;
