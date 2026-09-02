import { Show, createEffect, createSignal } from 'solid-js';

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
import AccountRequiredBanner from '#ui/components/AccountRequiredBanner';
import AdminCrudPage from '#ui/components/AdminCrudPage';
import DataTable, { type Column } from '#ui/components/DataTable';
import FormField from '#ui/components/FormField';
import FormModal from '#ui/components/FormModal';
import { Tabs } from '#ui/components';
import { useAccountId } from '#ui/hooks/useAccountId';
import { useFeedback, usePaged } from '#ui/hooks';
import { formatDateTime } from '#ui/utils';

const PAGE_SIZE = 20;
const TABS = ['充值支付', '提现管理'] as const;

const ORDER_STATUS_LABEL: Record<string, string> = {
  pending: '待支付',
  paid: '已支付',
  closed: '已关闭',
};

const ORDER_STATUS_BADGE: Record<string, string> = {
  pending: 'badge-warning',
  paid: 'badge-success',
  closed: 'badge-outline',
};

const WITHDRAW_STATUS_LABEL: Record<string, string> = {
  pending: '待处理',
  approved: '已批准',
  rejected: '已拒绝',
  paid: '已打款',
};

const WITHDRAW_STATUS_BADGE: Record<string, string> = {
  pending: 'badge-warning',
  approved: 'badge-info',
  rejected: 'badge-error',
  paid: 'badge-success',
};

