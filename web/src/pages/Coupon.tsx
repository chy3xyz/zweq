import { createSignal } from 'solid-js';

import {
  claimCoupon,
  createCoupon,
  deleteCoupon,
  listCoupons,
  listCouponUsers,
  setCouponStatus,
  useCoupon,
  type CouponItem,
  type CouponUserItem,
} from '#ui/api';
import AccountRequiredBanner from '#ui/components/AccountRequiredBanner';
import AdminCrudPage from '#ui/components/AdminCrudPage';
import DataTable, { type Column } from '#ui/components/DataTable';
import FormModal from '#ui/components/FormModal';
import SearchBar, { type SearchField, type SearchValues } from '#ui/components/SearchBar';
import { useAccountId, useFeedback, usePaged } from '#ui/hooks';
import { formatDateTime, intParam } from '#ui/utils';
import { fenToYuan, formatYuan } from '#ui/utils/money';

const COUPON_FIELDS: SearchField[] = [
  { kind: 'text', key: 'keyword', label: '券名', placeholder: '输入券名关键字' },
  {
    kind: 'select',
    key: 'status',
    label: '状态',
    options: [
      { value: '-1', label: '全部' },
      { value: '1', label: '上架' },
      { value: '0', label: '下架' },
    ],
  },
];

const USER_FIELDS: SearchField[] = [
  { kind: 'text', key: 'keyword', label: '粉丝 / 券码', placeholder: '输入 openid 或券码' },
  {
    kind: 'select',
    key: 'status',
    label: '状态',
    options: [
      { value: '', label: '全部' },
      { value: 'unused', label: '未用' },
      { value: 'used', label: '已用' },
      { value: 'expired', label: '已过期' },
    ],
  },
];

