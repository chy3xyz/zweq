import { For, Show, createSignal, type JSX } from 'solid-js';

import {
  auditShopRefund,
  createArticle,
  createInviteGift,
  createShopBalancePlan,
  createShopOutlet,
  deleteArticle,
  deleteInviteGift,
  deleteShopBalancePlan,
  deleteShopOutlet,
  listInviteGifts,
  listShopArticles,
  listShopBalancePlans,
  listShopOutlets,
  listShopRefunds,
  type ShopArticleItem,
  type ShopBalancePlanItem,
  type ShopInviteGiftItem,
  type ShopOutletItem,
  type ShopRefundItem,
} from '#ui/api';
import AccountRequiredBanner from '#ui/components/AccountRequiredBanner';
import DataTable, { type Column } from '#ui/components/DataTable';
import FormModal from '#ui/components/FormModal';
import RichEditor from '#ui/components/RichEditor';
import SearchBar, { type SearchField, type SearchValues } from '#ui/components/SearchBar';
import { useAccountId, useFeedback, useLocalPaged, usePaged } from '#ui/hooks';
import { formatDateTime, intParam } from '#ui/utils';
import { fenToYuan, formatYuan, yuanToFen } from '#ui/utils/money';

const TABS = ['退款审核', '门店自提', '储值套餐', '邀请有礼', '文章内容'] as const;

function ShopAdmin() {
  const { accountId, accountName, ready } = useAccountId();
  const [tab, setTab] = createSignal<(typeof TABS)[number]>('退款审核');

  return (
    <div class="space-y-4">
      <div class="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 class="text-xl font-semibold">商城运营</h2>
          <p class="text-sm text-base-content/60">
            {ready() ? `当前公众号：${accountName()}` : '请先选择公众号'}
          </p>
        </div>
      </div>

      <AccountRequiredBanner />

      <div role="tablist" class="tabs tabs-box">
        <For each={TABS}>
          {(item) => (
            <button
              type="button"
              role="tab"
              class="tab"
              classList={{ 'tab-active': tab() === item }}
              onClick={() => setTab(item)}
            >
              {item}
            </button>
          )}
        </For>
      </div>

      <Show when={tab() === '退款审核'}>
        <RefundSection />
      </Show>
      <Show when={tab() === '门店自提'}>
        <OutletSection />
      </Show>
      <Show when={tab() === '储值套餐'}>
        <PlanSection />
      </Show>
      <Show when={tab() === '邀请有礼'}>
        <InviteGiftSection />
      </Show>
      <Show when={tab() === '文章内容'}>
        <ArticleSection />
      </Show>
    </div>
  );
}

/** Shared shell for the small sub-resources: header + search + table + pager. */
function SubResource(props: {
  title: string;
  hint?: string;
  onCreate: () => void;
  createLabel: string;
  onRefresh: () => void;
  search?: SearchField[];
  onSearch?: (values: SearchValues) => void;
  loading: boolean;
  children: JSX.Element;
}) {
  return (
    <section class="rounded-box border border-base-300 bg-base-100 p-4">
      <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
        <div>
          <h3 class="text-lg font-semibold">{props.title}</h3>
          <Show when={props.hint}>
            <p class="text-xs text-base-content/50">{props.hint}</p>
          </Show>
        </div>
        <div class="flex items-center gap-2">
          <button type="button" class="btn btn-ghost btn-sm" onClick={props.onRefresh}>
            刷新
          </button>
          <button type="button" class="btn btn-primary btn-sm" onClick={props.onCreate}>
            {props.createLabel}
          </button>
        </div>
      </div>
      <Show when={props.search && props.onSearch}>
        <div class="mb-4">
          <SearchBar fields={props.search!} loading={props.loading} onSearch={props.onSearch!} />
        </div>
      </Show>
      {props.children}
    </section>
  );
}

