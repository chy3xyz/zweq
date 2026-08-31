import { createSignal } from 'solid-js';

import {
  distributeCommission,
  joinDistributor,
  listCommissions,
  listDistributors,
  withdrawCommission,
  type CommissionItem,
  type DistributorItem,
} from '#ui/api';
import AccountRequiredBanner from '#ui/components/AccountRequiredBanner';
import AdminCrudPage from '#ui/components/AdminCrudPage';
import DataTable, { type Column } from '#ui/components/DataTable';
import FormModal from '#ui/components/FormModal';
import SearchBar, { type SearchField, type SearchValues } from '#ui/components/SearchBar';
import { useAccountId, useFeedback, usePaged } from '#ui/hooks';
import { formatDateTime, intParam } from '#ui/utils';
import { fenToYuan, formatYuan, yuanToFen } from '#ui/utils/money';

const COMMISSION_FIELDS: SearchField[] = [
  { kind: 'text', key: 'keyword', label: '受益分销员 / 购买者', placeholder: '输入 openid' },
  {
    kind: 'select',
    key: 'level',
    label: '层级',
    options: [
      { value: '', label: '全部' },
      { value: '1', label: '一级' },
      { value: '2', label: '二级' },
      { value: '3', label: '三级' },
      { value: '0', label: '提现' },
    ],
  },
];

