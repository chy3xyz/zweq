import { For, Show, createSignal } from 'solid-js';

import {
  distributeCommission,
  joinDistributor,
  listCommissions,
  listDistributors,
  toApiError,
  withdrawCommission,
  type CommissionItem,
  type DistributorItem,
} from '#ui/api';
import DataTable, { type Column } from '#ui/components/DataTable';
import { useAccounts } from '#ui/hooks/useAccounts';
import { usePaged } from '#ui/hooks/usePaged';
import { formatDateTime } from '#ui/utils';

const PAGE_SIZE = 20;

function Distribution() {
  const accounts = useAccounts();
  const [success, setSuccess] = createSignal<string | null>(null);
  const [error, setError] = createSignal<string | null>(null);
  const [joinOpenid, setJoinOpenid] = createSignal('');
  const [parentOpenid, setParentOpenid] = createSignal('');
  const [buyerOpenid, setBuyerOpenid] = createSignal('');
  const [orderAmount, setOrderAmount] = createSignal(10000);

  const accountId = () => accounts.selected() ?? 0;
  const distributors = usePaged<DistributorItem>(
    (page, pageSize) => listDistributors(accountId(), page, pageSize),
    PAGE_SIZE,
  );
  const commissions = usePaged<CommissionItem>(
    (page, pageSize) => listCommissions(accountId(), page, pageSize),
    PAGE_SIZE,
  );

  const distColumns: Column<DistributorItem>[] = [
    { key: 'openid', title: '分销员', render: (r) => <span class="font-mono text-xs">{r.openid}</span> },
    {
      key: 'parent_openid',
      title: '上级',
      render: (r) => (
        <span class={r.parent_openid ? 'font-mono text-xs' : 'text-base-content/40'}>
          {r.parent_openid || '无'}
        </span>
      ),
    },
    {
      key: 'commission_balance',
      title: '佣金余额',
      render: (r) => <span class="text-success font-semibold">{(r.commission_balance / 100).toFixed(2)} 元</span>,
    },
    { key: 'total_commission', title: '累计佣金', render: (r) => <span>{(r.total_commission / 100).toFixed(2)} 元</span> },
    {
      key: 'created_at',
      title: '加盟时间',
      render: (r) => <span class="text-sm text-base-content/70">{formatDateTime(r.created_at)}</span>,
    },
  ];

  const commissionColumns: Column<CommissionItem>[] = [
    { key: 'openid', title: '受益分销员', render: (r) => <span class="font-mono text-xs">{r.openid}</span> },
    { key: 'source_openid', title: '购买者', render: (r) => <span class="font-mono text-xs">{r.source_openid || '提现'}</span> },
    {
      key: 'level',
      title: '层级',
      render: (r) => (
        <span>
          {r.level === 0 ? '提现' : r.level === 1 ? '一级' : r.level === 2 ? '二级' : '三级'}
        </span>
      ),
    },
    {
      key: 'amount',
      title: '金额',
      render: (r) => (
        <span class={r.amount > 0 ? 'text-success' : 'text-error'}>
          {r.amount > 0 ? '+' : ''}
          {(r.amount / 100).toFixed(2)} 元
        </span>
      ),
    },
  ];

  const onAccountChange = (id: number) => {
    accounts.setSelected(id);
    void distributors.reload(1);
    void commissions.reload(1);
  };

  const onJoin = async () => {
    const openid = joinOpenid().trim();
    if (!openid) return;
    try {
      await joinDistributor(accountId(), { openid, parent_openid: parentOpenid().trim() });
      setJoinOpenid('');
      setParentOpenid('');
      setSuccess('分销员已开通');
      void distributors.reload(1);
    } catch (err) {
      setError(toApiError(err).message);
    }
  };

  const onDistribute = async () => {
    const buyer = buyerOpenid().trim();
    if (!buyer) return;
    try {
      const r = await distributeCommission(accountId(), { buyer_openid: buyer, order_amount: orderAmount() });
      setSuccess(`分佣完成（${r.count} 笔）`);
      void distributors.reload(1);
      void commissions.reload(1);
    } catch (err) {
      setError(toApiError(err).message);
    }
  };

  const onWithdraw = async (openid: string, amount: number) => {
    try {
      await withdrawCommission(accountId(), { openid, amount });
      setSuccess(`提现申请已提交（${(amount / 100).toFixed(2)} 元）`);
      void distributors.reload(1);
      void commissions.reload(1);
    } catch (err) {
      setError(toApiError(err).message);
    }
  };

  return (
    <div class="p-6 space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">分销</h1>
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

      <div class="grid md:grid-cols-2 gap-4">
        <form onSubmit={(e) => { e.preventDefault(); void onJoin(); }} class="card bg-base-200 p-4 space-y-2">
          <h2 class="font-semibold">开通分销员</h2>
          <input
            class="input input-bordered"
            placeholder="分销员 openid"
            value={joinOpenid()}
            onInput={(e) => setJoinOpenid(e.currentTarget.value)}
          />
          <input
            class="input input-bordered"
            placeholder="上级分销员 openid（可选）"
            value={parentOpenid()}
            onInput={(e) => setParentOpenid(e.currentTarget.value)}
          />
          <button class="btn btn-primary" type="submit">
            开通
          </button>
        </form>

        <form onSubmit={(e) => { e.preventDefault(); void onDistribute(); }} class="card bg-base-200 p-4 space-y-2">
          <h2 class="font-semibold">模拟订单分佣（三级 10%/5%/3%）</h2>
          <input
            class="input input-bordered"
            placeholder="购买者 openid"
            value={buyerOpenid()}
            onInput={(e) => setBuyerOpenid(e.currentTarget.value)}
          />
          <input
            class="input input-bordered"
            type="number"
            placeholder="订单金额(分)"
            value={orderAmount()}
            onInput={(e) => setOrderAmount(Number(e.currentTarget.value))}
          />
          <button class="btn btn-secondary" type="submit">
            分佣
          </button>
        </form>
      </div>

      <DataTable
        columns={distColumns}
        rows={distributors.items()}
        rowKey={(r) => r.id}
        total={distributors.total()}
        page={distributors.page()}
        totalPages={distributors.totalPages()}
        loading={distributors.loading()}
        error={distributors.error()}
        emptyText="暂无分销员"
        onPageChange={(p) => void distributors.reload(p)}
        actions={(row) => (
          <button
            class="btn btn-xs btn-outline btn-primary"
            onClick={() => void onWithdraw(row.openid, row.commission_balance)}
            disabled={row.commission_balance <= 0}
          >
            全额提现
          </button>
        )}
      />

      <div class="card bg-base-200 p-4">
        <h2 class="font-semibold mb-3">佣金记录</h2>
        <DataTable
          columns={commissionColumns}
          rows={commissions.items()}
          rowKey={(r) => r.id}
          total={commissions.total()}
          page={commissions.page()}
          totalPages={commissions.totalPages()}
          loading={commissions.loading()}
          error={commissions.error()}
          emptyText="暂无佣金记录"
          onPageChange={(p) => void commissions.reload(p)}
        />
      </div>
    </div>
  );
}

export default Distribution;
