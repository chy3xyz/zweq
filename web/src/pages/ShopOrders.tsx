import { For, Show, createSignal } from 'solid-js';

import {
  getShopOrderDetail,
  listShopOrders,
  pickupShopOrder,
  shipShopOrder,
  type ShopOrderDetail,
  type ShopOrderItem,
  type ShopOrderProductItem,
} from '#ui/api';
import AccountRequiredBanner from '#ui/components/AccountRequiredBanner';
import AdminCrudPage from '#ui/components/AdminCrudPage';
import DataTable, { type Column } from '#ui/components/DataTable';
import FormField from '#ui/components/FormField';
import FormModal from '#ui/components/FormModal';
import SearchBar, { type SearchField, type SearchValues } from '#ui/components/SearchBar';
import { useAccountId, useAuth, useFeedback, usePaged } from '#ui/hooks';
import { hasPermission } from '#ui/utils/permissions';
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
  {
    kind: 'select',
    key: 'pickupType',
    label: '配送方式',
    options: [
      { value: '', label: '全部' },
      { value: 'delivery', label: '配送' },
      { value: 'self', label: '自提' },
    ],
  },
];

function ShopOrders() {
  const { accountId, ready, accountName } = useAccountId();
  const [auth] = useAuth();
  const feedback = useFeedback();
  const [filters, setFilters] = createSignal<SearchValues>({});

  const canWrite = () => hasPermission(auth.user?.permissions, 'shop:write') || !!auth.user?.admin;

  // 详情
  const [detailId, setDetailId] = createSignal<number | null>(null);
  const [detail, setDetail] = createSignal<ShopOrderDetail | null>(null);
  const [detailLoading, setDetailLoading] = createSignal(false);
  const [detailError, setDetailError] = createSignal<string | null>(null);

  // 发货
  const [shipOrder, setShipOrder] = createSignal<ShopOrderItem | null>(null);
  const [expressCompany, setExpressCompany] = createSignal('顺丰');
  const [expressNo, setExpressNo] = createSignal('');
  const [shipping, setShipping] = createSignal(false);
  const [shipError, setShipError] = createSignal<string | null>(null);

  // 核销
  const [pickupOrder, setPickupOrder] = createSignal<ShopOrderItem | null>(null);
  const [pickupSubmitting, setPickupSubmitting] = createSignal(false);
  const [pickupError, setPickupError] = createSignal<string | null>(null);

  const paged = usePaged<ShopOrderItem>(
    (page, pageSize) =>
      listShopOrders(
        accountId(),
        page,
        pageSize,
        intParam(filters().status, -1),
        filters().openid?.trim() || '',
        filters().pickupType?.trim() || '',
      ),
    20,
    () => [accountId(), filters()],
  );

  const columns: Column<ShopOrderItem>[] = [
    { key: 'order_no', title: '订单号', render: (r) => <span class="font-mono text-xs">{r.order_no}</span> },
    { key: 'openid', title: '买家 OpenID', render: (r) => <span class="font-mono text-xs">{r.openid}</span> },
    {
      key: 'pickup_type',
      title: '类型',
      render: (r) =>
        r.pickup_type === 'self' ? (
          <span class="badge badge-sm badge-secondary">自提</span>
        ) : (
          <span class="text-base-content/30">—</span>
        ),
    },
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
      title: '物流/取件码',
      render: (r) =>
        r.pickup_type === 'self' ? (
          <span class="font-mono text-xs">{r.pickup_code || <span class="text-base-content/40">—</span>}</span>
        ) : r.express_no ? (
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

  const loadDetail = (id: number) => {
    setDetailLoading(true);
    setDetailError(null);
    setDetail(null);
    getShopOrderDetail(id)
      .then((d) => setDetail(d))
      .catch((err) => setDetailError(err instanceof Error ? err.message : '加载详情失败，请稍后重试'))
      .finally(() => setDetailLoading(false));
  };

  const openDetail = (row: ShopOrderItem) => {
    setDetailId(row.id);
    loadDetail(row.id);
  };

  const closeDetail = () => {
    setDetailId(null);
    setDetail(null);
    setDetailError(null);
  };

  const retryDetail = () => {
    const id = detailId();
    if (!id) return;
    loadDetail(id);
  };

  const canShip = (row: ShopOrderItem) => row.status === 1 && row.pickup_type !== 'self';
  const canPickup = (row: ShopOrderItem) => row.status === 1 && row.pickup_type === 'self';

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

  const openPickup = (row: ShopOrderItem) => {
    setPickupOrder(row);
    setPickupError(null);
  };

  const onPickup = async () => {
    const row = pickupOrder();
    if (!row || pickupSubmitting()) return;
    setPickupSubmitting(true);
    setPickupError(null);
    try {
      await pickupShopOrder(row.id, row.pickup_code || '');
      setPickupOrder(null);
      feedback.toast('已核销');
      void paged.refresh();
    } catch (err) {
      setPickupError(err instanceof Error ? err.message : '核销失败，请稍后重试');
    } finally {
      setPickupSubmitting(false);
    }
  };

  return (
    <AdminCrudPage
      title="订单中心"
      description={ready() ? `当前公众号：${accountName()}` : undefined}
      total={paged.total()}
      onRefresh={() => void paged.refresh()}
      search={
        <SearchBar
          fields={SEARCH_FIELDS}
          values={{ status: '-1', pickupType: '' }}
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
            <button type="button" class="btn btn-ghost btn-xs" onClick={() => openDetail(row)}>
              详情
            </button>
            <Show when={canShip(row) && canWrite()}>
              <button
                type="button"
                class="btn btn-ghost btn-xs text-primary"
                onClick={() => openShip(row)}
              >
                发货
              </button>
            </Show>
            <Show when={canPickup(row) && canWrite()}>
              <button
                type="button"
                class="btn btn-ghost btn-xs text-primary"
                onClick={() => openPickup(row)}
              >
                核销
              </button>
            </Show>
          </>
        )}
      />

      <FormModal open={detailId() != null} title="订单详情" onClose={closeDetail} size="lg">
        <Show when={detailLoading()}>
          <div class="flex justify-center py-10">
            <span class="loading loading-spinner loading-md text-primary" />
          </div>
        </Show>

        <Show when={detailError()}>
          <div class="space-y-3">
            <div role="alert" class="alert alert-error py-2 text-sm">
              {detailError()}
            </div>
            <div class="flex justify-end">
              <button type="button" class="btn btn-primary btn-sm" onClick={retryDetail}>
                重试
              </button>
            </div>
          </div>
        </Show>

        <Show when={detail()}>
          {(d) => (
            <div class="space-y-5">
              <dl class="divide-y divide-base-200 text-sm">
                <For each={detailFields(d().order)}>
                  {(field) => (
                    <div class="flex justify-between gap-4 py-2">
                      <dt class="text-base-content/60">{field.label}</dt>
                      <dd class="text-right">{field.value}</dd>
                    </div>
                  )}
                </For>
              </dl>

              <Show when={d().order.address_json}>
                <div>
                  <h4 class="mb-2 text-sm font-medium">收货地址</h4>
                  <p class="rounded-box border border-base-200 bg-base-100 p-3 text-sm leading-relaxed">
                    {formatAddress(d().order.address_json!)}
                  </p>
                </div>
              </Show>

              <div>
                <h4 class="mb-2 text-sm font-medium">商品清单</h4>
                <div class="rounded-box border border-base-200 overflow-x-auto">
                  <table class="table table-sm">
                    <thead>
                      <tr>
                        <th>商品</th>
                        <th>规格</th>
                        <th class="text-right">单价</th>
                        <th class="text-right">数量</th>
                        <th class="text-right">小计</th>
                      </tr>
                    </thead>
                    <tbody>
                      <For each={d().items}>
                        {(item) => (
                          <tr>
                            <td>
                              <div class="flex items-center gap-2">
                                <Show when={item.image}>
                                  <img
                                    src={item.image}
                                    alt={item.name}
                                    class="h-10 w-10 rounded object-cover"
                                  />
                                </Show>
                                <span class="text-sm">{item.name}</span>
                              </div>
                            </td>
                            <td class="text-xs text-base-content/70">
                              {formatSpec(item.spec_json)}
                            </td>
                            <td class="text-right text-sm">{formatYuan(item.price)}</td>
                            <td class="text-right text-sm">{item.quantity}</td>
                            <td class="text-right text-sm font-medium">
                              {formatYuan(item.price * item.quantity)}
                            </td>
                          </tr>
                        )}
                      </For>
                    </tbody>
                  </table>
                </div>
              </div>
            </div>
          )}
        </Show>
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

      <FormModal
        open={pickupOrder() != null}
        title="订单核销"
        description={pickupOrder() ? `订单号 ${pickupOrder()!.order_no}` : undefined}
        onSubmit={onPickup}
        onClose={() => setPickupOrder(null)}
        submitting={pickupSubmitting()}
        error={pickupError()}
        submitLabel="确认核销"
        size="sm"
      >
        <p class="text-sm text-base-content/60">核销后订单将标记为已完成</p>
        <FormField label="取件码">
          <input
            type="text"
            class="input input-bordered input-sm w-full font-mono"
            value={pickupOrder()?.pickup_code ?? ''}
            disabled
          />
        </FormField>
      </FormModal>
    </AdminCrudPage>
  );
}

function detailFields(order: ShopOrderItem): { label: string; value: string }[] {
  const fields: { label: string; value: string }[] = [
    { label: '订单号', value: order.order_no },
    { label: '订单 ID', value: String(order.id) },
    { label: '买家 OpenID', value: order.openid },
    { label: '订单金额', value: formatYuan(order.total_amount) },
    { label: '实付金额', value: formatYuan(order.pay_amount) },
    { label: '状态', value: STATUS[order.status]?.label ?? String(order.status) },
    { label: '下单时间', value: formatDateTime(order.created_at) },
  ];

  if (order.pickup_type === 'self') {
    fields.push({ label: '配送方式', value: '自提' });
    if (order.pickup_code) fields.push({ label: '取件码', value: order.pickup_code });
    if (order.store_id) fields.push({ label: '自提门店', value: String(order.store_id) });
  } else if (order.pickup_type === 'delivery') {
    fields.push({ label: '配送方式', value: '配送' });
    fields.push({ label: '快递公司', value: order.express_company || '—' });
    fields.push({ label: '快递单号', value: order.express_no || '—' });
  }

  if (order.paid_at) {
    fields.push({ label: '支付时间', value: formatDateTime(order.paid_at) });
  }

  return fields;
}

function formatAddress(addressJson: string): string {
  try {
    const obj = JSON.parse(addressJson) as Record<string, unknown>;
    const parts: string[] = [];
    const region = [obj.province, obj.city, obj.district, (obj.region as string | undefined)]
      .filter((v): v is string => typeof v === 'string' && v.length > 0)
      .join(' ');
    if (region) parts.push(region);
    if (typeof obj.detail === 'string' && obj.detail) parts.push(obj.detail);
    if (typeof obj.name === 'string' && obj.name) parts.push(obj.name);
    if (typeof obj.mobile === 'string' && obj.mobile) parts.push(obj.mobile);
    return parts.length ? parts.join(' · ') : addressJson;
  } catch {
    return addressJson;
  }
}

function formatSpec(specJson: string): string {
  if (!specJson) return '—';
  try {
    const obj = JSON.parse(specJson) as Record<string, unknown>;
    const values = Object.values(obj)
      .filter((v): v is string => typeof v === 'string' && v.length > 0)
      .join(' / ');
    return values || specJson;
  } catch {
    return specJson;
  }
}

export default ShopOrders;
