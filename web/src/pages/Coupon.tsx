import { Show, createSignal } from 'solid-js';

import {
  claimCoupon,
  createCoupon,
  deleteCoupon,
  listCoupons,
  listCouponUsers,
  setCouponStatus,
  updateCoupon,
  useCoupon,
  type CouponItem,
  type CouponUserItem,
} from '#ui/api';
import AccountRequiredBanner from '#ui/components/AccountRequiredBanner';
import AdminCrudPage from '#ui/components/AdminCrudPage';
import DataTable, { type Column } from '#ui/components/DataTable';
import FormField from '#ui/components/FormField';
import FormModal from '#ui/components/FormModal';
import SearchBar, { type SearchField, type SearchValues } from '#ui/components/SearchBar';
import Tabs from '#ui/components/Tabs';
import { useAccountId, useFeedback, usePaged } from '#ui/hooks';
import { formatDateTime, intParam } from '#ui/utils';
import { fenToYuan, formatYuan } from '#ui/utils/money';

const TABS = ['优惠券模板', '领取记录'] as const;
type Tab = (typeof TABS)[number];

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

/** 新建/编辑共用的券模板表单（金额字段以「元」字符串编辑，提交时转分）。 */
interface CouponFormState {
  title: string;
  /** 元 */
  amount: string;
  /** 元 */
  min_amount: string;
  total: number;
  per_user: number;
  /** 生效时间（epoch 秒），0 = 不限 */
  start_at: number;
  /** 失效时间（epoch 秒），0 = 不限 */
  end_at: number;
  /** 1 = 上架，0 = 下架 */
  status: number;
}

const EMPTY_FORM: CouponFormState = {
  title: '',
  amount: '10.00',
  min_amount: '0.00',
  total: 0,
  per_user: 1,
  start_at: 0,
  end_at: 0,
  status: 1,
};

