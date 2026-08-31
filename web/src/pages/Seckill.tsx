import { createSignal } from 'solid-js';

import {
  createSeckill,
  listSeckillOrders,
  listSeckills,
  rushSeckill,
  setSeckillStatus,
  type SeckillActivityItem,
  type SeckillOrderItem,
} from '#ui/api';
import AccountRequiredBanner from '#ui/components/AccountRequiredBanner';
import AdminCrudPage from '#ui/components/AdminCrudPage';
import DataTable, { type Column } from '#ui/components/DataTable';
import FormModal from '#ui/components/FormModal';
import SearchBar, { type SearchValues } from '#ui/components/SearchBar';
import { useAccountId, useFeedback, usePaged } from '#ui/hooks';
import { formatDateTime, intParam } from '#ui/utils';
import { fenToYuan, formatYuan, yuanToFen } from '#ui/utils/money';

function Seckill() {
  const { accountId, ready, accountName } = useAccountId();
  const feedback = useFeedback();

  const [keyword, setKeyword] = createSignal<SearchValues>({});
  const [orderFilters, setOrderFilters] = createSignal<SearchValues>({});

  const [formOpen, setFormOpen] = createSignal(false);
  const [title, setTitle] = createSignal('');
  const [price, setPrice] = createSignal('99.00');
  const [originalPrice, setOriginalPrice] = createSignal('199.00');
  const [stock, setStock] = createSignal(100);
  const [rushTarget, setRushTarget] = createSignal<SeckillActivityItem | null>(null);
  const [rushOpenid, setRushOpenid] = createSignal('');
  const [submitting, setSubmitting] = createSignal(false);
  const [error, setError] = createSignal<string | null>(null);

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

  const openCreate = () => {
    setError(null);
    setTitle('');
    setPrice('99.00');
    setOriginalPrice('199.00');
    setStock(100);
    setFormOpen(true);
  };

  const onCreate = async () => {
    if (submitting()) return;
    setSubmitting(true);
    setError(null);
    try {
      await createSeckill({
        account_id: accountId(),
        title: title().trim(),
        price: yuanToFen(Number(price())),
        original_price: yuanToFen(Number(originalPrice())),
        stock: stock(),
        per_user: 1,
        status: 1,
      });
      setFormOpen(false);
      feedback.toast('秒杀活动已创建');
      void paged.reload(1);
    } catch (err) {
      setError(err instanceof Error ? err.message : '创建失败，请稍后重试');
    } finally {
      setSubmitting(false);
    }
  };

  const onRush = async () => {
    const target = rushTarget();
    if (submitting() || !target) return;
    setSubmitting(true);
    setError(null);
    try {
      await rushSeckill(target.id, rushOpenid().trim(), 1);
      setRushTarget(null);
      setRushOpenid('');
      feedback.toast('抢购成功');
      void Promise.all([paged.refresh(), orders.refresh()]);
    } catch (err) {
      setError(err instanceof Error ? err.message : '抢购失败，请稍后重试');
    } finally {
      setSubmitting(false);
    }
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
      render: (r) => (
        <span class="text-base-content/50 line-through">{formatYuan(r.original_price)}</span>
      ),
    },
    {
      key: 'stock',
      title: '剩余 / 总量',
      render: (r) => (
        <span class={r.sold >= r.stock ? 'text-error' : ''}>
          {r.stock - r.sold} / {r.stock}
        </span>
      ),
    },
    { key: 'per_user', title: '限购', render: (r) => `${r.per_user} 件` },
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
    { key: 'openid', title: '粉丝', render: (r) => <span class="font-mono text-xs">{r.openid}</span> },
    { key: 'quantity', title: '数量', render: (r) => r.quantity },
    {
      key: 'created_at',
      title: '抢购时间',
      render: (r) => <span class="text-sm text-base-content/70">{formatDateTime(r.created_at)}</span>,
    },
  ];

  return (
    <div class="space-y-4">
      <AdminCrudPage
        title="秒杀活动"
        description={ready() ? `当前公众号：${accountName()}` : undefined}
        total={paged.total()}
        onCreate={ready() ? openCreate : undefined}
        createLabel="新增活动"
        onRefresh={() => void paged.refresh()}
        search={
          <SearchBar
            fields={[
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
            ]}
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
          emptyText="暂无秒杀活动"
          onPageChange={(p) => void paged.reload(p)}
          onPageSizeChange={(size) => paged.setPageSize(size)}
          actions={(row) => (
            <>
              <button
                type="button"
                class="btn btn-ghost btn-xs text-primary"
                disabled={row.sold >= row.stock}
                onClick={() => {
                  setError(null);
                  setRushOpenid('');
                  setRushTarget(row);
                }}
              >
                抢购
              </button>
              <button
                type="button"
                class="btn btn-ghost btn-xs"
                onClick={() => void onToggleStatus(row)}
              >
                {row.status === 1 ? '下架' : '上架'}
              </button>
            </>
          )}
        />
      </AdminCrudPage>

      <section class="rounded-box border border-base-300 bg-base-100 p-4">
        <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
          <h3 class="text-lg font-semibold">抢购记录</h3>
          <button type="button" class="btn btn-ghost btn-sm" onClick={() => void orders.refresh()}>
            刷新
          </button>
        </div>
        <div class="mb-4">
          <SearchBar
            fields={[{ kind: 'text', key: 'keyword', label: '粉丝 openid', placeholder: '输入 openid' }]}
            loading={orders.loading()}
            onSearch={setOrderFilters}
          />
        </div>
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
      </section>

      <FormModal
        open={formOpen()}
        title="新增秒杀活动"
        onSubmit={onCreate}
        onClose={() => setFormOpen(false)}
        submitting={submitting()}
        error={error()}
      >
        <label class="form-control">
          <span class="label-text mb-1">活动名称</span>
          <input
            class="input input-bordered input-sm"
            placeholder="例如：限时秒杀 iPhone"
            value={title()}
            onInput={(e) => setTitle(e.currentTarget.value)}
            required
          />
        </label>
        <div class="grid grid-cols-3 gap-3">
          <label class="form-control">
            <span class="label-text mb-1">秒杀价（元）</span>
            <input
              class="input input-bordered input-sm"
              type="number"
              step="0.01"
              min="0"
              value={price()}
              onInput={(e) => setPrice(e.currentTarget.value)}
              required
            />
          </label>
          <label class="form-control">
            <span class="label-text mb-1">原价（元）</span>
            <input
              class="input input-bordered input-sm"
              type="number"
              step="0.01"
              min="0"
              value={originalPrice()}
              onInput={(e) => setOriginalPrice(e.currentTarget.value)}
            />
          </label>
          <label class="form-control">
            <span class="label-text mb-1">库存</span>
            <input
              class="input input-bordered input-sm"
              type="number"
              min="1"
              value={stock()}
              onInput={(e) => setStock(Number(e.currentTarget.value) || 0)}
              required
            />
          </label>
        </div>
        <p class="text-xs text-base-content/50">
          秒杀价 ¥{fenToYuan(yuanToFen(Number(price() || 0)))}，每人限购 1 件
        </p>
      </FormModal>

      <FormModal
        open={rushTarget() != null}
        title="手动抢购"
        description={rushTarget() ? `活动：${rushTarget()!.title}` : undefined}
        onSubmit={onRush}
        onClose={() => setRushTarget(null)}
        submitting={submitting()}
        error={error()}
        submitLabel="抢购"
        size="sm"
      >
        <label class="form-control">
          <span class="label-text mb-1">粉丝 openid</span>
          <input
            class="input input-bordered input-sm"
            placeholder="输入粉丝 openid"
            value={rushOpenid()}
            onInput={(e) => setRushOpenid(e.currentTarget.value)}
            required
          />
        </label>
      </FormModal>
    </div>
  );
}

export default Seckill;
