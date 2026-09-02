import { Show, createSignal } from 'solid-js';

import {
  createSeckill,
  deleteSeckill,
  listSeckillOrders,
  listSeckills,
  rushSeckill,
  setSeckillStatus,
  updateSeckill,
  type SeckillActivityItem,
  type SeckillOrderItem,
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
import { fenToYuan, formatYuan, yuanToFen } from '#ui/utils/money';

const TABS = ['活动管理', '抢购记录'] as const;
type Tab = (typeof TABS)[number];

const ACTIVITY_FIELDS: SearchField[] = [
  { kind: 'text', key: 'keyword', label: '活动名称', placeholder: '输入活动名关键字' },
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

const ORDER_FIELDS: SearchField[] = [
  { kind: 'text', key: 'keyword', label: '买家 openid', placeholder: '输入粉丝 openid' },
];

/** 新建/编辑共用的秒杀活动表单（金额字段以「元」字符串编辑，提交时转分）。 */
interface SeckillFormState {
  title: string;
  /** 元 */
  price: string;
  /** 元 */
  original_price: string;
  stock: number;
  per_user: number;
  /** 开始时间 datetime-local 原始输入值（提交时解析为 epoch 秒，0 = 不限）。 */
  startAtInput: string;
  /** 结束时间 datetime-local 原始输入值（提交时解析为 epoch 秒，0 = 不限）。 */
  endAtInput: string;
  /** 1 = 上架，0 = 下架 */
  status: number;
}

const EMPTY_FORM: SeckillFormState = {
  title: '',
  price: '99.00',
  original_price: '199.00',
  stock: 100,
  per_user: 1,
  startAtInput: '',
  endAtInput: '',
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

function Seckill() {
  const { accountId, ready, accountName, onAccountChange } = useAccountId();
  const feedback = useFeedback();

  const [tab, setTab] = createSignal<Tab>('活动管理');
  const [keyword, setKeyword] = createSignal<SearchValues>({});
  const [orderFilters, setOrderFilters] = createSignal<SearchValues>({});

  // 活动 新建/编辑
  const [formOpen, setFormOpen] = createSignal(false);
  const [editing, setEditing] = createSignal<SeckillActivityItem | null>(null);
  const [form, setForm] = createSignal<SeckillFormState>({ ...EMPTY_FORM });
  const [formSubmitting, setFormSubmitting] = createSignal(false);
  const [formError, setFormError] = createSignal<string | null>(null);

  // 手动抢购
  const [rushTarget, setRushTarget] = createSignal<SeckillActivityItem | null>(null);
  const [rushOpenid, setRushOpenid] = createSignal('');
  const [rushSubmitting, setRushSubmitting] = createSignal(false);
  const [rushError, setRushError] = createSignal<string | null>(null);

  const paged = usePaged<SeckillActivityItem>(
    (page, pageSize) =>
      listSeckills(
        accountId(),
        page,
        pageSize,
        keyword().keyword?.trim() ?? '',
        intParam(keyword().status, -1),
      ),
    20,
    () => [accountId(), keyword()],
  );

  const orders = usePaged<SeckillOrderItem>(
    (page, pageSize) =>
      listSeckillOrders(accountId(), page, pageSize, orderFilters().keyword?.trim() ?? ''),
    20,
    () => [accountId(), orderFilters()],
  );

  const setFormField = <K extends keyof SeckillFormState>(key: K, value: SeckillFormState[K]) => {
    setForm((prev) => ({ ...prev, [key]: value }));
  };

  const resetFormModals = () => {
    setFormOpen(false);
    setEditing(null);
    setForm({ ...EMPTY_FORM });
    setRushTarget(null);
    setRushOpenid('');
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

  const openEdit = (row: SeckillActivityItem) => {
    setFormError(null);
    setEditing(row);
    setForm({
      title: row.title,
      price: fenToYuan(row.price),
      original_price: fenToYuan(row.original_price),
      stock: row.stock,
      per_user: row.per_user,
      startAtInput: toLocalInput(row.start_at),
      endAtInput: toLocalInput(row.end_at),
      status: row.status,
    });
    setFormOpen(true);
  };

  const onFormSubmit = async () => {
    if (formSubmitting() || !ready()) return;
    const current = form();
    const title = current.title.trim();
    if (!title) {
      setFormError('活动名称不能为空');
      return;
    }
    // 时间字段仅在提交时解析，避免编辑时 datetime-local 输入中途被回填清空。
    const start_at = parseLocalInput(current.startAtInput);
    const end_at = parseLocalInput(current.endAtInput);
    if (start_at > 0 && end_at > 0 && start_at >= end_at) {
      setFormError('开始时间需早于结束时间');
      return;
    }
    const body = {
      title,
      price: yuanToFen(Number(current.price)),
      original_price: yuanToFen(Number(current.original_price || 0)),
      stock: current.stock,
      per_user: current.per_user,
      start_at,
      end_at,
      status: current.status,
    };
    setFormSubmitting(true);
    setFormError(null);
    try {
      if (editing()) {
        await updateSeckill(editing()!.id, body);
      } else {
        await createSeckill({ account_id: accountId(), ...body });
      }
      setFormOpen(false);
      feedback.toast(editing() ? '秒杀活动已更新' : '秒杀活动已创建');
      void paged.refresh();
    } catch (err) {
      setFormError(err instanceof Error ? err.message : '保存失败，请稍后重试');
    } finally {
      setFormSubmitting(false);
    }
  };

  const onRush = async () => {
    const target = rushTarget();
    if (rushSubmitting() || !target) return;
    setRushSubmitting(true);
    setRushError(null);
    try {
      await rushSeckill(target.id, rushOpenid().trim(), 1);
      setRushTarget(null);
      setRushOpenid('');
      feedback.toast('抢购成功');
      void Promise.all([paged.refresh(), orders.refresh()]);
    } catch (err) {
      setRushError(err instanceof Error ? err.message : '抢购失败，请稍后重试');
    } finally {
      setRushSubmitting(false);
    }
  };

  const openRush = (row: SeckillActivityItem) => {
    setRushError(null);
    setRushOpenid('');
    setRushTarget(row);
  };

  const onToggleStatus = (row: SeckillActivityItem) => {
    const next = row.status === 1 ? 0 : 1;
    return feedback.runAction({
      confirm:
        next === 0
          ? { title: '下架秒杀活动', message: `确定下架秒杀活动「${row.title}」吗？`, danger: true }
          : undefined,
      action: () => setSeckillStatus(row.id, next),
      success: next === 1 ? '秒杀活动已上架' : '秒杀活动已下架',
      onDone: () => void paged.refresh(),
    });
  };

  const onDelete = (row: SeckillActivityItem) =>
    feedback.runAction({
      confirm: {
        title: '删除秒杀活动',
        message: `确定删除秒杀活动「${row.title}」吗？其抢购记录将一并删除。`,
        danger: true,
      },
      action: () => deleteSeckill(row.id),
      success: '秒杀活动已删除',
      onDone: () => void paged.refresh(),
    });

  const columns: Column<SeckillActivityItem>[] = [
    { key: 'title', title: '活动', render: (r) => <span class="font-medium">{r.title}</span> },
    {
      key: 'price',
      title: '秒杀价',
      render: (r) => <span class="font-semibold text-error">{formatYuan(r.price)}</span>,
    },
    {
      key: 'original_price',
      title: '原价',
      render: (r) =>
        r.original_price > 0 ? (
          <span class="text-base-content/50 line-through">{formatYuan(r.original_price)}</span>
        ) : (
          <span class="text-base-content/40">—</span>
        ),
    },
    {
      key: 'stock',
      title: '售罄进度',
      render: (r) => (
        <span class={r.sold >= r.stock ? 'text-error' : ''}>
          {r.sold} / {r.stock}
        </span>
      ),
    },
    { key: 'per_user', title: '每人限购', render: (r) => `${r.per_user} 件` },
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

  const orderColumns: Column<SeckillOrderItem>[] = [
    {
      key: 'activity_title',
      title: '活动',
      render: (r) =>
        r.activity_title?.trim() ? (
          <span class="text-sm">{r.activity_title}</span>
        ) : (
          <span class="text-xs text-base-content/40">活动 #{r.activity_id}</span>
        ),
    },
    { key: 'openid', title: '买家', render: (r) => <span class="font-mono text-xs">{r.openid}</span> },
    { key: 'quantity', title: '数量', render: (r) => r.quantity },
    {
      key: 'created_at',
      title: '抢购时间',
      render: (r) => <span class="text-sm text-base-content/70">{formatDateTime(r.created_at)}</span>,
    },
  ];

  return (
    <div class="space-y-4">
      <div>
        <h2 class="text-xl font-semibold">秒杀活动</h2>
        <p class="text-sm text-base-content/60">活动配置、手动抢购与抢购记录</p>
      </div>

      <AccountRequiredBanner />

      <Tabs tabs={[...TABS]} active={tab()} onChange={setTab} />

      <Show when={tab() === '活动管理'}>
        <AdminCrudPage
          title="活动管理"
          description={ready() ? `当前公众号：${accountName()}` : undefined}
          total={paged.total()}
          onCreate={ready() ? openCreate : undefined}
          createLabel="新增活动"
          onRefresh={() => void paged.refresh()}
          search={
            <SearchBar
              fields={ACTIVITY_FIELDS}
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
            emptyText="暂无秒杀活动"
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
                  class="btn btn-ghost btn-xs text-error"
                  onClick={() => void onDelete(row)}
                >
                  删除
                </button>
                <button
                  type="button"
                  class="btn btn-ghost btn-xs text-primary"
                  disabled={row.sold >= row.stock}
                  onClick={() => openRush(row)}
                >
                  抢购
                </button>
              </>
            )}
          />
        </AdminCrudPage>
      </Show>

      <Show when={tab() === '抢购记录'}>
        <AdminCrudPage
          title="抢购记录"
          description="用户秒杀成功的记录"
          total={orders.total()}
          onRefresh={() => void orders.refresh()}
          search={
            <SearchBar fields={ORDER_FIELDS} loading={orders.loading()} onSearch={setOrderFilters} />
          }
        >
          <DataTable
            columns={orderColumns}
            rows={orders.items()}
            rowKey={(r) => r.id}
            total={orders.total()}
            page={orders.page()}
            totalPages={orders.totalPages()}
            pageSize={orders.pageSize()}
            loading={orders.loading()}
            error={orders.error()}
            emptyText="暂无抢购记录"
            onPageChange={(p) => void orders.reload(p)}
            onPageSizeChange={(size) => orders.setPageSize(size)}
          />
        </AdminCrudPage>
      </Show>

      <FormModal
        open={formOpen()}
        title={editing() ? `编辑秒杀活动 #${editing()!.id}` : '新增秒杀活动'}
        onSubmit={onFormSubmit}
        onClose={() => setFormOpen(false)}
        submitting={formSubmitting()}
        error={formError()}
        submitLabel={editing() ? '保存修改' : '创建'}
      >
        <FormField label="活动名称" required>
          <input
            type="text"
            class="input input-bordered input-sm w-full"
            placeholder="例如：限时秒杀 iPhone"
            value={form().title}
            onInput={(e) => setFormField('title', e.currentTarget.value)}
            required
          />
        </FormField>
        <div class="grid grid-cols-2 gap-3">
          <FormField label="秒杀价（元）" required>
            <input
              type="number"
              step="0.01"
              min="0.01"
              class="input input-bordered input-sm w-full"
              value={form().price}
              onInput={(e) => setFormField('price', e.currentTarget.value)}
              required
            />
          </FormField>
          <FormField label="原价（元）" hint="用于划线价展示，留空则不展示">
            <input
              type="number"
              step="0.01"
              min="0"
              class="input input-bordered input-sm w-full"
              value={form().original_price}
              onInput={(e) => setFormField('original_price', e.currentTarget.value)}
            />
          </FormField>
        </div>
        <div class="grid grid-cols-2 gap-3">
          <FormField
            label="库存"
            required
            hint={editing() ? `该活动已售 ${editing()!.sold} 件，库存不可低于已售数量` : '可抢购的总件数'}
          >
            <input
              type="number"
              min="1"
              class="input input-bordered input-sm w-full"
              value={form().stock}
              onInput={(e) => setFormField('stock', Math.max(1, Math.floor(Number(e.currentTarget.value) || 1)))}
              required
            />
          </FormField>
          <FormField label="每人限购" required hint="每个用户最多可抢购的件数">
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
          <FormField label="开始时间" hint="留空表示不限">
            <input
              type="datetime-local"
              class="input input-bordered input-sm w-full"
              value={form().startAtInput}
              onInput={(e) => setFormField('startAtInput', e.currentTarget.value)}
            />
          </FormField>
          <FormField label="结束时间" hint="留空表示不限">
            <input
              type="datetime-local"
              class="input input-bordered input-sm w-full"
              value={form().endAtInput}
              onInput={(e) => setFormField('endAtInput', e.currentTarget.value)}
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
        open={rushTarget() != null}
        title="手动抢购"
        description={rushTarget() ? `活动：${rushTarget()!.title}` : undefined}
        onSubmit={onRush}
        onClose={() => setRushTarget(null)}
        submitting={rushSubmitting()}
        error={rushError()}
        submitLabel="抢购"
        size="sm"
      >
        <FormField label="粉丝 openid" required>
          <input
            type="text"
            class="input input-bordered input-sm w-full"
            placeholder="输入粉丝 openid"
            value={rushOpenid()}
            onInput={(e) => setRushOpenid(e.currentTarget.value)}
            required
          />
        </FormField>
      </FormModal>
    </div>
  );
}

export default Seckill;
