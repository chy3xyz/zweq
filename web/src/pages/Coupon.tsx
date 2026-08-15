import { For, Show, createSignal } from 'solid-js';

import {
  claimCoupon,
  createCoupon,
  deleteCoupon,
  listCoupons,
  listCouponUsers,
  useCoupon,
  toApiError,
  type CouponItem,
  type CouponUserItem,
} from '#ui/api';
import DataTable, { type Column } from '#ui/components/DataTable';
import { useAccounts } from '#ui/hooks/useAccounts';
import { usePaged } from '#ui/hooks/usePaged';
import { formatDateTime } from '#ui/utils';

const PAGE_SIZE = 20;

function Coupon() {
  const accounts = useAccounts();
  const [success, setSuccess] = createSignal<string | null>(null);
  const [error, setError] = createSignal<string | null>(null);
  const [title, setTitle] = createSignal('');
  const [amount, setAmount] = createSignal(1000);
  const [minAmount, setMinAmount] = createSignal(0);
  const [total, setTotal] = createSignal(0);
  const [claimOpenid, setClaimOpenid] = createSignal('');
  const [useCode, setUseCode] = createSignal('');

  const accountId = () => accounts.selected() ?? 0;
  const paged = usePaged<CouponItem>((page, pageSize) => listCoupons(accountId(), page, pageSize), PAGE_SIZE);
  const users = usePaged<CouponUserItem>(
    (page, pageSize) => listCouponUsers(accountId(), page, pageSize),
    PAGE_SIZE,
  );

  const columns: Column<CouponItem>[] = [
    { key: 'title', title: '券名', render: (r) => <span class="font-medium">{r.title}</span> },
    { key: 'amount', title: '面额(分)', render: (r) => <span>{r.amount}</span> },
    { key: 'min_amount', title: '门槛(分)', render: (r) => <span>{r.min_amount}</span> },
    { key: 'total', title: '总量', render: (r) => <span>{r.total === 0 ? '不限' : r.total}</span> },
    {
      key: 'created_at',
      title: '创建时间',
      render: (r) => <span class="text-sm text-base-content/70">{formatDateTime(r.created_at)}</span>,
    },
  ];

  const userColumns: Column<CouponUserItem>[] = [
    { key: 'openid', title: '粉丝', render: (r) => <span class="font-mono text-xs">{r.openid}</span> },
    { key: 'code', title: '券码', render: (r) => <span class="font-mono text-xs">{r.code}</span> },
    {
      key: 'status',
      title: '状态',
      render: (r) => (
        <span class={r.status === 'unused' ? 'text-success' : 'text-base-content/50'}>
          {r.status === 'unused' ? '未用' : r.status === 'used' ? '已用' : '过期'}
        </span>
      ),
    },
    {
      key: 'created_at',
      title: '领取时间',
      render: (r) => <span class="text-sm text-base-content/70">{formatDateTime(r.created_at)}</span>,
    },
  ];

  const onAccountChange = (id: number) => {
    accounts.setSelected(id);
    void paged.reload(1);
    void users.reload(1);
  };

  const onCreate = async (e: SubmitEvent) => {
    e.preventDefault();
    if (accountId() === 0) return;
    setError(null);
    setSuccess(null);
    try {
      await createCoupon({
        account_id: accountId(),
        title: title().trim(),
        amount: amount(),
        min_amount: minAmount(),
        total: total(),
        per_user: 1,
      });
      setTitle('');
      setSuccess('优惠券已创建');
      void paged.reload(1);
    } catch (err) {
      setError(toApiError(err).message);
    }
  };

  const onClaim = async (id: number) => {
    const openid = claimOpenid().trim();
    if (!openid) {
      setError('请输入粉丝 openid');
      return;
    }
    try {
      const r = await claimCoupon(id, openid);
      setSuccess(`领取成功：${r.code}`);
      void users.reload(1);
    } catch (err) {
      setError(toApiError(err).message);
    }
  };

  const onUse = async () => {
    const code = useCode().trim();
    if (!code) return;
    try {
      await useCoupon(code);
      setSuccess('已核销');
      setUseCode('');
      void users.reload(1);
    } catch (err) {
      setError(toApiError(err).message);
    }
  };

  const onDelete = async (id: number) => {
    try {
      await deleteCoupon(id);
      setSuccess('已删除');
      void paged.reload(1);
    } catch (err) {
      setError(toApiError(err).message);
    }
  };

  return (
    <div class="p-6 space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">优惠券</h1>
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
        <h2 class="font-semibold">新建优惠券</h2>
        <div class="flex flex-wrap gap-2">
          <input
            class="input input-bordered flex-1 min-w-40"
            placeholder="券名"
            value={title()}
            onInput={(e) => setTitle(e.currentTarget.value)}
          />
          <input
            class="input input-bordered w-28"
            type="number"
            placeholder="面额(分)"
            value={amount()}
            onInput={(e) => setAmount(Number(e.currentTarget.value))}
          />
          <input
            class="input input-bordered w-28"
            type="number"
            placeholder="门槛(分)"
            value={minAmount()}
            onInput={(e) => setMinAmount(Number(e.currentTarget.value))}
          />
          <input
            class="input input-bordered w-28"
            type="number"
            placeholder="总量(0不限)"
            value={total()}
            onInput={(e) => setTotal(Number(e.currentTarget.value))}
          />
          <button class="btn btn-primary" type="submit">
            创建
          </button>
        </div>
      </form>

      <div class="card bg-base-200 p-4 space-y-3">
        <h2 class="font-semibold">手动领券 / 核销</h2>
        <div class="flex flex-wrap gap-2">
          <input
            class="input input-bordered flex-1 min-w-40"
            placeholder="领券 openid（先填再点券「发券」）"
            value={claimOpenid()}
            onInput={(e) => setClaimOpenid(e.currentTarget.value)}
          />
          <input
            class="input input-bordered w-48"
            placeholder="券码（核销）"
            value={useCode()}
            onInput={(e) => setUseCode(e.currentTarget.value)}
          />
          <button class="btn btn-secondary" onClick={() => void onUse()}>
            核销
          </button>
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
        emptyText="暂无优惠券"
        onPageChange={(p) => void paged.reload(p)}
        actions={(row) => (
          <div class="flex gap-1">
            <button class="btn btn-xs btn-outline btn-primary" onClick={() => void onClaim(row.id)}>
              发券
            </button>
            <button class="btn btn-xs btn-outline btn-error" onClick={() => void onDelete(row.id)}>
              删除
            </button>
          </div>
        )}
      />

      <div class="card bg-base-200 p-4">
        <h2 class="font-semibold mb-3">领取记录</h2>
        <DataTable
          columns={userColumns}
          rows={users.items()}
          rowKey={(r) => r.id}
          total={users.total()}
          page={users.page()}
          totalPages={users.totalPages()}
          loading={users.loading()}
          error={users.error()}
          emptyText="暂无领取记录"
          onPageChange={(p) => void users.reload(p)}
        />
      </div>
    </div>
  );
}

export default Coupon;
