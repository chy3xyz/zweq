import { Show, createMemo, createSignal } from 'solid-js';

import {
  adjustMemberPoints,
  createMemberLevel,
  deleteMemberLevel,
  getMemberView,
  listMemberLevels,
  listMembers,
  openMemberCard,
  setMemberLevelStatus,
  updateMemberLevel,
  type MemberAccountItem,
  type MemberCardLevelItem,
  type MemberView,
} from '#ui/api';
import AccountRequiredBanner from '#ui/components/AccountRequiredBanner';
import AdminCrudPage from '#ui/components/AdminCrudPage';
import BaseModal from '#ui/components/BaseModal';
import DataTable, { type Column } from '#ui/components/DataTable';
import FormField from '#ui/components/FormField';
import FormModal from '#ui/components/FormModal';
import SearchBar, { type SearchField, type SearchValues } from '#ui/components/SearchBar';
import Tabs from '#ui/components/Tabs';
import { useAccountId, useFeedback, usePaged } from '#ui/hooks';
import { formatDateTime, intParam } from '#ui/utils';

const TABS = ['会员等级', '会员列表'] as const;
type Tab = (typeof TABS)[number];

/** 折扣千分比 → 「折」：900 → 9.0 折。 */
const discountToZhe = (discount: number) => `${(discount / 100).toFixed(1)} 折`;

/** 新建/编辑共用的等级表单（折扣以「折」字符串编辑，提交时 ×100 → 千分比）。 */
interface LevelFormState {
  name: string;
  /** 等级值（升序数值） */
  level: number;
  /** 折 */
  discount: string;
  /** 升级门槛（积分） */
  threshold: number;
  /** 积分倍率（1 = 1 倍） */
  points_ratio: number;
}

const EMPTY_LEVEL_FORM: LevelFormState = {
  name: '',
  level: 1,
  discount: '9.5',
  threshold: 0,
  points_ratio: 1,
};

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

