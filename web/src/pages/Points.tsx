import { createSignal } from 'solid-js';

import {
  adjustPoints,
  createProduct,
  deleteProduct,
  listPointsOrders,
  listProducts,
  redeemPoints,
  updateProduct,
  type PointsOrder,
  type PointsProduct,
} from '#ui/api';
import AccountRequiredBanner from '#ui/components/AccountRequiredBanner';
import AdminCrudPage from '#ui/components/AdminCrudPage';
import DataTable, { type Column } from '#ui/components/DataTable';
import FormModal from '#ui/components/FormModal';
import SearchBar, { type SearchField, type SearchValues } from '#ui/components/SearchBar';
import { useAccountId, useFeedback, useLocalPaged, usePaged } from '#ui/hooks';
import { formatDateTime, intParam } from '#ui/utils';

const ORDER_FIELDS: SearchField[] = [
  { kind: 'text', key: 'keyword', label: '粉丝 / 商品', placeholder: '输入 openid 或商品名' },
];

interface ProductForm {
  id: number | null;
  name: string;
  points: number;
  stock: number;
  status: number;
}

const EMPTY_FORM: ProductForm = { id: null, name: '', points: 0, stock: 0, status: 1 };

function Points() {
  const { accountId, ready, accountName } = useAccountId();
  const feedback = useFeedback();

  const [filters, setFilters] = createSignal<SearchValues>({});
  const [orderFilters, setOrderFilters] = createSignal<SearchValues>({});

  const [formOpen, setFormOpen] = createSignal(false);
  const [form, setForm] = createSignal<ProductForm>({ ...EMPTY_FORM });
  const [adjustOpen, setAdjustOpen] = createSignal(false);
  const [adjustOpenid, setAdjustOpenid] = createSignal('');
  const [adjustDelta, setAdjustDelta] = createSignal(0);
  const [redeemTarget, setRedeemTarget] = createSignal<PointsProduct | null>(null);
  const [redeemOpenid, setRedeemOpenid] = createSignal('');
  const [submitting, setSubmitting] = createSignal(false);
  const [error, setError] = createSignal<string | null>(null);

  const paged = usePaged<PointsProduct>(
    (page, pageSize) =>
      listProducts(
        accountId(),
        page,
        pageSize,
        filters().keyword?.trim() ?? '',
        intParam(filters().status, -1),
      ),
    20,
    () => [accountId(), filters()],
  );

  const orders = useLocalPaged<PointsOrder>(
    () => listPointsOrders(accountId()),
    {
      keyword: () => orderFilters().keyword ?? '',
      match: (r, kw) =>
        r.openid.toLowerCase().includes(kw) || r.product_name.toLowerCase().includes(kw),
      resetKey: () => orderFilters(),
      watch: accountId,
      enabled: ready,
    },
  );

  const openCreate = () => {
    setError(null);
    setForm({ ...EMPTY_FORM });
    setFormOpen(true);
  };

  const openEdit = (row: PointsProduct) => {
    setError(null);
    setForm({
      id: row.id,
      name: row.name,
      points: row.points,
      stock: row.stock,
      status: row.status,
    });
    setFormOpen(true);
  };

  const onSubmit = async () => {
    if (submitting()) return;
    setSubmitting(true);
    setError(null);
    try {
      const current = form();
      const body = {
        name: current.name.trim(),
        points: current.points,
        stock: current.stock,
        status: current.status,
      };
      if (current.id == null) {
        await createProduct(accountId(), body);
      } else {
        await updateProduct(current.id, body);
      }
      setFormOpen(false);
      feedback.toast(current.id == null ? '商品已创建' : '商品已更新');
      void paged.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : '保存失败，请稍后重试');
    } finally {
      setSubmitting(false);
    }
  };

  const onRedeem = async () => {
    const target = redeemTarget();
    if (submitting() || !target) return;
    setSubmitting(true);
    setError(null);
    try {
      await redeemPoints(accountId(), { openid: redeemOpenid().trim(), product_id: target.id });
      setRedeemTarget(null);
      setRedeemOpenid('');
      feedback.toast('兑换成功');
      void Promise.all([paged.refresh(), orders.reload()]);
    } catch (err) {
      setError(err instanceof Error ? err.message : '兑换失败，请稍后重试');
    } finally {
      setSubmitting(false);
    }
  };

  const onAdjust = async () => {
    if (submitting()) return;
    setSubmitting(true);
    setError(null);
    try {
      await adjustPoints(accountId(), { openid: adjustOpenid().trim(), delta: adjustDelta() });
      setAdjustOpen(false);
      setAdjustOpenid('');
      setAdjustDelta(0);
      feedback.toast('积分已调整');
      void orders.reload();
    } catch (err) {
      setError(err instanceof Error ? err.message : '调整失败，请稍后重试');
    } finally {
      setSubmitting(false);
    }
  };

  const onDelete = (row: PointsProduct) =>
    feedback.runAction({
      confirm: { title: '删除商品', message: `确定删除积分商品「${row.name}」吗？`, danger: true },
      action: () => deleteProduct(row.id),
      success: '商品已删除',
      onDone: () => void paged.refresh(),
    });

  const onToggleStatus = (row: PointsProduct) => {
    const next = row.status === 1 ? 0 : 1;
    return feedback.runAction({
      // 下架是破坏性方向，需要二次确认；上架直接生效。
      confirm:
        next === 0
          ? { title: '下架商品', message: `确定下架积分商品「${row.name}」吗？`, danger: true }
          : undefined,
      action: () =>
        updateProduct(row.id, {
          name: row.name,
          points: row.points,
          stock: row.stock,
          status: next,
        }),
      success: next === 1 ? '商品已上架' : '商品已下架',
      onDone: () => void paged.refresh(),
    });
  };

  const columns: Column<PointsProduct>[] = [
    { key: 'name', title: '商品', render: (r) => <span class="font-medium">{r.name}</span> },
    { key: 'points', title: '所需积分', render: (r) => <span class="font-semibold">{r.points}</span> },
    {
      key: 'stock',
      title: '库存',
      render: (r) => (
        <span class={r.stock > 0 ? '' : 'text-error'}>{r.stock > 0 ? r.stock : '已兑完'}</span>
      ),
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

  const orderColumns: Column<PointsOrder>[] = [
    { key: 'openid', title: '粉丝', render: (r) => <span class="font-mono text-xs">{r.openid}</span> },
    { key: 'product_name', title: '商品', render: (r) => r.product_name },
    { key: 'points', title: '消耗积分', render: (r) => <span class="font-semibold">{r.points}</span> },
    {
      key: 'created_at',
      title: '兑换时间',
      render: (r) => <span class="text-sm text-base-content/70">{formatDateTime(r.created_at)}</span>,
    },
  ];

  return (
    <div class="space-y-4">
      <AdminCrudPage
        title="积分商城"
        description={ready() ? `当前公众号：${accountName()}` : undefined}
        total={paged.total()}
        onCreate={ready() ? openCreate : undefined}
        createLabel="新增商品"
        onRefresh={() => void paged.refresh()}
        extra={
          <button
            type="button"
            class="btn btn-outline btn-sm"
            disabled={!ready()}
            onClick={() => {
              setError(null);
              setAdjustOpen(true);
            }}
          >
            调整积分
          </button>
        }
        search={
          <SearchBar
            fields={[
              { kind: 'text', key: 'keyword', label: '商品名', placeholder: '输入商品名关键字' },
              {
                kind: 'select',
                key: 'status',
                label: '状态',
                options: [
                  { value: '', label: '全部' },
                  { value: '1', label: '上架' },
                  { value: '0', label: '下架' },
                ],
              },
            ]}
            loading={paged.loading()}
            onSearch={setFilters}
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
          emptyText="暂无积分商品"
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
                disabled={row.stock <= 0}
                onClick={() => {
                  setError(null);
                  setRedeemOpenid('');
                  setRedeemTarget(row);
                }}
              >
                兑换
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
          <h3 class="text-lg font-semibold">兑换订单</h3>
          <button type="button" class="btn btn-ghost btn-sm" onClick={() => void orders.reload()}>
            刷新
          </button>
        </div>
        <div class="mb-4">
          <SearchBar fields={ORDER_FIELDS} loading={orders.loading()} onSearch={setOrderFilters} />
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
          emptyText="暂无兑换订单"
          onPageChange={(p) => orders.setPage(p)}
          onPageSizeChange={(size) => orders.setPageSize(size)}
        />
      </section>

      <FormModal
        open={formOpen()}
        title={form().id == null ? '新增积分商品' : '编辑积分商品'}
        onSubmit={onSubmit}
        onClose={() => setFormOpen(false)}
        submitting={submitting()}
        error={error()}
        size="sm"
      >
        <label class="form-control">
          <span class="label-text mb-1">商品名称</span>
          <input
            class="input input-bordered input-sm"
            value={form().name}
            onInput={(e) => setForm((prev) => ({ ...prev, name: e.currentTarget.value }))}
            required
          />
        </label>
        <label class="form-control">
          <span class="label-text mb-1">上架状态</span>
          <select
            class="select select-bordered select-sm"
            value={form().status}
            onChange={(e) => setForm((prev) => ({ ...prev, status: Number(e.currentTarget.value) }))}
          >
            <option value={1}>上架</option>
            <option value={0}>下架</option>
          </select>
        </label>
        <div class="grid grid-cols-2 gap-3">
          <label class="form-control">
            <span class="label-text mb-1">所需积分</span>
            <input
              class="input input-bordered input-sm"
              type="number"
              min="0"
              value={form().points}
              onInput={(e) => setForm((prev) => ({ ...prev, points: Number(e.currentTarget.value) || 0 }))}
              required
            />
          </label>
          <label class="form-control">
            <span class="label-text mb-1">库存</span>
            <input
              class="input input-bordered input-sm"
              type="number"
              min="0"
              value={form().stock}
              onInput={(e) => setForm((prev) => ({ ...prev, stock: Number(e.currentTarget.value) || 0 }))}
              required
            />
          </label>
        </div>
      </FormModal>

      <FormModal
        open={redeemTarget() != null}
        title="积分兑换"
        description={redeemTarget() ? `使用 ${redeemTarget()!.points} 积分兑换「${redeemTarget()!.name}」` : undefined}
        onSubmit={onRedeem}
        onClose={() => setRedeemTarget(null)}
        submitting={submitting()}
        error={error()}
        submitLabel="确认兑换"
        size="sm"
      >
        <label class="form-control">
          <span class="label-text mb-1">粉丝 openid</span>
          <input
            class="input input-bordered input-sm"
            placeholder="输入粉丝 openid"
            value={redeemOpenid()}
            onInput={(e) => setRedeemOpenid(e.currentTarget.value)}
            required
          />
        </label>
      </FormModal>

      <FormModal
        open={adjustOpen()}
        title="调整粉丝积分"
        description="正数为增加，负数为扣减"
        onSubmit={onAdjust}
        onClose={() => setAdjustOpen(false)}
        submitting={submitting()}
        error={error()}
        submitLabel="调整"
        size="sm"
      >
        <label class="form-control">
          <span class="label-text mb-1">粉丝 openid</span>
          <input
            class="input input-bordered input-sm"
            value={adjustOpenid()}
            onInput={(e) => setAdjustOpenid(e.currentTarget.value)}
            required
          />
        </label>
        <label class="form-control">
          <span class="label-text mb-1">积分增减</span>
          <input
            class="input input-bordered input-sm"
            type="number"
            value={adjustDelta()}
            onInput={(e) => setAdjustDelta(Number(e.currentTarget.value) || 0)}
            required
          />
        </label>
      </FormModal>
    </div>
  );
}

export default Points;