function Coupon() {
  const { accountId, ready, accountName } = useAccountId();
  const feedback = useFeedback();

  const [keyword, setKeyword] = createSignal<SearchValues>({});
  const [userFilters, setUserFilters] = createSignal<SearchValues>({});

  const [createOpen, setCreateOpen] = createSignal(false);
  const [verifyOpen, setVerifyOpen] = createSignal(false);
  const [claimTarget, setClaimTarget] = createSignal<CouponItem | null>(null);
  const [openid, setOpenid] = createSignal('');
  const [useCode, setUseCode] = createSignal('');
  const [submitting, setSubmitting] = createSignal(false);
  const [error, setError] = createSignal<string | null>(null);

  const [title, setTitle] = createSignal('');
  const [amount, setAmount] = createSignal('10.00');
  const [minAmount, setMinAmount] = createSignal('0.00');
  const [total, setTotal] = createSignal(0);

  const paged = usePaged<CouponItem>(
    (page, pageSize) =>
      listCoupons(
        accountId(),
        page,
        pageSize,
        keyword().keyword?.trim() ?? '',
        intParam(keyword().status, -1),
      ),
    20,
    () => [accountId(), keyword()],
  );

  const users = usePaged<CouponUserItem>(
    (page, pageSize) =>
      listCouponUsers(
        accountId(),
        page,
        pageSize,
        userFilters().keyword?.trim() ?? '',
        userFilters().status ?? '',
      ),
    20,
    () => [accountId(), userFilters()],
  );

  const openCreate = () => {
    setError(null);
    setTitle('');
    setAmount('10.00');
    setMinAmount('0.00');
    setTotal(0);
    setCreateOpen(true);
  };

  const onCreate = async () => {
    if (submitting()) return;
    setSubmitting(true);
    setError(null);
    try {
      await createCoupon({
        account_id: accountId(),
        title: title().trim(),
        amount: Math.round(Number(amount()) * 100),
        min_amount: Math.round(Number(minAmount()) * 100),
        total: total(),
        per_user: 1,
        status: 1,
      });
      setCreateOpen(false);
      feedback.toast('优惠券已创建');
      void paged.reload(1);
    } catch (err) {
      setError(err instanceof Error ? err.message : '创建失败，请稍后重试');
    } finally {
      setSubmitting(false);
    }
  };

  const onClaim = async () => {
    const coupon = claimTarget();
    if (submitting() || !coupon) return;
    setSubmitting(true);
    setError(null);
    try {
      const result = await claimCoupon(coupon.id, openid().trim());
      setClaimTarget(null);
      setOpenid('');
      feedback.toast(`发券成功：${result.code}`);
      void users.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : '发券失败，请稍后重试');
    } finally {
      setSubmitting(false);
    }
  };

  const onVerify = async () => {
    if (submitting()) return;
    setSubmitting(true);
    setError(null);
    try {
      await useCoupon(useCode().trim());
      setVerifyOpen(false);
      setUseCode('');
      feedback.toast('已核销');
      void users.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : '核销失败，请稍后重试');
    } finally {
      setSubmitting(false);
    }
  };

  const onToggleStatus = (row: CouponItem) => {
    const next = row.status === 1 ? 0 : 1;
    return feedback.runAction({
      confirm:
        next === 0
          ? { title: '下架优惠券', message: `确定下架优惠券「${row.title}」吗？`, danger: true }
          : undefined,
      action: () => setCouponStatus(row.id, next),
      success: next === 1 ? '优惠券已上架' : '优惠券已下架',
      onDone: () => void paged.refresh(),
    });
  };

  const onDelete = (row: CouponItem) =>
    feedback.runAction({
      confirm: { title: '删除优惠券', message: `确定删除优惠券「${row.title}」吗？`, danger: true },
      action: () => deleteCoupon(row.id),
      success: '优惠券已删除',
      onDone: () => void paged.refresh(),
    });

  const columns: Column<CouponItem>[] = [
    { key: 'title', title: '券名', render: (r) => <span class="font-medium">{r.title}</span> },
    {
      key: 'amount',
      title: '面额',
      render: (r) => <span class="font-semibold text-error">{formatYuan(r.amount)}</span>,
    },
    {
      key: 'min_amount',
      title: '使用门槛',
      render: (r) => (r.min_amount > 0 ? formatYuan(r.min_amount) : <span class="text-base-content/40">无门槛</span>),
    },
    { key: 'total', title: '总量', render: (r) => (r.total === 0 ? '不限' : r.total) },
    {
      key: 'status',
      title: '状态',
      render: (r) => (
        <span class={`badge badge-sm ${r.status === 1 ? 'badge-success' : 'badge-ghost'}`}>
          {r.status === 1 ? '上架' : '下架'}
        </span>
      ),
    },
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
        <span class={`badge badge-sm ${statusClass(r.status)}`}>{statusLabel(r.status)}</span>
      ),
    },
    {
      key: 'created_at',
      title: '领取时间',
      render: (r) => <span class="text-sm text-base-content/70">{formatDateTime(r.created_at)}</span>,
    },
  ];

  return (
    <div class="space-y-4">
      <AdminCrudPage
        title="优惠券"
        description={ready() ? `当前公众号：${accountName()}` : undefined}
        total={paged.total()}
        onCreate={ready() ? openCreate : undefined}
        createLabel="新增优惠券"
        onRefresh={() => void paged.refresh()}
        extra={
          <button
            type="button"
            class="btn btn-outline btn-sm"
            disabled={!ready()}
            onClick={() => {
              setError(null);
              setVerifyOpen(true);
            }}
          >
            核销券码
          </button>
        }
        search={
          <SearchBar
            fields={COUPON_FIELDS}
            values={{ status: '-1' }}
            loading={paged.loading()}
            onSearch={setKeyword}
          />
        }
      >
        <AccountRequiredBanner />

        <DataTable
          columns={columns}
          rows={paged.items()}
          rowKey={(r) => r.id}
          total={paged.total()}
          page={paged.page()}
          totalPages={paged.totalPages()}
          pageSize={paged.pageSize()}
          loading={paged.loading()}
          error={paged.error()}
          emptyText="暂无优惠券"
          onPageChange={(p) => void paged.reload(p)}
          onPageSizeChange={(size) => paged.setPageSize(size)}
          actions={(row) => (
            <>
              <button
                type="button"
                class="btn btn-ghost btn-xs text-primary"
                onClick={() => {
                  setError(null);
                  setOpenid('');
                  setClaimTarget(row);
                }}
              >
                发券
              </button>
              <button
                type="button"
                class="btn btn-ghost btn-xs"
                onClick={() => void onToggleStatus(row)}
              >
                {row.status === 1 ? '下架' : '上架'}
              </button>
              <button type="button" class="btn btn-ghost btn-xs text-error" onClick={() => void onDelete(row)}>
                删除
              </button>
            </>
          )}
        />
      </AdminCrudPage>

      <section class="rounded-box border border-base-300 bg-base-100 p-4">
        <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
          <h3 class="text-lg font-semibold">领取记录</h3>
          <button type="button" class="btn btn-ghost btn-sm" onClick={() => void users.refresh()}>
            刷新
          </button>
        </div>
        <div class="mb-4">
          <SearchBar fields={USER_FIELDS} loading={users.loading()} onSearch={setUserFilters} />
        </div>
        <DataTable
          columns={userColumns}
          rows={users.items()}
          rowKey={(r) => r.id}
          total={users.total()}
          page={users.page()}
          totalPages={users.totalPages()}
          pageSize={users.pageSize()}
          loading={users.loading()}
          error={users.error()}
          emptyText="暂无领取记录"
          onPageChange={(p) => void users.reload(p)}
          onPageSizeChange={(size) => users.setPageSize(size)}
        />
      </section>

      <FormModal
        open={createOpen()}
        title="新增优惠券"
        onSubmit={onCreate}
        onClose={() => setCreateOpen(false)}
        submitting={submitting()}
        error={error()}
      >
        <label class="form-control">
          <span class="label-text mb-1">券名</span>
          <input
            class="input input-bordered input-sm"
            placeholder="例如：满 100 减 10"
            value={title()}
            onInput={(e) => setTitle(e.currentTarget.value)}
            required
          />
        </label>
        <div class="grid grid-cols-2 gap-3">
          <label class="form-control">
            <span class="label-text mb-1">面额（元）</span>
            <input
              class="input input-bordered input-sm"
              type="number"
              step="0.01"
              min="0"
              value={amount()}
              onInput={(e) => setAmount(e.currentTarget.value)}
              required
            />
          </label>
          <label class="form-control">
            <span class="label-text mb-1">使用门槛（元）</span>
            <input
              class="input input-bordered input-sm"
              type="number"
              step="0.01"
              min="0"
              value={minAmount()}
              onInput={(e) => setMinAmount(e.currentTarget.value)}
            />
          </label>
        </div>
        <label class="form-control">
          <span class="label-text mb-1">发放总量（0 表示不限）</span>
          <input
            class="input input-bordered input-sm"
            type="number"
            min="0"
            value={total()}
            onInput={(e) => setTotal(Number(e.currentTarget.value) || 0)}
          />
        </label>
        <p class="text-xs text-base-content/50">
          面额 {fenToYuan(Math.round(Number(amount() || 0) * 100))} 元，每人限领 1 张
        </p>
      </FormModal>

      <FormModal
        open={claimTarget() != null}
        title="发放优惠券"
        description={claimTarget() ? `将「${claimTarget()!.title}」发放给指定粉丝` : undefined}
        onSubmit={onClaim}
        onClose={() => setClaimTarget(null)}
        submitting={submitting()}
        error={error()}
        submitLabel="发放"
        size="sm"
      >
        <label class="form-control">
          <span class="label-text mb-1">粉丝 openid</span>
          <input
            class="input input-bordered input-sm"
            placeholder="输入粉丝 openid"
            value={openid()}
            onInput={(e) => setOpenid(e.currentTarget.value)}
            required
          />
        </label>
      </FormModal>

      <FormModal
        open={verifyOpen()}
        title="核销券码"
        onSubmit={onVerify}
        onClose={() => setVerifyOpen(false)}
        submitting={submitting()}
        error={error()}
        submitLabel="核销"
        size="sm"
      >
        <label class="form-control">
          <span class="label-text mb-1">券码</span>
          <input
            class="input input-bordered input-sm"
            placeholder="输入用户券码"
            value={useCode()}
            onInput={(e) => setUseCode(e.currentTarget.value)}
            required
          />
        </label>
      </FormModal>
    </div>
  );
}

function statusLabel(status: CouponUserItem['status']): string {
  return status === 'unused' ? '未使用' : status === 'used' ? '已使用' : '已过期';
}

function statusClass(status: CouponUserItem['status']): string {
  return status === 'unused' ? 'badge-success' : status === 'used' ? 'badge-ghost' : 'badge-warning';
}

export default Coupon;