function MemberCard() {
  const { accountId, ready, accountName, onAccountChange } = useAccountId();
  const feedback = useFeedback();

  const [tab, setTab] = createSignal<Tab>('会员等级');
  const [levelKeyword, setLevelKeyword] = createSignal<SearchValues>({});
  const [memberFilters, setMemberFilters] = createSignal<SearchValues>({});

  // 等级 新建/编辑
  const [formOpen, setFormOpen] = createSignal(false);
  const [editing, setEditing] = createSignal<MemberCardLevelItem | null>(null);
  const [form, setForm] = createSignal<LevelFormState>({ ...EMPTY_LEVEL_FORM });
  const [formSubmitting, setFormSubmitting] = createSignal(false);
  const [formError, setFormError] = createSignal<string | null>(null);

  // 会员详情弹窗
  const [detail, setDetail] = createSignal<MemberAccountItem | null>(null);
  const [detailView, setDetailView] = createSignal<MemberView | null>(null);
  const [detailLoading, setDetailLoading] = createSignal(false);
  const [detailError, setDetailError] = createSignal<string | null>(null);

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

  /** 等级行 id → 名称，供会员列表「等级」列提示（等级可能不在当前分页/筛选内，缺失时回退显示 id）。 */
  const levelNameById = createMemo(() => {
    const map = new Map<number, string>();
    for (const l of levels.items()) map.set(l.id, l.name);
    return map;
  });

  const setFormField = <K extends keyof LevelFormState>(key: K, value: LevelFormState[K]) => {
    setForm((prev) => ({ ...prev, [key]: value }));
  };

  const closeLevelForm = () => {
    setFormOpen(false);
    setEditing(null);
    setForm({ ...EMPTY_LEVEL_FORM });
  };

  const closeDetail = () => {
    setDetail(null);
    setDetailView(null);
    setDetailError(null);
  };

  // 账号切换：关闭所有弹窗并复位表单，列表由 usePaged 的 watch 自动回到第 1 页。
  onAccountChange(() => {
    closeLevelForm();
    closeDetail();
  });

  const openCreate = () => {
    setFormError(null);
    setEditing(null);
    setForm({ ...EMPTY_LEVEL_FORM });
    setFormOpen(true);
  };

  const openEdit = (row: MemberCardLevelItem) => {
    setFormError(null);
    setEditing(row);
    setForm({
      name: row.name,
      level: row.level,
      discount: String(row.discount / 100),
      threshold: row.threshold,
      points_ratio: row.points_ratio / 100,
    });
    setFormOpen(true);
  };

  const onFormSubmit = async () => {
    if (formSubmitting() || !ready()) return;
    const current = form();
    const name = current.name.trim();
    const discountZhe = Number(current.discount);
    if (!name) {
      setFormError('等级名称不能为空');
      return;
    }
    if (!Number.isFinite(discountZhe) || discountZhe < 0.1 || discountZhe > 10) {
      setFormError('折扣需在 0.1 ~ 10 折之间');
      return;
    }
    // 单位换算与原有新增逻辑一致：折扣/积分倍率均 ×100 存为整数。
    const body = {
      name,
      level: current.level,
      discount: Math.round(discountZhe * 100),
      threshold: current.threshold,
      points_ratio: Math.round(current.points_ratio * 100),
      // 编辑时保留原启停状态（PUT 为整体更新），新建默认启用。
      status: editing()?.status ?? 1,
    };
    setFormSubmitting(true);
    setFormError(null);
    try {
      if (editing()) {
        await updateMemberLevel(editing()!.id, body);
      } else {
        await createMemberLevel({ account_id: accountId(), ...body });
      }
      setFormOpen(false);
      feedback.toast(editing() ? '会员等级已更新' : '会员等级已创建');
      void levels.refresh();
    } catch (err) {
      setFormError(err instanceof Error ? err.message : '保存失败，请稍后重试');
    } finally {
      setFormSubmitting(false);
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

  const onDeleteLevel = (row: MemberCardLevelItem) =>
    feedback.runAction({
      confirm: {
        title: '删除等级',
        message: `确定删除等级「${row.name}」吗？等级下仍有会员时将无法删除，需先为会员迁移其他等级。`,
        danger: true,
      },
      action: () => deleteMemberLevel(row.id),
      success: '等级已删除',
      onDone: () => void levels.refresh(),
    });

  const loadDetail = async (openid: string) => {
    setDetailError(null);
    setDetailView(null);
    setDetailLoading(true);
    try {
      setDetailView(await getMemberView(accountId(), openid));
    } catch (err) {
      setDetailError(err instanceof Error ? err.message : '查询失败，请稍后重试');
    } finally {
      setDetailLoading(false);
    }
  };

  /** 详情弹窗打开后（开卡/调积分成功后）静默刷新，避免整窗闪烁。 */
  const refreshDetail = async (openid: string) => {
    try {
      setDetailView(await getMemberView(accountId(), openid));
    } catch (err) {
      feedback.toast(err instanceof Error ? err.message : '查询失败', 'error');
    }
  };

  const openDetail = (row: MemberAccountItem) => {
    setDetail(row);
    void loadDetail(row.openid);
  };

  const onOpenCard = () => {
    const openid = detail()?.openid;
    if (!openid || !ready()) return;
    return feedback.runAction({
      confirm: { title: '开卡', message: `确定为「${openid}」开通会员卡吗？` },
      action: () => openMemberCard(accountId(), openid),
      success: '开卡成功',
      onDone: () => {
        void refreshDetail(openid);
        void members.refresh();
      },
    });
  };

  const onAdjustPoints = (delta: number) => {
    const openid = detail()?.openid;
    if (!openid || !ready()) return;
    return feedback.runAction({
      confirm: {
        title: '调整积分',
        message: `确定为「${openid}」${delta > 0 ? '增加' : '扣减'} ${Math.abs(delta)} 积分吗？`,
      },
      action: () => adjustMemberPoints(accountId(), openid, delta),
      success: '积分已调整',
      onDone: () => {
        void refreshDetail(openid);
        void members.refresh();
      },
    });
  };

  const levelColumns: Column<MemberCardLevelItem>[] = [
    { key: 'name', title: '名称', render: (r) => <span class="font-medium">{r.name}</span> },
    { key: 'level', title: '等级', render: (r) => <span class="font-mono text-xs">Lv.{r.level}</span> },
    { key: 'discount', title: '折扣', render: (r) => discountToZhe(r.discount) },
    { key: 'threshold', title: '升级门槛', render: (r) => `${r.threshold} 积分` },
    { key: 'points_ratio', title: '积分倍率', render: (r) => `${r.points_ratio / 100}x` },
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
    {
      key: 'level_id',
      title: '等级',
      render: (r) => {
        const name = levelNameById().get(r.level_id);
        return <span title={name}>{name ?? `#${r.level_id}`}</span>;
      },
    },
    { key: 'points', title: '积分', render: (r) => <span class="font-semibold">{r.points}</span> },
    { key: 'total_points', title: '累计积分', render: (r) => r.total_points },
    {
      key: 'created_at',
      title: '开卡时间',
      render: (r) => <span class="text-sm text-base-content/70">{formatDateTime(r.created_at)}</span>,
    },
  ];

  return (
    <div class="space-y-4">
      <div>
        <h2 class="text-xl font-semibold">会员卡</h2>
        <p class="text-sm text-base-content/60">卡等级管理与会员积分账户</p>
      </div>

      <AccountRequiredBanner />

      <Tabs tabs={[...TABS]} active={tab()} onChange={setTab} />

      <Show when={tab() === '会员等级'}>
        <AdminCrudPage
          title="会员等级"
          description={ready() ? `当前公众号：${accountName()}` : undefined}
          total={levels.total()}
          onCreate={ready() ? openCreate : undefined}
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
              <>
                <button type="button" class="btn btn-ghost btn-xs" onClick={() => openEdit(row)}>
                  编辑
                </button>
                <button
                  type="button"
                  class="btn btn-ghost btn-xs"
                  onClick={() => void onToggleLevelStatus(row)}
                >
                  {row.status === 1 ? '停用' : '启用'}
                </button>
                <button type="button" class="btn btn-ghost btn-xs text-error" onClick={() => void onDeleteLevel(row)}>
                  删除
                </button>
              </>
            )}
          />
        </AdminCrudPage>
      </Show>

      <Show when={tab() === '会员列表'}>
        <AdminCrudPage
          title="会员列表"
          description="已办卡粉丝及其积分账户"
          total={members.total()}
          onRefresh={() => void members.refresh()}
          search={
            <SearchBar
              fields={[{ kind: 'text', key: 'keyword', label: '粉丝 openid', placeholder: '输入 openid' }]}
              loading={members.loading()}
              onSearch={setMemberFilters}
            />
          }
        >
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
              <button type="button" class="btn btn-ghost btn-xs" onClick={() => openDetail(row)}>
                详情
              </button>
            )}
          />
        </AdminCrudPage>
      </Show>

      <FormModal
        open={formOpen()}
        title={editing() ? `编辑会员等级 #${editing()!.id}` : '新增会员等级'}
        description="折扣按「折」填写（如 9.5 表示 9.5 折），保存时自动转为千分比"
        onSubmit={onFormSubmit}
        onClose={closeLevelForm}
        submitting={formSubmitting()}
        error={formError()}
        submitLabel={editing() ? '保存修改' : '创建'}
      >
        <FormField label="等级名称" required>
          <input
            type="text"
            class="input input-bordered input-sm w-full"
            placeholder="例如：黄金会员"
            value={form().name}
            onInput={(e) => setFormField('name', e.currentTarget.value)}
            required
          />
        </FormField>
        <div class="grid grid-cols-2 gap-3">
          <FormField label="等级值" required hint="数值越大等级越高，从 1 起">
            <input
              type="number"
              min={1}
              step={1}
              class="input input-bordered input-sm w-full"
              value={form().level}
              onInput={(e) => setFormField('level', Math.max(1, Math.floor(Number(e.currentTarget.value) || 1)))}
              required
            />
          </FormField>
          <FormField label="折扣（折）" required hint="范围 0.1 ~ 10">
            <input
              type="number"
              step={0.1}
              min={0.1}
              max={10}
              class="input input-bordered input-sm w-full"
              value={form().discount}
              onInput={(e) => setFormField('discount', e.currentTarget.value)}
            />
          </FormField>
        </div>
        <div class="grid grid-cols-2 gap-3">
          <FormField label="升级门槛（积分）" hint="累计积分达到即升级，0 为入门等级">
            <input
              type="number"
              min={0}
              class="input input-bordered input-sm w-full"
              value={form().threshold}
              onInput={(e) => setFormField('threshold', Math.max(0, Math.floor(Number(e.currentTarget.value) || 0)))}
            />
          </FormField>
          <FormField label="积分倍率" hint="消费 1 元获得积分，如 1.5 表示 1.5 倍">
            <input
              type="number"
              step={0.1}
              min={0}
              class="input input-bordered input-sm w-full"
              value={form().points_ratio}
              onInput={(e) => setFormField('points_ratio', Math.max(0, Number(e.currentTarget.value) || 0))}
            />
          </FormField>
        </div>
      </FormModal>

      <BaseModal
        open={detail() != null}
        title={detail() ? `会员详情 · ${detail()!.openid}` : '会员详情'}
        onClose={closeDetail}
        size="md"
      >
        <Show when={detail() && detailLoading()}>
          <div class="flex min-h-40 items-center justify-center">
            <span class="loading loading-spinner loading-md text-primary" />
          </div>
        </Show>

        <Show when={detail() && !detailLoading() && detailError()}>
          <div class="flex min-h-40 flex-col items-center justify-center gap-3">
            <div role="alert" class="alert alert-error w-full py-2 text-sm">
              {detailError()}
            </div>
            <button type="button" class="btn btn-ghost btn-sm" onClick={closeDetail}>
              关闭
            </button>
          </div>
        </Show>

        <Show when={detail() && !detailLoading() && !detailError() && detailView() == null}>
          <div class="flex min-h-48 flex-col items-center justify-center gap-3">
            <p class="text-sm text-base-content/50">该粉丝尚未办理会员卡</p>
            <button type="button" class="btn btn-primary btn-sm" onClick={() => void onOpenCard()}>
              开卡
            </button>
          </div>
        </Show>

        <Show when={detail() && !detailLoading() && !detailError() && detailView()}>
          {(view) => (
            <div class="space-y-4">
              <div class="rounded-lg border border-base-300 bg-base-200/50 p-4">
                <dl class="grid grid-cols-2 gap-x-4 gap-y-3 text-sm">
                  <div>
                    <dt class="text-xs text-base-content/50">粉丝 openid</dt>
                    <dd class="font-mono text-xs">{view().openid}</dd>
                  </div>
                  <div>
                    <dt class="text-xs text-base-content/50">会员等级</dt>
                    <dd class="font-medium">
                      {view().level_name}
                      <span class="ml-1 text-xs text-base-content/50">Lv.{view().level}</span>
                    </dd>
                  </div>
                  <div>
                    <dt class="text-xs text-base-content/50">折扣</dt>
                    <dd>{discountToZhe(view().discount)}</dd>
                  </div>
                  <div>
                    <dt class="text-xs text-base-content/50">开卡时间</dt>
                    <dd class="text-xs text-base-content/70">{formatDateTime(view().created_at)}</dd>
                  </div>
                  <div>
                    <dt class="text-xs text-base-content/50">积分余额</dt>
                    <dd class="font-semibold">{view().points}</dd>
                  </div>
                  <div>
                    <dt class="text-xs text-base-content/50">累计积分</dt>
                    <dd>{view().total_points}</dd>
                  </div>
                </dl>
                <div class="mt-4 flex items-center justify-end gap-2 border-t border-base-300 pt-3">
                  <span class="mr-auto text-xs text-base-content/50">积分调整</span>
                  <button
                    type="button"
                    class="btn btn-outline btn-primary btn-xs"
                    onClick={() => void onAdjustPoints(100)}
                  >
                    +100
                  </button>
                  <button
                    type="button"
                    class="btn btn-outline btn-error btn-xs"
                    onClick={() => void onAdjustPoints(-100)}
                  >
                    -100
                  </button>
                </div>
              </div>
              <div class="flex justify-end">
                <button type="button" class="btn btn-ghost btn-sm" onClick={closeDetail}>
                  关闭
                </button>
              </div>
            </div>
          )}
        </Show>
      </BaseModal>
    </div>
  );
}

export default MemberCard;
