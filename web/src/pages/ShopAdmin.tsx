import { For, Show, createSignal } from 'solid-js';

import {
  auditShopRefund,
  createArticle,
  createInviteGift,
  createShopBalancePlan,
  createShopGroupon,
  createShopOutlet,
  deleteArticle,
  deleteInviteGift,
  deleteShopBalancePlan,
  deleteShopOutlet,
  listShopBalancePlans,
  listShopOutlets,
  listShopRefunds,
  toApiError,
  type ShopArticleItem,
  type ShopBalancePlanItem,
  type ShopInviteGiftItem,
  type ShopOutletItem,
  type ShopRefundItem,
} from '#ui/api';
import DataTable, { type Column } from '#ui/components/DataTable';
import { useAccounts } from '#ui/hooks/useAccounts';
import { usePaged } from '#ui/hooks/usePaged';
import { formatDateTime } from '#ui/utils';

const PAGE_SIZE = 20;
const yuan = (fen: number) => (fen / 100).toFixed(2);

function ShopAdmin() {
  const accounts = useAccounts();
  const [success, setSuccess] = createSignal<string | null>(null);
  const [error, setError] = createSignal<string | null>(null);
  // 套餐表单
  const [planName, setPlanName] = createSignal('');
  const [planAmount, setPlanAmount] = createSignal(0);
  const [planBonus, setPlanBonus] = createSignal(0);
  // 门店表单
  const [outletName, setOutletName] = createSignal('');
  const [outletAddress, setOutletAddress] = createSignal('');
  const [outletMobile, setOutletMobile] = createSignal('');
  // 拼团表单
  const [grouponProduct, setGrouponProduct] = createSignal(0);
  const [grouponPrice, setGrouponPrice] = createSignal(0);
  const [grouponSize, setGrouponSize] = createSignal(2);
  // 邀请奖励
  const [inviteCount, setInviteCount] = createSignal(1);
  const [inviteType, setInviteType] = createSignal('points');
  const [inviteValue, setInviteValue] = createSignal(0);
  // 文章
  const [articleTitle, setArticleTitle] = createSignal('');
  const [articleContent, setArticleContent] = createSignal('');

  const accountId = () => accounts.selected() ?? 0;
  const refunds = usePaged<ShopRefundItem>(
    (page, pageSize) => listShopRefunds(accountId(), page, pageSize),
    PAGE_SIZE,
  );
  const [plans, setPlans] = createSignal<ShopBalancePlanItem[]>([]);
  const [outlets, setOutlets] = createSignal<ShopOutletItem[]>([]);
  const [inviteGifts, setInviteGifts] = createSignal<ShopInviteGiftItem[]>([]);
  const [articles, setArticles] = createSignal<ShopArticleItem[]>([]);

  const refundColumns: Column<ShopRefundItem>[] = [
    { key: 'order_id', title: '订单', render: (r) => <span class="font-mono text-xs">#{r.order_id}</span> },
    { key: 'openid', title: '买家', render: (r) => <span class="font-mono text-xs">{r.openid}</span> },
    { key: 'reason', title: '原因', render: (r) => <span class="text-sm">{r.reason}</span> },
    { key: 'amount', title: '金额', render: (r) => <span class="text-error font-semibold">¥{yuan(r.amount)}</span> },
    {
      key: 'status',
      title: '状态',
      render: (r) => (
        <span class={r.status === 0 ? 'text-warning' : r.status === 1 ? 'text-success' : 'text-base-content/50'}>
          {r.status === 0 ? '待审核' : r.status === 1 ? '已同意' : '已拒绝'}
        </span>
      ),
    },
    {
      key: 'created_at',
      title: '申请时间',
      render: (r) => <span class="text-sm text-base-content/70">{formatDateTime(r.created_at)}</span>,
    },
  ];

  const onAccountChange = (id: number) => {
    accounts.setSelected(id);
    void refunds.reload(1);
    void reloadPlans();
    void reloadOutlets();
  };

  const reloadPlans = async () => {
    if (accountId() === 0) return;
    try {
      setPlans(await listShopBalancePlans(accountId()));
    } catch {
      setPlans([]);
    }
  };

  const reloadOutlets = async () => {
    if (accountId() === 0) return;
    try {
      setOutlets(await listShopOutlets(accountId()));
    } catch {
      setOutlets([]);
    }
  };

  const reloadInviteGifts = async () => {
    if (accountId() === 0) return;
    try {
      const { listInviteGifts: listGifts } = await import('#ui/api/shop');
      const rows = await listGifts(accountId());
      setInviteGifts(rows as ShopInviteGiftItem[]);
    } catch {
      setInviteGifts([]);
    }
  };

  const reloadArticles = async () => {
    if (accountId() === 0) return;
    try {
      const { listShopArticles } = await import('#ui/api/shop');
      const rows = await listShopArticles(accountId(), 1, 50);
      setArticles(rows.list as ShopArticleItem[]);
    } catch {
      setArticles([]);
    }
  };

  const onAudit = async (row: ShopRefundItem, approve: boolean) => {
    try {
      await auditShopRefund(row.id, row.order_id, approve);
      setSuccess(approve ? '已同意退款' : '已拒绝');
      void refunds.reload(1);
    } catch (err) {
      setError(toApiError(err).message);
    }
  };

  const onCreatePlan = async () => {
    if (!planName().trim() || planAmount() <= 0) return;
    try {
      await createShopBalancePlan(accountId(), planName().trim(), planAmount(), planBonus());
      setPlanName('');
      setSuccess('套餐已创建');
      void reloadPlans();
    } catch (err) {
      setError(toApiError(err).message);
    }
  };

  const onCreateGroupon = async () => {
    if (!grouponProduct() || grouponPrice() <= 0) return;
    try {
      await createShopGroupon(accountId(), grouponProduct(), grouponPrice(), grouponSize());
      setSuccess('拼团已创建');
    } catch (err) {
      setError(toApiError(err).message);
    }
  };

  const onCreateInvite = async () => {
    if (inviteCount() <= 0 || inviteValue() <= 0) return;
    try {
      await createInviteGift(accountId(), inviteCount(), inviteType(), inviteValue());
      setSuccess('奖励已创建');
      void reloadInviteGifts();
    } catch (err) {
      setError(toApiError(err).message);
    }
  };

  const onCreateArticle = async () => {
    if (!articleTitle().trim()) return;
    try {
      await createArticle(accountId(), articleTitle().trim(), articleContent().trim());
      setArticleTitle('');
      setArticleContent('');
      setSuccess('文章已发布');
      void reloadArticles();
    } catch (err) {
      setError(toApiError(err).message);
    }
  };

  const onCreateOutlet = async () => {
    if (!outletName().trim()) return;
    try {
      await createShopOutlet(accountId(), outletName().trim(), outletAddress().trim(), outletMobile().trim());
      setOutletName('');
      setSuccess('门店已创建');
      void reloadOutlets();
    } catch (err) {
      setError(toApiError(err).message);
    }
  };

  return (
    <div class="p-6 space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">商城运营</h1>
        <select
          class="select select-bordered"
          onChange={(e) => onAccountChange(Number(e.currentTarget.value))}
        >
          <option value={0}>选择公众号</option>
          <For each={accounts.accounts()}>
            {(a) => <option value={a.id}>{a.name}</option>}
          </For>
        </select>
      </div>

      <Show when={success()}>
        <div class="alert alert-success">{success()}</div>
      </Show>
      <Show when={error()}>
        <div class="alert alert-error">{error()}</div>
      </Show>

      {/* 退款审核 */}
      <DataTable
        columns={refundColumns}
        rows={refunds.items()}
        rowKey={(r) => r.id}
        total={refunds.total()}
        page={refunds.page()}
        totalPages={refunds.totalPages()}
        loading={refunds.loading()}
        error={refunds.error()}
        emptyText="暂无退款申请"
        onPageChange={(p) => void refunds.reload(p)}
        actions={(row) => (
          <Show when={row.status === 0}>
            <div class="flex gap-1">
              <button class="btn btn-xs btn-outline btn-success" onClick={() => void onAudit(row, true)}>
                同意
              </button>
              <button class="btn btn-xs btn-outline btn-error" onClick={() => void onAudit(row, false)}>
                拒绝
              </button>
            </div>
          </Show>
        )}
      />

      {/* 储值套餐 */}
      <div class="card bg-base-200 p-4 space-y-3">
        <h2 class="font-semibold">储值套餐（充送）</h2>
        <div class="flex flex-wrap gap-2">
          <input
            class="input input-bordered flex-1 min-w-40"
            placeholder="套餐名，如：充100送20"
            value={planName()}
            onInput={(e) => setPlanName(e.currentTarget.value)}
          />
          <input
            class="input input-bordered w-28"
            type="number"
            placeholder="充值(分)"
            value={planAmount()}
            onInput={(e) => setPlanAmount(Number(e.currentTarget.value))}
          />
          <input
            class="input input-bordered w-28"
            type="number"
            placeholder="赠送(分)"
            value={planBonus()}
            onInput={(e) => setPlanBonus(Number(e.currentTarget.value))}
          />
          <button class="btn btn-primary" onClick={() => void onCreatePlan()}>
            创建
          </button>
        </div>
        <div class="flex flex-wrap gap-2">
          <For each={plans()}>
            {(p) => (
              <span class="badge badge-outline gap-2">
                {p.name}（充 ¥{yuan(p.amount)} 送 ¥{yuan(p.bonus)}）
                <button
                  class="text-error"
                  onClick={() => void deleteShopBalancePlan(p.id).then(() => void reloadPlans())}
                >
                  ✕
                </button>
              </span>
            )}
          </For>
        </div>
      </div>

      {/* 拼团活动 */}
      <div class="card bg-base-200 p-4 space-y-3">
        <h2 class="font-semibold">拼团活动</h2>
        <div class="flex flex-wrap gap-2">
          <input
            class="input input-bordered w-24"
            type="number"
            placeholder="商品ID"
            value={grouponProduct()}
            onInput={(e) => setGrouponProduct(Number(e.currentTarget.value))}
          />
          <input
            class="input input-bordered w-28"
            type="number"
            placeholder="团价(分)"
            value={grouponPrice()}
            onInput={(e) => setGrouponPrice(Number(e.currentTarget.value))}
          />
          <input
            class="input input-bordered w-24"
            type="number"
            placeholder="成团人数"
            value={grouponSize()}
            onInput={(e) => setGrouponSize(Number(e.currentTarget.value))}
          />
          <button class="btn btn-primary" onClick={() => void onCreateGroupon()}>
            创建拼团
          </button>
        </div>
      </div>

      {/* 邀请奖励 */}
      <div class="card bg-base-200 p-4 space-y-3">
        <h2 class="font-semibold">邀请有礼（拉新奖励）</h2>
        <div class="flex flex-wrap gap-2">
          <input
            class="input input-bordered w-24"
            type="number"
            placeholder="邀请人数"
            value={inviteCount()}
            onInput={(e) => setInviteCount(Number(e.currentTarget.value))}
          />
          <select
            class="select select-bordered"
            value={inviteType()}
            onChange={(e) => setInviteType(e.currentTarget.value)}
          >
            <option value="points">积分</option>
            <option value="coupon">优惠券</option>
          </select>
          <input
            class="input input-bordered w-28"
            type="number"
            placeholder="奖励值"
            value={inviteValue()}
            onInput={(e) => setInviteValue(Number(e.currentTarget.value))}
          />
          <button class="btn btn-primary" onClick={() => void onCreateInvite()}>
            创建奖励
          </button>
        </div>
        <div class="flex flex-wrap gap-2">
          <For each={inviteGifts()}>
            {(g) => (
              <span class="badge badge-outline gap-2">
                邀 {g.target_count} 人 → {g.reward_type === 'points' ? `${g.reward_value} 积分` : `券 ${g.reward_value}`}
                <button class="text-error" onClick={() => void deleteInviteGift(g.id).then(() => void reloadInviteGifts())}>
                  ✕
                </button>
              </span>
            )}
          </For>
        </div>
      </div>

      {/* 文章管理 */}
      <div class="card bg-base-200 p-4 space-y-3">
        <h2 class="font-semibold">文章（内容营销）</h2>
        <div class="flex flex-wrap gap-2">
          <input
            class="input input-bordered flex-1 min-w-40"
            placeholder="标题"
            value={articleTitle()}
            onInput={(e) => setArticleTitle(e.currentTarget.value)}
          />
          <input
            class="input input-bordered flex-1 min-w-40"
            placeholder="内容"
            value={articleContent()}
            onInput={(e) => setArticleContent(e.currentTarget.value)}
          />
          <button class="btn btn-primary" onClick={() => void onCreateArticle()}>
            发布
          </button>
        </div>
        <div class="flex flex-col gap-2">
          <For each={articles()}>
            {(a) => (
              <div class="flex items-center justify-between bg-base-100 rounded-lg px-3 py-2">
                <span class="text-sm">{a.title}</span>
                <button class="btn btn-xs btn-outline btn-error" onClick={() => void deleteArticle(a.id).then(() => void reloadArticles())}>
                  删除
                </button>
              </div>
            )}
          </For>
        </div>
      </div>

      {/* 门店管理 */}
      <div class="card bg-base-200 p-4 space-y-3">
        <h2 class="font-semibold">门店（自提点）</h2>
        <div class="flex flex-wrap gap-2">
          <input
            class="input input-bordered flex-1 min-w-40"
            placeholder="门店名"
            value={outletName()}
            onInput={(e) => setOutletName(e.currentTarget.value)}
          />
          <input
            class="input input-bordered flex-1 min-w-40"
            placeholder="地址"
            value={outletAddress()}
            onInput={(e) => setOutletAddress(e.currentTarget.value)}
          />
          <input
            class="input input-bordered w-36"
            placeholder="电话"
            value={outletMobile()}
            onInput={(e) => setOutletMobile(e.currentTarget.value)}
          />
          <button class="btn btn-primary" onClick={() => void onCreateOutlet()}>
            创建
          </button>
        </div>
        <div class="flex flex-wrap gap-2">
          <For each={outlets()}>
            {(o) => (
              <span class="badge badge-outline gap-2">
                {o.name} · {o.address}
                <button
                  class="text-error"
                  onClick={() => void deleteShopOutlet(o.id).then(() => void reloadOutlets())}
                >
                  ✕
                </button>
              </span>
            )}
          </For>
        </div>
      </div>
    </div>
  );
}

export default ShopAdmin;