function Distribution() {
  const { accountId, ready, accountName } = useAccountId();
  const feedback = useFeedback();

  const [distKeyword, setDistKeyword] = createSignal<SearchValues>({});
  const [commissionFilters, setCommissionFilters] = createSignal<SearchValues>({});

  const [joinOpen, setJoinOpen] = createSignal(false);
  const [joinOpenid, setJoinOpenid] = createSignal('');
  const [parentOpenid, setParentOpenid] = createSignal('');
  const [distributeOpen, setDistributeOpen] = createSignal(false);
  const [buyerOpenid, setBuyerOpenid] = createSignal('');
  const [orderAmount, setOrderAmount] = createSignal('100.00');
  const [submitting, setSubmitting] = createSignal(false);
  const [error, setError] = createSignal<string | null>(null);

  const distributors = usePaged<DistributorItem>(
    (page, pageSize) =>
      listDistributors(
        accountId(),
        page,
        pageSize,
        distKeyword().keyword?.trim() ?? '',
        intParam(distKeyword().status, -1),
      ),
    20,
    () => [accountId(), distKeyword()],
  );

  const commissions = usePaged<CommissionItem>(
    (page, pageSize) =>
      listCommissions(
        accountId(),
        page,
        pageSize,
        commissionFilters().keyword?.trim() ?? '',
        intParam(commissionFilters().level, -1),
      ),
    20,
    () => [accountId(), commissionFilters()],
  );

  const onJoin = async () => {
    if (submitting()) return;
    setSubmitting(true);
    setError(null);
    try {
      await joinDistributor(accountId(), { openid: joinOpenid().trim(), parent_openid: parentOpenid().trim() });
      setJoinOpen(false);
      setJoinOpenid('');
      setParentOpenid('');
      feedback.toast('分销员已开通');
      void distributors.reload(1);
    } catch (err) {
      setError(err instanceof Error ? err.message : '开通失败，请稍后重试');
    } finally {
      setSubmitting(false);
    }
  };

  const onDistribute = async () => {
    if (submitting()) return;
    setSubmitting(true);
    setError(null);
    try {
      const result = await distributeCommission(accountId(), {
        buyer_openid: buyerOpenid().trim(),
        order_amount: yuanToFen(Number(orderAmount())),
      });
      setDistributeOpen(false);
      setBuyerOpenid('');
      feedback.toast(`分佣完成（${result.count} 笔）`);
      void Promise.all([distributors.refresh(), commissions.refresh()]);
    } catch (err) {
      setError(err instanceof Error ? err.message : '分佣失败，请稍后重试');
    } finally {
      setSubmitting(false);
    }
  };

  const onWithdraw = (row: DistributorItem) =>
    feedback.runAction({
      confirm: {
        title: '佣金提现',
        message: `确定为「${row.openid}」提现 ${formatYuan(row.commission_balance)} 吗？`,
      },
      action: () => withdrawCommission(accountId(), { openid: row.openid, amount: row.commission_balance }),
      success: '提现申请已提交',
      onDone: () => void Promise.all([distributors.refresh(), commissions.refresh()]),
    });

  const distColumns: Column<DistributorItem>[] = [
    { key: 'openid', title: '分销员', render: (r) => <span class="font-mono text-xs">{r.openid}</span> },
    {
      key: 'parent_openid',
      title: '上级',
      render: (r) =>
        r.parent_openid ? (
          <span class="font-mono text-xs">{r.parent_openid}</span>
        ) : (
          <span class="text-base-content/40">无</span>
        ),
    },
    {
      key: 'commission_balance',
      title: '佣金余额',
      render: (r) => <span class="font-semibold text-success">{formatYuan(r.commission_balance)}</span>,
    },
    {
      key: 'total_commission',
      title: '累计佣金',
      render: (r) => formatYuan(r.total_commission),
    },
    {
      key: 'created_at',
      title: '加盟时间',
      render: (r) => <span class="text-sm text-base-content/70">{formatDateTime(r.created_at)}</span>,
    },
  ];

  const commissionColumns: Column<CommissionItem>[] = [
    { key: 'openid', title: '受益分销员', render: (r) => <span class="font-mono text-xs">{r.openid}</span> },
    {
      key: 'source_openid',
      title: '购买者',
      render: (r) => <span class="font-mono text-xs">{r.source_openid || '提现'}</span>,
    },
    {
      key: 'level',
      title: '层级',
      render: (r) => (
        <span class="badge badge-sm badge-ghost">
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
          {formatYuan(r.amount)}
        </span>
      ),
    },
    {
      key: 'created_at',
      title: '时间',
      render: (r) => <span class="text-sm text-base-content/70">{formatDateTime(r.created_at)}</span>,
    },
  ];

  return (
    <div class="space-y-4">
      <AdminCrudPage
        title="分销管理"
        description={ready() ? `当前公众号：${accountName()}` : undefined}
        total={distributors.total()}
        onCreate={
          ready()
            ? () => {
                setError(null);
                setJoinOpen(true);
              }
            : undefined
        }
        createLabel="开通分销员"
        onRefresh={() => void distributors.refresh()}
        extra={
          <button
            type="button"
            class="btn btn-outline btn-sm"
            disabled={!ready()}
            onClick={() => {
              setError(null);
              setDistributeOpen(true);
            }}
          >
            模拟订单分佣
          </button>
        }
        search={
          <SearchBar
            fields={[
              { kind: 'text', key: 'keyword', label: '分销员 openid', placeholder: '输入 openid' },
              {
                kind: 'select',
                key: 'status',
                label: '状态',
                options: [
                  { value: '-1', label: '全部' },
                  { value: '1', label: '启用' },
                  { value: '0', label: '停用' },
                ],
              },
            ]}
            values={{ status: '-1' }}
            loading={distributors.loading()}
            onSearch={setDistKeyword}
          />
        }
      >
        <AccountRequiredBanner />

        <DataTable
          columns={distColumns}
          rows={distributors.items()}
          rowKey={(r) => r.id}
          total={distributors.total()}
          page={distributors.page()}
          totalPages={distributors.totalPages()}
          pageSize={distributors.pageSize()}
          loading={distributors.loading()}
          error={distributors.error()}
          emptyText="暂无分销员"
          onPageChange={(p) => void distributors.reload(p)}
          onPageSizeChange={(size) => distributors.setPageSize(size)}
          actions={(row) => (
            <button
              type="button"
              class="btn btn-ghost btn-xs text-primary"
              onClick={() => void onWithdraw(row)}
              disabled={row.commission_balance <= 0}
            >
              全额提现
            </button>
          )}
        />
      </AdminCrudPage>

      <section class="rounded-box border border-base-300 bg-base-100 p-4">
        <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
          <h3 class="text-lg font-semibold">佣金记录</h3>
          <button type="button" class="btn btn-ghost btn-sm" onClick={() => void commissions.refresh()}>
            刷新
          </button>
        </div>
        <div class="mb-4">
          <SearchBar fields={COMMISSION_FIELDS} loading={commissions.loading()} onSearch={setCommissionFilters} />
        </div>
        <DataTable
          columns={commissionColumns}
          rows={commissions.items()}
          rowKey={(r) => r.id}
          total={commissions.total()}
          page={commissions.page()}
          totalPages={commissions.totalPages()}
          pageSize={commissions.pageSize()}
          loading={commissions.loading()}
          error={commissions.error()}
          emptyText="暂无佣金记录"
          onPageChange={(p) => void commissions.reload(p)}
          onPageSizeChange={(size) => commissions.setPageSize(size)}
        />
      </section>

      <FormModal
        open={joinOpen()}
        title="开通分销员"
        onSubmit={onJoin}
        onClose={() => setJoinOpen(false)}
        submitting={submitting()}
        error={error()}
        size="sm"
      >
        <label class="form-control">
          <span class="label-text mb-1">分销员 openid</span>
          <input
            class="input input-bordered input-sm"
            value={joinOpenid()}
            onInput={(e) => setJoinOpenid(e.currentTarget.value)}
            required
          />
        </label>
        <label class="form-control">
          <span class="label-text mb-1">上级分销员 openid（可选）</span>
          <input
            class="input input-bordered input-sm"
            value={parentOpenid()}
            onInput={(e) => setParentOpenid(e.currentTarget.value)}
          />
        </label>
      </FormModal>

      <FormModal
        open={distributeOpen()}
        title="模拟订单分佣"
        description="按三级分销比例 10% / 5% / 3% 计算"
        onSubmit={onDistribute}
        onClose={() => setDistributeOpen(false)}
        submitting={submitting()}
        error={error()}
        submitLabel="分佣"
        size="sm"
      >
        <label class="form-control">
          <span class="label-text mb-1">购买者 openid</span>
          <input
            class="input input-bordered input-sm"
            value={buyerOpenid()}
            onInput={(e) => setBuyerOpenid(e.currentTarget.value)}
            required
          />
        </label>
        <label class="form-control">
          <span class="label-text mb-1">订单金额（元）</span>
          <input
            class="input input-bordered input-sm"
            type="number"
            step="0.01"
            min="0"
            value={orderAmount()}
            onInput={(e) => setOrderAmount(e.currentTarget.value)}
            required
          />
        </label>
        <p class="text-xs text-base-content/50">折合 {fenToYuan(yuanToFen(Number(orderAmount() || 0)))} 元</p>
      </FormModal>
    </div>
  );
}

export default Distribution;
