import { Show, createSignal } from 'solid-js';

import {
  adjustMemberPoints,
  createMemberLevel,
  getMemberView,
  listMemberLevels,
  listMembers,
  openMemberCard,
  setMemberLevelStatus,
  type MemberAccountItem,
  type MemberCardLevelItem,
  type MemberView,
} from '#ui/api';
import AccountRequiredBanner from '#ui/components/AccountRequiredBanner';
import AdminCrudPage from '#ui/components/AdminCrudPage';
import DataTable, { type Column } from '#ui/components/DataTable';
import FormModal from '#ui/components/FormModal';
import SearchBar, { type SearchField, type SearchValues } from '#ui/components/SearchBar';
import { useAccountId, useFeedback, usePaged } from '#ui/hooks';
import { formatDateTime, intParam } from '#ui/utils';

function MemberCard() {
  const { accountId, ready, accountName } = useAccountId();
  const feedback = useFeedback();

  const [levelKeyword, setLevelKeyword] = createSignal<SearchValues>({});
  const [memberFilters, setMemberFilters] = createSignal<SearchValues>({});

  const [levelOpen, setLevelOpen] = createSignal(false);
  const [name, setName] = createSignal('');
  const [discount, setDiscount] = createSignal('9.5');
  const [threshold, setThreshold] = createSignal(0);
  const [pointsRatio, setPointsRatio] = createSignal(1);
  const [memberView, setMemberView] = createSignal<MemberView | null>(null);
  const [submitting, setSubmitting] = createSignal(false);
  const [error, setError] = createSignal<string | null>(null);

  const levels = usePaged<MemberCardLevelItem>(
    (page, pageSize) =>
      listMemberLevels(
        accountId(),
        page,
        pageSize,
        levelKeyword().keyword?.trim() ?? '',
        intParam(levelKeyword().status, -1),
      ),
    20,
    () => [accountId(), levelKeyword()],
  );

  const members = usePaged<MemberAccountItem>(
    (page, pageSize) => listMembers(accountId(), page, pageSize, memberFilters().keyword?.trim() ?? ''),
    20,
    () => [accountId(), memberFilters()],
  );

  const openCreateLevel = () => {
    setError(null);
    setName('');
    setDiscount('9.5');
    setThreshold(0);
    setPointsRatio(1);
    setLevelOpen(true);
  };

  const onCreateLevel = async () => {
    if (submitting()) return;
    setSubmitting(true);
    setError(null);
    try {
      await createMemberLevel({
        account_id: accountId(),
        name: name().trim(),
        discount: Math.round(Number(discount()) * 100),
        threshold: threshold(),
        points_ratio: Math.round(pointsRatio() * 100),
        status: 1,
      });
      setLevelOpen(false);
      feedback.toast('会员等级已创建');
      void levels.reload(1);
    } catch (err) {
      setError(err instanceof Error ? err.message : '创建失败，请稍后重试');
    } finally {
      setSubmitting(false);
    }
  };

  const onToggleLevelStatus = (row: MemberCardLevelItem) => {
    const next = row.status === 1 ? 0 : 1;
    return feedback.runAction({
      confirm:
        next === 0
          ? { title: '停用等级', message: `确定停用等级「${row.name}」吗？停用后不再自动分配给新开的会员卡。`, danger: true }
          : undefined,
      action: () => setMemberLevelStatus(row.id, next),
      success: next === 1 ? '等级已启用' : '等级已停用',
      onDone: () => void levels.refresh(),
    });
  };

  const onView = async (openid: string) => {
    try {
      setMemberView(await getMemberView(accountId(), openid));
    } catch (err) {
      feedback.toast(err instanceof Error ? err.message : '查询失败', 'error');
    }
  };

  const onAdjust = (openid: string, delta: number) =>
    feedback.runAction({
      confirm: {
        title: '调整积分',
        message: `确定为「${openid}」${delta > 0 ? '增加' : '扣减'} ${Math.abs(delta)} 积分吗？`,
      },
      action: async () => {
        await adjustMemberPoints(accountId(), openid, delta);
        if (memberView()?.openid === openid) await onView(openid);
      },
      success: '积分已调整',
      onDone: () => void members.refresh(),
    });

  const onOpen = (openid: string) =>
    feedback.runAction({
      confirm: { title: '开卡', message: `确定为「${openid}」开通会员卡吗？` },
      action: () => openMemberCard(accountId(), openid),
      success: '开卡成功',
      onDone: () => void members.refresh(),
    });

  const levelSearchFields: SearchField[] = [
    { kind: 'text', key: 'keyword', label: '等级名称', placeholder: '输入等级名关键字' },
    {
      kind: 'select',
      key: 'status',
      label: '状态',
      options: [
        { value: '', label: '全部' },
        { value: '1', label: '启用' },
        { value: '0', label: '停用' },
      ],
    },
  ];

  const levelColumns: Column<MemberCardLevelItem>[] = [
    { key: 'name', title: '等级', render: (r) => <span class="font-medium">{r.name}</span> },
    { key: 'discount', title: '折扣', render: (r) => `${(r.discount / 10).toFixed(1)} 折` },
    { key: 'points_ratio', title: '积分倍率', render: (r) => `${r.points_ratio / 100}x` },
    { key: 'threshold', title: '升级门槛', render: (r) => `${r.threshold} 积分` },
    {
      key: 'status',
      title: '状态',
      render: (r) => (
        <span class={`badge badge-sm ${r.status === 1 ? 'badge-success' : 'badge-ghost'}`}>
          {r.status === 1 ? '启用' : '停用'}
        </span>
      ),
    },
  ];

  const memberColumns: Column<MemberAccountItem>[] = [
    { key: 'openid', title: '粉丝', render: (r) => <span class="font-mono text-xs">{r.openid}</span> },
    { key: 'points', title: '积分余额', render: (r) => <span class="font-semibold">{r.points}</span> },
    { key: 'total_points', title: '累计积分', render: (r) => r.total_points },
    {
      key: 'created_at',
      title: '开卡时间',
      render: (r) => <span class="text-sm text-base-content/70">{formatDateTime(r.created_at)}</span>,
    },
  ];

  return (
    <div class="space-y-4">
      <AdminCrudPage
        title="会员卡"
        description={ready() ? `当前公众号：${accountName()}` : undefined}
        total={levels.total()}
        onCreate={ready() ? openCreateLevel : undefined}
        createLabel="新增等级"
        onRefresh={() => void levels.refresh()}
        search={
          <SearchBar
            fields={levelSearchFields}
            values={{ keyword: '', status: '' }}
            loading={levels.loading()}
            onSearch={setLevelKeyword}
          />
        }
      >
        <AccountRequiredBanner />

        <Show when={memberView()}>
          {(view) => (
            <div class="mb-4 rounded-lg border border-base-300 bg-base-200/50 p-3">
              <p class="mb-2 text-sm font-semibold">会员详情（{view().openid}）</p>
              <div class="flex flex-wrap items-center gap-4 text-sm">
                <span>
                  等级：<b>{view().level_name || '—'}</b>
                </span>
                <span>
                  折扣：<b>{(view().discount / 10).toFixed(1)} 折</b>
                </span>
                <span>
                  积分：<b>{view().points}</b>
                </span>
                <span>
                  累计：<b>{view().total_points}</b>
                </span>
                <button
                  type="button"
                  class="btn btn-xs btn-outline btn-primary"
                  onClick={() => void onAdjust(view().openid, 100)}
                >
                  +100
                </button>
                <button
                  type="button"
                  class="btn btn-xs btn-outline btn-error"
                  onClick={() => void onAdjust(view().openid, -100)}
                >
                  -100
                </button>
              </div>
            </div>
          )}
        </Show>

        <DataTable
          columns={levelColumns}
          rows={levels.items()}
          rowKey={(r) => r.id}
          total={levels.total()}
          page={levels.page()}
          totalPages={levels.totalPages()}
          pageSize={levels.pageSize()}
          loading={levels.loading()}
          error={levels.error()}
          emptyText="暂无会员等级"
          onPageChange={(p) => void levels.reload(p)}
          onPageSizeChange={(size) => levels.setPageSize(size)}
          actions={(row) => (
            <button
              type="button"
              class={`btn btn-ghost btn-xs ${row.status === 1 ? 'text-base-content/70' : 'text-success'}`}
              onClick={() => void onToggleLevelStatus(row)}
            >
              {row.status === 1 ? '停用' : '启用'}
            </button>
          )}
        />
      </AdminCrudPage>

      <section class="rounded-box border border-base-300 bg-base-100 p-4">
        <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
          <h3 class="text-lg font-semibold">会员列表</h3>
          <button type="button" class="btn btn-ghost btn-sm" onClick={() => void members.refresh()}>
            刷新
          </button>
        </div>
        <div class="mb-4">
          <SearchBar
            fields={[{ kind: 'text', key: 'keyword', label: '粉丝 openid', placeholder: '输入 openid' }]}
            loading={members.loading()}
            onSearch={setMemberFilters}
          />
        </div>
        <DataTable
          columns={memberColumns}
          rows={members.items()}
          rowKey={(r) => r.id}
          total={members.total()}
          page={members.page()}
          totalPages={members.totalPages()}
          pageSize={members.pageSize()}
          loading={members.loading()}
          error={members.error()}
          emptyText="暂无会员"
          onPageChange={(p) => void members.reload(p)}
          onPageSizeChange={(size) => members.setPageSize(size)}
          actions={(row) => (
            <>
              <button type="button" class="btn btn-ghost btn-xs" onClick={() => void onView(row.openid)}>
                详情
              </button>
              <button
                type="button"
                class="btn btn-ghost btn-xs text-primary"
                onClick={() => void onOpen(row.openid)}
              >
                开卡
              </button>
            </>
          )}
        />
      </section>

      <FormModal
        open={levelOpen()}
        title="新增会员等级"
        description="折扣按「折」填写，如 9.5 表示 9.5 折"
        onSubmit={onCreateLevel}
        onClose={() => setLevelOpen(false)}
        submitting={submitting()}
        error={error()}
      >
        <label class="form-control">
          <span class="label-text mb-1">等级名称</span>
          <input
            class="input input-bordered input-sm"
            placeholder="例如：黄金会员"
            value={name()}
            onInput={(e) => setName(e.currentTarget.value)}
            required
          />
        </label>
        <div class="grid grid-cols-3 gap-3">
          <label class="form-control">
            <span class="label-text mb-1">折扣（折）</span>
            <input
              class="input input-bordered input-sm"
              type="number"
              step="0.1"
              min="0"
              max="10"
              value={discount()}
              onInput={(e) => setDiscount(e.currentTarget.value)}
            />
          </label>
          <label class="form-control">
            <span class="label-text mb-1">升级门槛（积分）</span>
            <input
              class="input input-bordered input-sm"
              type="number"
              min="0"
              value={threshold()}
              onInput={(e) => setThreshold(Number(e.currentTarget.value) || 0)}
            />
          </label>
          <label class="form-control">
            <span class="label-text mb-1">积分倍率</span>
            <input
              class="input input-bordered input-sm"
              type="number"
              step="0.1"
              min="0"
              value={pointsRatio()}
              onInput={(e) => setPointsRatio(Number(e.currentTarget.value) || 0)}
            />
          </label>
        </div>
      </FormModal>
    </div>
  );
}

export default MemberCard;