function RefundSection() {
  const { accountId, ready } = useAccountId();
  const feedback = useFeedback();
  const [filters, setFilters] = createSignal<SearchValues>({});

  const paged = usePaged<ShopRefundItem>(
    (page, pageSize) => listShopRefunds(accountId(), page, pageSize, intParam(filters().status, -1)),
    20,
    () => [accountId(), filters()],
  );

  const rows = () => {
    const kw = filters().keyword?.trim().toLowerCase() ?? '';
    return kw
      ? paged.items().filter((r) => r.openid.toLowerCase().includes(kw))
      : paged.items();
  };

  const onAudit = (row: ShopRefundItem, approve: boolean) =>
    feedback.runAction({
      confirm: {
        title: approve ? '同意退款' : '拒绝退款',
        message: `确定${approve ? '同意' : '拒绝'}该笔 ${formatYuan(row.amount)} 的退款申请吗？`,
        danger: !approve,
      },
      action: () => auditShopRefund(row.id, row.order_id, approve),
      success: approve ? '已同意退款' : '已拒绝退款',
      onDone: () => void paged.refresh(),
    });

  const columns: Column<ShopRefundItem>[] = [
    { key: 'order_id', title: '订单', render: (r) => <span class="font-mono text-xs">#{r.order_id}</span> },
    { key: 'openid', title: '买家', render: (r) => <span class="font-mono text-xs">{r.openid}</span> },
    { key: 'reason', title: '原因', render: (r) => <span class="text-sm">{r.reason || '—'}</span> },
    {
      key: 'amount',
      title: '退款金额',
      render: (r) => <span class="font-semibold text-error">{formatYuan(r.amount)}</span>,
    },
    {
      key: 'status',
      title: '状态',
      render: (r) => (
        <span class={`badge badge-sm ${refundClass(r.status)}`}>{refundLabel(r.status)}</span>
      ),
    },
    {
      key: 'created_at',
      title: '申请时间',
      render: (r) => <span class="text-sm text-base-content/70">{formatDateTime(r.created_at)}</span>,
    },
  ];

  return (
    <section class="rounded-box border border-base-300 bg-base-100 p-4">
      <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
        <h3 class="text-lg font-semibold">退款审核</h3>
        <button type="button" class="btn btn-ghost btn-sm" onClick={() => void paged.refresh()}>
          刷新
        </button>
      </div>
      <div class="mb-4">
        <SearchBar
          fields={[
            { kind: 'text', key: 'keyword', label: '买家 openid', placeholder: '输入 openid' },
            {
              kind: 'select',
              key: 'status',
              label: '审核状态',
              options: [
                { value: '-1', label: '全部' },
                { value: '0', label: '待审核' },
                { value: '1', label: '已同意' },
                { value: '2', label: '已拒绝' },
              ],
            },
          ]}
          values={{ status: '-1' }}
          loading={paged.loading()}
          onSearch={setFilters}
        />
      </div>
      <DataTable
        columns={columns}
        rows={rows()}
        rowKey={(r) => r.id}
        total={paged.total()}
        page={paged.page()}
        totalPages={paged.totalPages()}
        pageSize={paged.pageSize()}
        loading={paged.loading()}
        error={paged.error()}
        emptyText="暂无退款申请"
        onPageChange={(p) => void paged.reload(p)}
        onPageSizeChange={(size) => paged.setPageSize(size)}
        actions={(row) => (
          <Show when={row.status === 0}>
            <button type="button" class="btn btn-ghost btn-xs text-success" onClick={() => void onAudit(row, true)}>
              同意
            </button>
            <button type="button" class="btn btn-ghost btn-xs text-error" onClick={() => void onAudit(row, false)}>
              拒绝
            </button>
          </Show>
        )}
      />
    </section>
  );
}

function OutletSection() {
  const { accountId, ready } = useAccountId();
  const feedback = useFeedback();
  const [filters, setFilters] = createSignal<SearchValues>({});
  const [open, setOpen] = createSignal(false);
  const [name, setName] = createSignal('');
  const [address, setAddress] = createSignal('');
  const [mobile, setMobile] = createSignal('');
  const [submitting, setSubmitting] = createSignal(false);
  const [error, setError] = createSignal<string | null>(null);

  const list = useLocalPaged<ShopOutletItem>(() => listShopOutlets(accountId()), {
    keyword: () => filters().keyword ?? '',
    match: (o, kw) => o.name.toLowerCase().includes(kw) || o.address.toLowerCase().includes(kw),
    resetKey: () => filters(),
    watch: accountId,
    enabled: ready,
  });

  const onSubmit = async () => {
    if (submitting()) return;
    setSubmitting(true);
    setError(null);
    try {
      await createShopOutlet(accountId(), name().trim(), address().trim(), mobile().trim());
      setOpen(false);
      setName('');
      setAddress('');
      setMobile('');
      feedback.toast('门店已创建');
      void list.reload();
    } catch (err) {
      setError(err instanceof Error ? err.message : '创建失败，请稍后重试');
    } finally {
      setSubmitting(false);
    }
  };

  const onDelete = (row: ShopOutletItem) =>
    feedback.runAction({
      confirm: { title: '删除门店', message: `确定删除门店「${row.name}」吗？`, danger: true },
      action: () => deleteShopOutlet(row.id),
      success: '门店已删除',
      onDone: () => void list.reload(),
    });

  const columns: Column<ShopOutletItem>[] = [
    { key: 'name', title: '门店', render: (r) => <span class="font-medium">{r.name}</span> },
    { key: 'address', title: '地址', render: (r) => <span class="text-sm">{r.address || '—'}</span> },
    { key: 'mobile', title: '联系电话', render: (r) => <span class="text-sm">{r.mobile || '—'}</span> },
  ];

  return (
    <SubResource
      title="门店（自提点）"
      onCreate={() => {
        setError(null);
        setOpen(true);
      }}
      createLabel="新增门店"
      onRefresh={() => void list.reload()}
      search={[{ kind: 'text', key: 'keyword', label: '门店名称 / 地址', placeholder: '输入关键字' }]}
      onSearch={setFilters}
      loading={list.loading()}
    >
      <DataTable
        columns={columns}
        rows={list.items()}
        rowKey={(r) => r.id}
        total={list.total()}
        page={list.page()}
        totalPages={list.totalPages()}
        pageSize={list.pageSize()}
        loading={list.loading()}
        error={list.error()}
        emptyText="暂无门店"
        onPageChange={(p) => list.setPage(p)}
        onPageSizeChange={(size) => list.setPageSize(size)}
        actions={(row) => (
          <button type="button" class="btn btn-ghost btn-xs text-error" onClick={() => void onDelete(row)}>
            删除
          </button>
        )}
      />

      <FormModal
        open={open()}
        title="新增门店"
        onSubmit={onSubmit}
        onClose={() => setOpen(false)}
        submitting={submitting()}
        error={error()}
        size="sm"
      >
        <label class="form-control">
          <span class="label-text mb-1">门店名称</span>
          <input
            class="input input-bordered input-sm"
            value={name()}
            onInput={(e) => setName(e.currentTarget.value)}
            required
          />
        </label>
        <label class="form-control">
          <span class="label-text mb-1">地址</span>
          <input
            class="input input-bordered input-sm"
            value={address()}
            onInput={(e) => setAddress(e.currentTarget.value)}
          />
        </label>
        <label class="form-control">
          <span class="label-text mb-1">联系电话</span>
          <input
            class="input input-bordered input-sm"
            value={mobile()}
            onInput={(e) => setMobile(e.currentTarget.value)}
          />
        </label>
      </FormModal>
    </SubResource>
  );
}

function PlanSection() {
  const { accountId, ready } = useAccountId();
  const feedback = useFeedback();
  const [filters, setFilters] = createSignal<SearchValues>({});
  const [open, setOpen] = createSignal(false);
  const [name, setName] = createSignal('');
  const [amount, setAmount] = createSignal('100.00');
  const [bonus, setBonus] = createSignal('20.00');
  const [submitting, setSubmitting] = createSignal(false);
  const [error, setError] = createSignal<string | null>(null);

  const list = useLocalPaged<ShopBalancePlanItem>(() => listShopBalancePlans(accountId()), {
    keyword: () => filters().keyword ?? '',
    match: (p, kw) => p.name.toLowerCase().includes(kw),
    resetKey: () => filters(),
    watch: accountId,
    enabled: ready,
  });

  const onSubmit = async () => {
    if (submitting()) return;
    setSubmitting(true);
    setError(null);
    try {
      await createShopBalancePlan(
        accountId(),
        name().trim(),
        yuanToFen(Number(amount())),
        yuanToFen(Number(bonus())),
      );
      setOpen(false);
      setName('');
      feedback.toast('储值套餐已创建');
      void list.reload();
    } catch (err) {
      setError(err instanceof Error ? err.message : '创建失败，请稍后重试');
    } finally {
      setSubmitting(false);
    }
  };

  const onDelete = (row: ShopBalancePlanItem) =>
    feedback.runAction({
      confirm: { title: '删除套餐', message: `确定删除套餐「${row.name}」吗？`, danger: true },
      action: () => deleteShopBalancePlan(row.id),
      success: '套餐已删除',
      onDone: () => void list.reload(),
    });

  const columns: Column<ShopBalancePlanItem>[] = [
    { key: 'name', title: '套餐', render: (r) => <span class="font-medium">{r.name}</span> },
    { key: 'amount', title: '充值', render: (r) => <span class="font-semibold">{formatYuan(r.amount)}</span> },
    { key: 'bonus', title: '赠送', render: (r) => <span class="text-success">{formatYuan(r.bonus)}</span> },
  ];

  return (
    <SubResource
      title="储值套餐（充送）"
      onCreate={() => {
        setError(null);
        setOpen(true);
      }}
      createLabel="新增套餐"
      onRefresh={() => void list.reload()}
      search={[{ kind: 'text', key: 'keyword', label: '套餐名称', placeholder: '输入套餐名' }]}
      onSearch={setFilters}
      loading={list.loading()}
    >
      <DataTable
        columns={columns}
        rows={list.items()}
        rowKey={(r) => r.id}
        total={list.total()}
        page={list.page()}
        totalPages={list.totalPages()}
        pageSize={list.pageSize()}
        loading={list.loading()}
        error={list.error()}
        emptyText="暂无储值套餐"
        onPageChange={(p) => list.setPage(p)}
        onPageSizeChange={(size) => list.setPageSize(size)}
        actions={(row) => (
          <button type="button" class="btn btn-ghost btn-xs text-error" onClick={() => void onDelete(row)}>
            删除
          </button>
        )}
      />

      <FormModal
        open={open()}
        title="新增储值套餐"
        onSubmit={onSubmit}
        onClose={() => setOpen(false)}
        submitting={submitting()}
        error={error()}
        size="sm"
      >
        <label class="form-control">
          <span class="label-text mb-1">套餐名称</span>
          <input
            class="input input-bordered input-sm"
            placeholder="例如：充 100 送 20"
            value={name()}
            onInput={(e) => setName(e.currentTarget.value)}
            required
          />
        </label>
        <div class="grid grid-cols-2 gap-3">
          <label class="form-control">
            <span class="label-text mb-1">充值金额（元）</span>
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
            <span class="label-text mb-1">赠送金额（元）</span>
            <input
              class="input input-bordered input-sm"
              type="number"
              step="0.01"
              min="0"
              value={bonus()}
              onInput={(e) => setBonus(e.currentTarget.value)}
            />
          </label>
        </div>
        <p class="text-xs text-base-content/50">
          实得 ¥
          {fenToYuan(yuanToFen(Number(amount() || 0)) + yuanToFen(Number(bonus() || 0)))}
        </p>
      </FormModal>
    </SubResource>
  );
}

function InviteGiftSection() {
  const { accountId, ready } = useAccountId();
  const feedback = useFeedback();
  const [open, setOpen] = createSignal(false);
  const [count, setCount] = createSignal(1);
  const [type, setType] = createSignal('points');
  const [value, setValue] = createSignal(0);
  const [submitting, setSubmitting] = createSignal(false);
  const [error, setError] = createSignal<string | null>(null);

  const list = useLocalPaged<ShopInviteGiftItem>(() => listInviteGifts(accountId()), { watch: accountId, enabled: ready });

  const onSubmit = async () => {
    if (submitting()) return;
    setSubmitting(true);
    setError(null);
    try {
      await createInviteGift(accountId(), count(), type(), value());
      setOpen(false);
      feedback.toast('邀请奖励已创建');
      void list.reload();
    } catch (err) {
      setError(err instanceof Error ? err.message : '创建失败，请稍后重试');
    } finally {
      setSubmitting(false);
    }
  };

  const onDelete = (row: ShopInviteGiftItem) =>
    feedback.runAction({
      confirm: {
        title: '删除奖励',
        message: `确定删除「邀 ${row.target_count} 人」的奖励规则吗？`,
        danger: true,
      },
      action: () => deleteInviteGift(row.id),
      success: '奖励已删除',
      onDone: () => void list.reload(),
    });

  const columns: Column<ShopInviteGiftItem>[] = [
    { key: 'target_count', title: '邀请人数', render: (r) => `${r.target_count} 人` },
    {
      key: 'reward_type',
      title: '奖励类型',
      render: (r) => (
        <span class="badge badge-sm badge-ghost">{r.reward_type === 'points' ? '积分' : '优惠券'}</span>
      ),
    },
    {
      key: 'reward_value',
      title: '奖励值',
      render: (r) => (r.reward_type === 'points' ? `${r.reward_value} 积分` : `券 #${r.reward_value}`),
    },
  ];

  return (
    <SubResource
      title="邀请有礼（拉新奖励）"
      hint="粉丝邀请满指定人数后发放奖励"
      onCreate={() => {
        setError(null);
        setOpen(true);
      }}
      createLabel="新增奖励"
      onRefresh={() => void list.reload()}
      loading={list.loading()}
    >
      <DataTable
        columns={columns}
        rows={list.items()}
        rowKey={(r) => r.id}
        total={list.total()}
        page={list.page()}
        totalPages={list.totalPages()}
        pageSize={list.pageSize()}
        loading={list.loading()}
        error={list.error()}
        emptyText="暂无邀请奖励"
        onPageChange={(p) => list.setPage(p)}
        onPageSizeChange={(size) => list.setPageSize(size)}
        actions={(row) => (
          <button type="button" class="btn btn-ghost btn-xs text-error" onClick={() => void onDelete(row)}>
            删除
          </button>
        )}
      />

      <FormModal
        open={open()}
        title="新增邀请奖励"
        onSubmit={onSubmit}
        onClose={() => setOpen(false)}
        submitting={submitting()}
        error={error()}
        size="sm"
      >
        <div class="grid grid-cols-2 gap-3">
          <label class="form-control">
            <span class="label-text mb-1">邀请人数</span>
            <input
              class="input input-bordered input-sm"
              type="number"
              min="1"
              value={count()}
              onInput={(e) => setCount(Number(e.currentTarget.value) || 1)}
              required
            />
          </label>
          <label class="form-control">
            <span class="label-text mb-1">奖励类型</span>
            <select
              class="select select-bordered select-sm"
              value={type()}
              onChange={(e) => setType(e.currentTarget.value)}
            >
              <option value="points">积分</option>
              <option value="coupon">优惠券</option>
            </select>
          </label>
        </div>
        <label class="form-control">
          <span class="label-text mb-1">奖励值（积分数量 / 优惠券 ID）</span>
          <input
            class="input input-bordered input-sm"
            type="number"
            min="0"
            value={value()}
            onInput={(e) => setValue(Number(e.currentTarget.value) || 0)}
            required
          />
        </label>
      </FormModal>
    </SubResource>
  );
}

function ArticleSection() {
  const { accountId, ready } = useAccountId();
  const feedback = useFeedback();
  const [filters, setFilters] = createSignal<SearchValues>({});
  const [open, setOpen] = createSignal(false);
  const [title, setTitle] = createSignal('');
  const [content, setContent] = createSignal('');
  const [submitting, setSubmitting] = createSignal(false);
  const [error, setError] = createSignal<string | null>(null);

  const list = useLocalPaged<ShopArticleItem>(
    async () => {
      const res = await listShopArticles(accountId(), 1, 200);
      return res.list;
    },
    {
      keyword: () => filters().keyword ?? '',
      match: (a, kw) => a.title.toLowerCase().includes(kw),
      resetKey: () => filters(),
      watch: accountId,
      enabled: ready,
    },
  );

  const onSubmit = async () => {
    if (submitting()) return;
    setSubmitting(true);
    setError(null);
    try {
      await createArticle(accountId(), title().trim(), content().trim());
      setOpen(false);
      setTitle('');
      setContent('');
      feedback.toast('文章已发布');
      void list.reload();
    } catch (err) {
      setError(err instanceof Error ? err.message : '发布失败，请稍后重试');
    } finally {
      setSubmitting(false);
    }
  };

  const onDelete = (row: ShopArticleItem) =>
    feedback.runAction({
      confirm: { title: '删除文章', message: `确定删除文章「${row.title}」吗？`, danger: true },
      action: () => deleteArticle(row.id),
      success: '文章已删除',
      onDone: () => void list.reload(),
    });

  const columns: Column<ShopArticleItem>[] = [
    { key: 'title', title: '标题', render: (r) => <span class="font-medium">{r.title}</span> },
    {
      key: 'content',
      title: '内容摘要',
      render: (r) => <span class="text-sm text-base-content/60">{r.content?.slice(0, 40) || '—'}</span>,
    },
    {
      key: 'created_at',
      title: '发布时间',
      render: (r) => <span class="text-sm text-base-content/70">{formatDateTime(r.created_at)}</span>,
    },
  ];

  return (
    <SubResource
      title="文章（内容营销）"
      onCreate={() => {
        setError(null);
        setOpen(true);
      }}
      createLabel="发布文章"
      onRefresh={() => void list.reload()}
      search={[{ kind: 'text', key: 'keyword', label: '文章标题', placeholder: '输入标题关键字' }]}
      onSearch={setFilters}
      loading={list.loading()}
    >
      <DataTable
        columns={columns}
        rows={list.items()}
        rowKey={(r) => r.id}
        total={list.total()}
        page={list.page()}
        totalPages={list.totalPages()}
        pageSize={list.pageSize()}
        loading={list.loading()}
        error={list.error()}
        emptyText="暂无文章"
        onPageChange={(p) => list.setPage(p)}
        onPageSizeChange={(size) => list.setPageSize(size)}
        actions={(row) => (
          <button type="button" class="btn btn-ghost btn-xs text-error" onClick={() => void onDelete(row)}>
            删除
          </button>
        )}
      />

      <FormModal
        open={open()}
        title="发布文章"
        onSubmit={onSubmit}
        onClose={() => setOpen(false)}
        submitting={submitting()}
        error={error()}
      >
        <label class="form-control">
          <span class="label-text mb-1">标题</span>
          <input
            class="input input-bordered input-sm"
            value={title()}
            onInput={(e) => setTitle(e.currentTarget.value)}
            required
          />
        </label>
        <label class="form-control">
          <span class="label-text mb-1">正文</span>
          <RichEditor value={content()} onInput={setContent} placeholder="支持加粗、标题、列表、链接与图片插入" />
        </label>
      </FormModal>
    </SubResource>
  );
}

function refundLabel(status: number): string {
  return status === 0 ? '待审核' : status === 1 ? '已同意' : '已拒绝';
}

function refundClass(status: number): string {
  return status === 0 ? 'badge-warning' : status === 1 ? 'badge-success' : 'badge-ghost';
}

export default ShopAdmin;
