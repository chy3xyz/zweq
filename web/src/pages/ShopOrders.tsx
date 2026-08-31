import { For, createSignal } from 'solid-js';

import { listShopOrders, shipShopOrder, type ShopOrderItem } from '#ui/api';
import AccountRequiredBanner from '#ui/components/AccountRequiredBanner';
import AdminCrudPage from '#ui/components/AdminCrudPage';
import DataTable, { type Column } from '#ui/components/DataTable';
import FormModal from '#ui/components/FormModal';
import SearchBar, { type SearchField, type SearchValues } from '#ui/components/SearchBar';
import { useAccountId, useFeedback, usePaged } from '#ui/hooks';
import { formatDateTime, intParam } from '#ui/utils';
import { formatYuan } from '#ui/utils/money';

const STATUS: Record<number, { label: string; cls: string }> = {
  0: { label: '待支付', cls: 'badge-warning' },
  1: { label: '已支付', cls: 'badge-info' },
  2: { label: '已发货', cls: 'badge-primary' },
  3: { label: '已完成', cls: 'badge-success' },
  4: { label: '已取消', cls: 'badge-ghost' },
};

const SEARCH_FIELDS: SearchField[] = [
  { kind: 'text', key: 'openid', label: '买家 OpenID', placeholder: '精确匹配', width: 'w-64' },
  {
    kind: 'select',
    key: 'status',
    label: '订单状态',
    options: [
      { value: '-1', label: '全部' },
      { value: '0', label: '待支付' },
      { value: '1', label: '已支付' },
      { value: '2', label: '已发货' },
      { value: '3', label: '已完成' },
      { value: '4', label: '已取消' },
    ],
  },
];

function ShopOrders() {
  const { accountId, ready, accountName } = useAccountId();
  const feedback = useFeedback();
  const [filters, setFilters] = createSignal<SearchValues>({});

  const [detailOrder, setDetailOrder] = createSignal<ShopOrderItem | null>(null);
  const [shipOrder, setShipOrder] = createSignal<ShopOrderItem | null>(null);
  const [expressCompany, setExpressCompany] = createSignal('顺丰');
  const [expressNo, setExpressNo] = createSignal('');
  const [shipping, setShipping] = createSignal(false);
  const [shipError, setShipError] = createSignal<string | null>(null);

  const paged = usePaged<ShopOrderItem>(
    (page, pageSize) =>
      listShopOrders(
        accountId(),
        page,
        pageSize,
        intParam(filters().status, -1),
        filters().openid?.trim() || '',
      ),
    20,
    () => [accountId(), filters()],
  );

  const columns: Column<ShopOrderItem>[] = [
    { key: 'order_no', title: '订单号', render: (r) => <span class="font-mono text-xs">{r.order_no}</span> },
    { key: 'openid', title: '买家 OpenID', render: (r) => <span class="font-mono text-xs">{r.openid}</span> },
    {
      key: 'pay_amount',
      title: '实付',
      render: (r) => <span class="font-semibold text-error">{formatYuan(r.pay_amount)}</span>,
    },
    {
      key: 'status',
      title: '状态',
      render: (r) => (
        <span class={`badge badge-sm ${STATUS[r.status]?.cls ?? 'badge-ghost'}`}>
          {STATUS[r.status]?.label ?? r.status}
        </span>
      ),
    },
    {
      key: 'express',
      title: '物流',
      render: (r) =>
        r.express_no ? (
          <span class="text-xs">
            {r.express_company} {r.express_no}
          </span>
        ) : (
          <span class="text-base-content/40">—</span>
        ),
    },
    {
      key: 'created_at',
      title: '下单时间',
      render: (r) => <span class="text-sm text-base-content/70">{formatDateTime(r.created_at)}</span>,
    },
  ];

  const openShip = (row: ShopOrderItem) => {
    setShipOrder(row);
    setExpressCompany('顺丰');
    setExpressNo('');
    setShipError(null);
  };

  const onShip = async () => {
    const row = shipOrder();
    if (!row || shipping()) return;
    setShipping(true);
    setShipError(null);
    try {
      await shipShopOrder(row.id, expressCompany().trim(), expressNo().trim());
      setShipOrder(null);
      feedback.toast('已发货');
      void paged.refresh();
    } catch (err) {
      setShipError(err instanceof Error ? err.message : '发货失败，请稍后重试');
    } finally {
      setShipping(false);
    }
  };

  return (
    <AdminCrudPage
      title="订单管理"
      description={ready() ? `当前公众号：${accountName()}` : undefined}
      total={paged.total()}
      onRefresh={() => void paged.refresh()}
      search={
        <SearchBar
          fields={SEARCH_FIELDS}
          values={{ status: '-1' }}
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
        emptyText="暂无订单"
        onPageChange={(p) => void paged.reload(p)}
        onPageSizeChange={(size) => paged.setPageSize(size)}
        actions={(row) => (
          <>
            <button type="button" class="btn btn-ghost btn-xs" onClick={() => setDetailOrder(row)}>
              详情
            </button>
            {row.status === 1 ? (
              <button type="button" class="btn btn-ghost btn-xs text-primary" onClick={() => openShip(row)}>
                发货
              </button>
            ) : null}
          </>
        )}
      />

      <FormModal
        open={detailOrder() != null}
        title="订单详情"
        onClose={() => setDetailOrder(null)}
        size="md"
      >
        <dl class="divide-y divide-base-200 text-sm">
          <For each={detailFields(detailOrder())}>
            {(field) => (
              <div class="flex justify-between gap-4 py-2">
                <dt class="text-base-content/60">{field.label}</dt>
                <dd class="text-right">{field.value}</dd>
              </div>
            )}
          </For>
        </dl>
      </FormModal>

      <FormModal
        open={shipOrder() != null}
        title="订单发货"
        description={shipOrder() ? `订单号 ${shipOrder()!.order_no}` : undefined}
        onSubmit={onShip}
        onClose={() => setShipOrder(null)}
        submitting={shipping()}
        error={shipError()}
        submitLabel="确认发货"
        size="sm"
      >
        <label class="form-control">
          <span class="label-text mb-1">快递公司</span>
          <input
            class="input input-bordered input-sm"
            value={expressCompany()}
            onInput={(e) => setExpressCompany(e.currentTarget.value)}
          />
        </label>
        <label class="form-control">
          <span class="label-text mb-1">快递单号</span>
          <input
            class="input input-bordered input-sm"
            value={expressNo()}
            onInput={(e) => setExpressNo(e.currentTarget.value)}
            required
          />
        </label>
      </FormModal>
    </AdminCrudPage>
  );
}

function detailFields(order: ShopOrderItem | null): { label: string; value: string }[] {
  if (!order) return [];
  return [
    { label: '订单号', value: order.order_no },
    { label: '订单 ID', value: String(order.id) },
    { label: '买家 OpenID', value: order.openid },
    { label: '订单金额', value: formatYuan(order.total_amount) },
    { label: '实付金额', value: formatYuan(order.pay_amount) },
    { label: '状态', value: STATUS[order.status]?.label ?? String(order.status) },
    { label: '快递公司', value: order.express_company || '—' },
    { label: '快递单号', value: order.express_no || '—' },
    { label: '支付时间', value: order.paid_at ? formatDateTime(order.paid_at) : '—' },
    { label: '下单时间', value: formatDateTime(order.created_at) },
  ];
}

export default ShopOrders;
