import { For, Show, createSignal } from 'solid-js';

import {
  adjustMemberPoints,
  createMemberLevel,
  getMemberView,
  listMemberLevels,
  listMembers,
  openMemberCard,
  toApiError,
  type MemberAccountItem,
  type MemberCardLevelItem,
  type MemberView,
} from '#ui/api';
import DataTable, { type Column } from '#ui/components/DataTable';
import { useAccounts } from '#ui/hooks/useAccounts';
import { usePaged } from '#ui/hooks/usePaged';
import { formatDateTime } from '#ui/utils';

const PAGE_SIZE = 20;

function MemberCard() {
  const accounts = useAccounts();
  const [success, setSuccess] = createSignal<string | null>(null);
  const [error, setError] = createSignal<string | null>(null);
  const [name, setName] = createSignal('');
  const [discount, setDiscount] = createSignal(950);
  const [threshold, setThreshold] = createSignal(0);
  const [memberView, setMemberView] = createSignal<MemberView | null>(null);

  const accountId = () => accounts.selected() ?? 0;
  const levels = usePaged<MemberCardLevelItem>(
    (page, pageSize) => listMemberLevels(accountId(), page, pageSize),
    PAGE_SIZE,
  );
  const members = usePaged<MemberAccountItem>(
    (page, pageSize) => listMembers(accountId(), page, pageSize),
    PAGE_SIZE,
  );

  const levelColumns: Column<MemberCardLevelItem>[] = [
    { key: 'name', title: '等级', render: (r) => <span class="font-medium">{r.name}</span> },
    {
      key: 'discount',
      title: '折扣',
      render: (r) => <span>{(r.discount / 10).toFixed(1)} 折</span>,
    },
    { key: 'points_ratio', title: '积分倍率', render: (r) => <span>{r.points_ratio / 100}x</span> },
    { key: 'threshold', title: '升级门槛', render: (r) => <span>{r.threshold} 积分</span> },
  ];

  const memberColumns: Column<MemberAccountItem>[] = [
    { key: 'openid', title: '粉丝', render: (r) => <span class="font-mono text-xs">{r.openid}</span> },
    { key: 'points', title: '积分余额', render: (r) => <span class="font-semibold">{r.points}</span> },
    { key: 'total_points', title: '累计积分', render: (r) => <span>{r.total_points}</span> },
    {
      key: 'created_at',
      title: '开卡时间',
      render: (r) => <span class="text-sm text-base-content/70">{formatDateTime(r.created_at)}</span>,
    },
  ];

  const onAccountChange = (id: number) => {
    accounts.setSelected(id);
    setMemberView(null);
    void levels.reload(1);
    void members.reload(1);
  };

  const onCreateLevel = async (e: SubmitEvent) => {
    e.preventDefault();
    if (accountId() === 0) return;
    setError(null);
    setSuccess(null);
    try {
      await createMemberLevel({
        account_id: accountId(),
        name: name().trim(),
        discount: discount(),
        threshold: threshold(),
      });
      setName('');
      setSuccess('等级已创建');
      void levels.reload(1);
    } catch (err) {
      setError(toApiError(err).message);
    }
  };

  const onView = async (openid: string) => {
    try {
      const v = await getMemberView(accountId(), openid);
      setMemberView(v);
    } catch (err) {
      setError(toApiError(err).message);
    }
  };

  const onAdjust = async (openid: string, delta: number) => {
    try {
      await adjustMemberPoints(accountId(), openid, delta);
      setSuccess(`积分已调整（${delta > 0 ? '+' : ''}${delta}）`);
      void members.reload(1);
      if (memberView()?.openid === openid) void onView(openid);
    } catch (err) {
      setError(toApiError(err).message);
    }
  };

  const onOpen = async (openid: string) => {
    try {
      await openMemberCard(accountId(), openid);
      setSuccess('开卡成功');
      void members.reload(1);
    } catch (err) {
      setError(toApiError(err).message);
    }
  };

  return (
    <div class="p-6 space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">会员卡</h1>
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

      <form onSubmit={onCreateLevel} class="card bg-base-200 p-4 space-y-3">
        <h2 class="font-semibold">新建卡等级</h2>
        <div class="flex flex-wrap gap-2">
          <input
            class="input input-bordered flex-1 min-w-40"
            placeholder="等级名"
            value={name()}
            onInput={(e) => setName(e.currentTarget.value)}
          />
          <input
            class="input input-bordered w-28"
            type="number"
            placeholder="折扣(千分比)"
            value={discount()}
            onInput={(e) => setDiscount(Number(e.currentTarget.value))}
          />
          <input
            class="input input-bordered w-32"
            type="number"
            placeholder="升级门槛(积分)"
            value={threshold()}
            onInput={(e) => setThreshold(Number(e.currentTarget.value))}
          />
          <button class="btn btn-primary" type="submit">
            创建
          </button>
        </div>
      </form>

      <DataTable
        columns={levelColumns}
        rows={levels.items()}
        rowKey={(r) => r.id}
        total={levels.total()}
        page={levels.page()}
        totalPages={levels.totalPages()}
        loading={levels.loading()}
        error={levels.error()}
        emptyText="暂无卡等级"
        onPageChange={(p) => void levels.reload(p)}
      />

      <Show when={memberView()}>
        {(v) => (
          <div class="card bg-base-200 p-4">
            <h2 class="font-semibold mb-2">会员详情（{v().openid}）</h2>
            <div class="flex gap-6 text-sm">
              <span>
                等级：<b>{v().level_name}</b>
              </span>
              <span>
                折扣：<b>{(v().discount / 10).toFixed(1)} 折</b>
              </span>
              <span>
                积分：<b>{v().points}</b>
              </span>
              <span>
                累计：<b>{v().total_points}</b>
              </span>
              <button
                class="btn btn-xs btn-outline btn-primary"
                onClick={() => void onAdjust(v().openid, 100)}
              >
                +100
              </button>
              <button
                class="btn btn-xs btn-outline btn-error"
                onClick={() => void onAdjust(v().openid, -100)}
              >
                -100
              </button>
            </div>
          </div>
        )}
      </Show>

      <div class="card bg-base-200 p-4">
        <h2 class="font-semibold mb-3">会员列表</h2>
        <DataTable
          columns={memberColumns}
          rows={members.items()}
          rowKey={(r) => r.id}
          total={members.total()}
          page={members.page()}
          totalPages={members.totalPages()}
          loading={members.loading()}
          error={members.error()}
          emptyText="暂无会员"
          onPageChange={(p) => void members.reload(p)}
          actions={(row) => (
            <div class="flex gap-1">
              <button class="btn btn-xs btn-outline btn-primary" onClick={() => void onView(row.openid)}>
                详情
              </button>
              <button class="btn btn-xs btn-outline btn-success" onClick={() => void onOpen(row.openid)}>
                开卡
              </button>
            </div>
          )}
        />
      </div>
    </div>
  );
}

export default MemberCard;