/** epoch 秒 → datetime-local 输入值（空/0 → 空串）。 */
function toLocalInput(unixSeconds: number): string {
  if (!unixSeconds) return '';
  const d = new Date(unixSeconds * 1000);
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

/** datetime-local 输入值（"YYYY-MM-DDTHH:mm"，按本地时区解析）→ epoch 秒；空串/非法 → 0。 */
function parseLocalInput(value: string): number {
  const v = value.trim();
  if (!v) return 0;
  const ms = new Date(v).getTime();
  return Number.isNaN(ms) ? 0 : Math.floor(ms / 1000);
}

function Coupon() {
  const { accountId, ready, accountName, onAccountChange } = useAccountId();
  const feedback = useFeedback();

  const [tab, setTab] = createSignal<Tab>('优惠券模板');
  const [keyword, setKeyword] = createSignal<SearchValues>({});
  const [userFilters, setUserFilters] = createSignal<SearchValues>({});

  // 券模板 新建/编辑
  const [formOpen, setFormOpen] = createSignal(false);
  const [editing, setEditing] = createSignal<CouponItem | null>(null);
  const [form, setForm] = createSignal<CouponFormState>({ ...EMPTY_FORM });
  const [formSubmitting, setFormSubmitting] = createSignal(false);
  const [formError, setFormError] = createSignal<string | null>(null);

  // 发券 / 核销
  const [claimTarget, setClaimTarget] = createSignal<CouponItem | null>(null);
  const [openid, setOpenid] = createSignal('');
  const [claimSubmitting, setClaimSubmitting] = createSignal(false);
  const [claimError, setClaimError] = createSignal<string | null>(null);
  const [verifyOpen, setVerifyOpen] = createSignal(false);
  const [useCode, setUseCode] = createSignal('');
  const [verifySubmitting, setVerifySubmitting] = createSignal(false);
  const [verifyError, setVerifyError] = createSignal<string | null>(null);

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

  const setFormField = <K extends keyof CouponFormState>(key: K, value: CouponFormState[K]) => {
    setForm((prev) => ({ ...prev, [key]: value }));
  };

  const resetFormModals = () => {
    setFormOpen(false);
    setEditing(null);
    setForm({ ...EMPTY_FORM });
    setClaimTarget(null);
    setOpenid('');
    setVerifyOpen(false);
    setUseCode('');
  };

  // 账号切换：关闭所有弹窗并重置表单，列表由 usePaged 的 watch 自动回到第 1 页。
  onAccountChange(() => {
    resetFormModals();
  });

  const openCreate = () => {
    setFormError(null);
    setEditing(null);
    setForm({ ...EMPTY_FORM });
    setFormOpen(true);
  };

  const openEdit = (row: CouponItem) => {
    setFormError(null);
    setEditing(row);
    setForm({
      title: row.title,
      amount: fenToYuan(row.amount),
      min_amount: fenToYuan(row.min_amount),
      total: row.total,
      per_user: row.per_user,
      start_at: row.start_at,
      end_at: row.end_at,
      status: row.status,
    });
    setFormOpen(true);
  };

  const onFormSubmit = async () => {
    if (formSubmitting() || !ready()) return;
    const current = form();
    const title = current.title.trim();
    if (!title) {
      setFormError('券名不能为空');
      return;
    }
    const body = {
      title,
      amount: Math.round(Number(current.amount) * 100),
      min_amount: Math.round(Number(current.min_amount || 0) * 100),
      total: current.total,
      per_user: current.per_user,
      start_at: current.start_at,
      end_at: current.end_at,
      status: current.status,
    };
    setFormSubmitting(true);
    setFormError(null);
    try {
      if (editing()) {
        await updateCoupon(editing()!.id, body);
      } else {
        await createCoupon({ account_id: accountId(), ...body });
      }
      setFormOpen(false);
      feedback.toast(editing() ? '优惠券已更新' : '优惠券已创建');
      void paged.refresh();
    } catch (err) {
      setFormError(err instanceof Error ? err.message : '保存失败，请稍后重试');
    } finally {
      setFormSubmitting(false);
    }
  };

  const onClaim = async () => {
    const coupon = claimTarget();
    if (claimSubmitting() || !coupon) return;
    setClaimSubmitting(true);
    setClaimError(null);
    try {
      const result = await claimCoupon(coupon.id, openid().trim());
      setClaimTarget(null);
      setOpenid('');
      feedback.toast(`发券成功：${result.code}`);
      void users.refresh();
    } catch (err) {
      setClaimError(err instanceof Error ? err.message : '发券失败，请稍后重试');
    } finally {
      setClaimSubmitting(false);
    }
  };

  const onVerify = async () => {
    if (verifySubmitting()) return;
    setVerifySubmitting(true);
    setVerifyError(null);
    try {
      await useCoupon(useCode().trim());
      setVerifyOpen(false);
      setUseCode('');
      feedback.toast('已核销');
      void users.refresh();
    } catch (err) {
      setVerifyError(err instanceof Error ? err.message : '核销失败，请稍后重试');
    } finally {
      setVerifySubmitting(false);
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
    { key: 'per_user', title: '每人限领', render: (r) => r.per_user },
    {
      key: 'start_at',
      title: '有效期',
      render: (r) => {
        if (r.start_at && r.end_at) {
          return (
            <span class="text-sm text-base-content/70">
              {formatDateTime(r.start_at)} ~ {formatDateTime(r.end_at)}
            </span>
          );
        }
        if (r.start_at) return <span class="text-sm text-base-content/70">自 {formatDateTime(r.start_at)} 起</span>;
        if (r.end_at) return <span class="text-sm text-base-content/70">至 {formatDateTime(r.end_at)} 止</span>;
        return <span class="text-base-content/40">长期</span>;
      },
    },
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
      <div>
        <h2 class="text-xl font-semibold">优惠券</h2>
        <p class="text-sm text-base-content/60">券模板管理、发放与核销记录</p>
      </div>

      <AccountRequiredBanner />

      <Tabs tabs={[...TABS]} active={tab()} onChange={setTab} />

      <Show when={tab() === '优惠券模板'}>
        <AdminCrudPage
          title="优惠券模板"
          description={ready() ? `当前公众号：${accountName()}` : undefined}
          total={paged.total()}
          onCreate={ready() ? openCreate : undefined}
          createLabel="新增优惠券"
          onRefresh={() => void paged.refresh()}
          search={
            <SearchBar
              fields={COUPON_FIELDS}
              values={{ status: '-1' }}
              loading={paged.loading()}
              onSearch={setKeyword}
            />
          }
        >
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
                <button type="button" class="btn btn-ghost btn-xs" onClick={() => openEdit(row)}>
                  编辑
                </button>
                <button
                  type="button"
                  class="btn btn-ghost btn-xs"
                  onClick={() => void onToggleStatus(row)}
                >
                  {row.status === 1 ? '下架' : '上架'}
                </button>
                <button
                  type="button"
                  class="btn btn-ghost btn-xs text-primary"
                  onClick={() => {
                    setClaimError(null);
                    setOpenid('');
                    setClaimTarget(row);
                  }}
                >
                  发券
                </button>
                <button type="button" class="btn btn-ghost btn-xs text-error" onClick={() => void onDelete(row)}>
                  删除
                </button>
              </>
            )}
          />
        </AdminCrudPage>
      </Show>

      <Show when={tab() === '领取记录'}>
        <AdminCrudPage
          title="领取记录"
          description="用户领取的券码与核销状态"
          total={users.total()}
          onRefresh={() => void users.refresh()}
          extra={
            <button
              type="button"
              class="btn btn-outline btn-sm"
              disabled={!ready()}
              onClick={() => {
                setVerifyError(null);
                setVerifyOpen(true);
              }}
            >
              核销券码
            </button>
          }
          search={
            <SearchBar fields={USER_FIELDS} loading={users.loading()} onSearch={setUserFilters} />
          }
        >
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
        </AdminCrudPage>
      </Show>

      <FormModal
        open={formOpen()}
        title={editing() ? `编辑优惠券 #${editing()!.id}` : '新增优惠券'}
        onSubmit={onFormSubmit}
        onClose={() => setFormOpen(false)}
        submitting={formSubmitting()}
        error={formError()}
        submitLabel={editing() ? '保存修改' : '创建'}
      >
        <FormField label="券名" required>
          <input
            type="text"
            class="input input-bordered input-sm w-full"
            placeholder="例如：满 100 减 10"
            value={form().title}
            onInput={(e) => setFormField('title', e.currentTarget.value)}
            required
          />
        </FormField>
        <div class="grid grid-cols-2 gap-3">
          <FormField label="面额（元）" required>
            <input
              type="number"
              step="0.01"
              min="0"
              class="input input-bordered input-sm w-full"
              value={form().amount}
              onInput={(e) => setFormField('amount', e.currentTarget.value)}
              required
            />
          </FormField>
          <FormField label="使用门槛（元）" hint="订单满该金额可用，0 表示无门槛">
            <input
              type="number"
              step="0.01"
              min="0"
              class="input input-bordered input-sm w-full"
              value={form().min_amount}
              onInput={(e) => setFormField('min_amount', e.currentTarget.value)}
            />
          </FormField>
        </div>
        <div class="grid grid-cols-2 gap-3">
          <FormField label="发放总量" hint="0 表示不限">
            <input
              type="number"
              min="0"
              class="input input-bordered input-sm w-full"
              value={form().total}
              onInput={(e) => setFormField('total', Math.max(0, Math.floor(Number(e.currentTarget.value) || 0)))}
            />
          </FormField>
          <FormField label="每人限领" required hint="每个用户最多可领取的张数">
            <input
              type="number"
              min="1"
              class="input input-bordered input-sm w-full"
              value={form().per_user}
              onInput={(e) => setFormField('per_user', Math.max(1, Math.floor(Number(e.currentTarget.value) || 1)))}
              required
            />
          </FormField>
        </div>
        <div class="grid grid-cols-2 gap-3">
          <FormField label="生效时间" hint="留空表示立即生效">
            <input
              type="datetime-local"
              class="input input-bordered input-sm w-full"
              value={toLocalInput(form().start_at)}
              onInput={(e) => setFormField('start_at', parseLocalInput(e.currentTarget.value))}
            />
          </FormField>
          <FormField label="失效时间" hint="留空表示长期有效">
            <input
              type="datetime-local"
              class="input input-bordered input-sm w-full"
              value={toLocalInput(form().end_at)}
              onInput={(e) => setFormField('end_at', parseLocalInput(e.currentTarget.value))}
            />
          </FormField>
        </div>
        <FormField label="状态">
          <select
            class="select select-bordered select-sm w-full"
            value={form().status}
            onChange={(e) => setFormField('status', Number(e.currentTarget.value))}
          >
            <option value={1}>上架</option>
            <option value={0}>下架</option>
          </select>
        </FormField>
      </FormModal>

      <FormModal
        open={claimTarget() != null}
        title="发放优惠券"
        description={claimTarget() ? `将「${claimTarget()!.title}」发放给指定粉丝` : undefined}
        onSubmit={onClaim}
        onClose={() => setClaimTarget(null)}
        submitting={claimSubmitting()}
        error={claimError()}
        submitLabel="发放"
        size="sm"
      >
        <FormField label="粉丝 openid" required>
          <input
            type="text"
            class="input input-bordered input-sm w-full"
            placeholder="输入粉丝 openid"
            value={openid()}
            onInput={(e) => setOpenid(e.currentTarget.value)}
            required
          />
        </FormField>
      </FormModal>

      <FormModal
        open={verifyOpen()}
        title="核销券码"
        onSubmit={onVerify}
        onClose={() => setVerifyOpen(false)}
        submitting={verifySubmitting()}
        error={verifyError()}
        submitLabel="核销"
        size="sm"
      >
        <FormField label="券码" required>
          <input
            type="text"
            class="input input-bordered input-sm w-full"
            placeholder="输入用户券码"
            value={useCode()}
            onInput={(e) => setUseCode(e.currentTarget.value)}
            required
          />
        </FormField>
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