function RechargeModal(props: {
  open: boolean;
  accountId: number;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [fanId, setFanId] = createSignal(0);
  const [amount, setAmount] = createSignal(0);
  const [walletBalance, setWalletBalance] = createSignal<number | null>(null);
  const [submitting, setSubmitting] = createSignal(false);
  const [error, setError] = createSignal<string | null>(null);

  const refreshWallet = async () => {
    if (!props.open || props.accountId === 0) {
      setWalletBalance(null);
      return;
    }
    try {
      const w = await getWallet(props.accountId, fanId());
      setWalletBalance(w.balance);
    } catch {
      setWalletBalance(0);
    }
  };

  createEffect(() => {
    if (props.open) {
      setFanId(0);
      setAmount(0);
      setError(null);
    }
  });

  createEffect(() => {
    void refreshWallet();
  });

  const onSubmit = async (e: SubmitEvent) => {
    e.preventDefault();
    if (props.accountId === 0 || submitting()) return;
    setSubmitting(true);
    setError(null);
    try {
      const order = await createRechargeOrder({ account_id: props.accountId, fan_id: fanId(), amount: amount() });
      await completeRecharge(order.order_no);
      await refreshWallet();
      props.onSaved();
      props.onClose();
    } catch (err) {
      setError(toApiError(err).message);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <FormModal
      open={props.open}
      title="会员充值"
      description="当前 channel=mock，提交后自动标记已支付入账。"
      onClose={props.onClose}
      onSubmit={onSubmit}
      submitting={submitting()}
      error={error()}
      submitLabel="充值"
    >
      <FormField label="粉丝 ID" required>
        <input
          type="number"
          class="input input-bordered w-full"
          value={fanId()}
          onInput={(e) => setFanId(Number(e.currentTarget.value))}
          min={0}
          required
        />
      </FormField>
      <FormField
        label="金额（分）"
        required
        labelExtra={
          <Show when={walletBalance() !== null}>
            <span class="badge badge-success badge-sm">
              当前余额：{(walletBalance() ?? 0) / 100} 元
            </span>
          </Show>
        }
      >
        <input
          type="number"
          class="input input-bordered w-full"
          value={amount()}
          onInput={(e) => setAmount(Number(e.currentTarget.value))}
          min={1}
          required
        />
      </FormField>
    </FormModal>
  );
}

function WithdrawModal(props: {
  open: boolean;
  accountId: number;
  onClose: () => void;
  onSaved: () => void;
}) {
  const feedback = useFeedback();
  const [fanId, setFanId] = createSignal(0);
  const [amount, setAmount] = createSignal(0);
  const [submitting, setSubmitting] = createSignal(false);
  const [error, setError] = createSignal<string | null>(null);

  createEffect(() => {
    if (props.open) {
      setFanId(0);
      setAmount(0);
      setError(null);
    }
  });

  const onSubmit = async (e: SubmitEvent) => {
    e.preventDefault();
    if (props.accountId === 0 || submitting()) return;
    setSubmitting(true);
    setError(null);
    try {
      await createWithdraw({ account_id: props.accountId, fan_id: fanId(), amount: amount() });
      feedback.toast('提现申请已提交', 'success');
      props.onSaved();
      props.onClose();
    } catch (err) {
      setError(toApiError(err).message);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <FormModal
      open={props.open}
      title="申请提现"
      onClose={props.onClose}
      onSubmit={onSubmit}
      submitting={submitting()}
      error={error()}
      submitLabel="提交申请"
    >
      <FormField label="粉丝 ID" required>
        <input
          type="number"
          class="input input-bordered w-full"
          value={fanId()}
          onInput={(e) => setFanId(Number(e.currentTarget.value))}
          min={0}
          required
        />
      </FormField>
      <FormField label="金额（分）" required>
        <input
          type="number"
          class="input input-bordered w-full"
          value={amount()}
          onInput={(e) => setAmount(Number(e.currentTarget.value))}
          min={1}
          required
        />
      </FormField>
    </FormModal>
  );
}

function Payments() {
  const feedback = useFeedback();
  const { accountId } = useAccountId();
  const [tab, setTab] = createSignal<(typeof TABS)[number]>('充值支付');
  const [rechargeOpen, setRechargeOpen] = createSignal(false);
  const [withdrawOpen, setWithdrawOpen] = createSignal(false);

  const orders = usePaged<OrderItem>(
    (page, pageSize) => listOrders(page, pageSize, accountId()),
    PAGE_SIZE,
    accountId,
  );
  const withdraws = usePaged<WithdrawItem>(
    (page, pageSize) => listWithdraws(page, pageSize, accountId()),
    PAGE_SIZE,
    accountId,
  );

  const orderColumns: Column<OrderItem>[] = [
    { key: 'order_no', title: '订单号', render: (o) => <span class="font-mono text-xs">{o.order_no}</span> },
    { key: 'amount', title: '金额(分)', render: (o) => <span class="font-medium">{(o.amount / 100).toFixed(2)} 元</span> },
    { key: 'channel', title: '渠道', render: (o) => <span class="badge badge-sm badge-ghost">{o.channel}</span> },
    {
      key: 'status',
      title: '状态',
      render: (o) => (
        <span class={`badge badge-sm ${ORDER_STATUS_BADGE[o.status] ?? 'badge-ghost'}`}>
          {ORDER_STATUS_LABEL[o.status] ?? o.status}
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
    {
      key: 'status',
      title: '状态',
      render: (w) => (
        <span class={`badge badge-sm ${WITHDRAW_STATUS_BADGE[w.status] ?? 'badge-ghost'}`}>
          {WITHDRAW_STATUS_LABEL[w.status] ?? w.status}
        </span>
      ),
    },
    {
      key: 'created_at',
      title: '时间',
      render: (w) => <span class="text-sm text-base-content/70">{formatDateTime(w.created_at)}</span>,
    },
  ];

  const onRechargeSaved = () => {
    feedback.toast('充值成功', 'success');
    void orders.reload(1);
  };

  return (
    <div class="space-y-4">
      <div>
        <h2 class="text-xl font-semibold">充值支付</h2>
        <p class="text-sm text-base-content/60">会员充值与提现管理</p>
      </div>

      <AccountRequiredBanner />

      <Tabs tabs={[...TABS]} active={tab()} onChange={setTab} />

      <Show when={tab() === '充值支付'}>
        <AdminCrudPage
          title="充值订单"
          description="会员充值订单列表"
          total={orders.total()}
          onCreate={() => setRechargeOpen(true)}
          createLabel="会员充值"
          onRefresh={() => void orders.refresh()}
        >
          <DataTable
            columns={orderColumns}
            rows={orders.items()}
            rowKey={(o) => o.id}
            total={orders.total()}
            page={orders.page()}
            totalPages={orders.totalPages()}
            pageSize={orders.pageSize()}
            loading={orders.loading()}
            error={orders.error()}
            emptyText="暂无订单"
            onPageChange={(p) => void orders.reload(p)}
            onPageSizeChange={(size) => orders.setPageSize(size)}
          />
        </AdminCrudPage>
      </Show>

      <Show when={tab() === '提现管理'}>
        <AdminCrudPage
          title="提现记录"
          description="提现申请与打款记录"
          total={withdraws.total()}
          onCreate={() => setWithdrawOpen(true)}
          createLabel="申请提现"
          onRefresh={() => void withdraws.refresh()}
        >
          <DataTable
            columns={withdrawColumns}
            rows={withdraws.items()}
            rowKey={(w) => w.id}
            total={withdraws.total()}
            page={withdraws.page()}
            totalPages={withdraws.totalPages()}
            pageSize={withdraws.pageSize()}
            loading={withdraws.loading()}
            error={withdraws.error()}
            emptyText="暂无提现记录"
            onPageChange={(p) => void withdraws.reload(p)}
            onPageSizeChange={(size) => withdraws.setPageSize(size)}
          />
        </AdminCrudPage>
      </Show>

      <RechargeModal
        open={rechargeOpen()}
        accountId={accountId()}
        onClose={() => setRechargeOpen(false)}
        onSaved={onRechargeSaved}
      />
      <WithdrawModal
        open={withdrawOpen()}
        accountId={accountId()}
        onClose={() => setWithdrawOpen(false)}
        onSaved={() => void withdraws.reload(1)}
      />
    </div>
  );
}

export default Payments;
