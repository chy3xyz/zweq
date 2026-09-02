import { For, Show, createSignal } from 'solid-js';

import {
  createVote,
  deleteVote,
  getVoteResults,
  listVotes,
  updateVote,
  type VoteItem,
} from '#ui/api';
import AccountRequiredBanner from '#ui/components/AccountRequiredBanner';
import AdminCrudPage from '#ui/components/AdminCrudPage';
import DataTable, { type Column } from '#ui/components/DataTable';
import FormField from '#ui/components/FormField';
import FormModal from '#ui/components/FormModal';
import Tabs from '#ui/components/Tabs';
import { useAccountId, useFeedback, usePaged } from '#ui/hooks';
import { formatDateTime } from '#ui/utils';

const TABS = ['投票活动', '投票统计'] as const;
type Tab = (typeof TABS)[number];

const PAGE_SIZE = 20;

/** 新建/编辑共用的投票表单（选项文本域留原始内容，提交时才拆分校验）。 */
interface VoteFormState {
  title: string;
  /** 每行一个选项（提交时按换行/逗号拆分）。 */
  optionsText: string;
  /** 结束时间 datetime-local 原始输入值（提交时解析为 epoch 秒，空 = 不限）。 */
  endAtInput: string;
}

const EMPTY_FORM: VoteFormState = {
  title: '',
  optionsText: '',
  endAtInput: '',
};

/** `options_json`（JSON 字符串数组）→ 选项列表；解析失败兜底空数组。 */
function parseVoteOptions(json: string): string[] {
  if (!json) return [];
  try {
    const parsed: unknown = JSON.parse(json);
    return Array.isArray(parsed) ? parsed.filter((v): v is string => typeof v === 'string') : [];
  } catch {
    return [];
  }
}

/** 文本域内容 → 选项：按换行/中英文逗号拆分、去空白、去空项。 */
function splitVoteOptions(text: string): string[] {
  return text
    .split(/[\n,，]/)
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

/** epoch 秒 → datetime-local 输入值（0 → 空串）。 */
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

interface VoteStats {
  vote: VoteItem;
  options: string[];
  tally: number[];
  total: number;
}

function Vote() {
  const { accountId, ready, accountName, onAccountChange } = useAccountId();
  const feedback = useFeedback();

  const [tab, setTab] = createSignal<Tab>('投票活动');

  // 新建/编辑共用表单弹窗（editing 非空 = 编辑态）。
  const [formOpen, setFormOpen] = createSignal(false);
  const [editing, setEditing] = createSignal<VoteItem | null>(null);
  const [form, setForm] = createSignal<VoteFormState>({ ...EMPTY_FORM });
  const [formSubmitting, setFormSubmitting] = createSignal(false);
  const [formError, setFormError] = createSignal<string | null>(null);

  // 只读统计弹窗。
  const [statsOpen, setStatsOpen] = createSignal(false);
  const [stats, setStats] = createSignal<VoteStats | null>(null);
  const [statsLoading, setStatsLoading] = createSignal(false);

  const paged = usePaged<VoteItem>(
    (page, pageSize) => listVotes(accountId(), page, pageSize),
    PAGE_SIZE,
    accountId,
  );

  const statsPaged = usePaged<VoteItem>(
    (page, pageSize) => listVotes(accountId(), page, pageSize),
    PAGE_SIZE,
    accountId,
  );

  const resetModals = () => {
    setFormOpen(false);
    setEditing(null);
    setForm({ ...EMPTY_FORM });
    setFormError(null);
    setStatsOpen(false);
    setStats(null);
  };

  // 账号切换：关闭两分区弹窗并重置表单，列表由 usePaged 的 watch 自动回到第 1 页。
  onAccountChange(() => {
    resetModals();
  });

  const setFormField = <K extends keyof VoteFormState>(key: K, value: VoteFormState[K]) => {
    setForm((prev) => ({ ...prev, [key]: value }));
  };

  const openCreate = () => {
    setFormError(null);
    setEditing(null);
    setForm({ ...EMPTY_FORM });
    setFormOpen(true);
  };

  const openEdit = (row: VoteItem) => {
    setFormError(null);
    setEditing(row);
    setForm({
      title: row.title,
      optionsText: parseVoteOptions(row.options_json).join('\n'),
      endAtInput: toLocalInput(row.end_at),
    });
    setFormOpen(true);
  };

  const onFormSubmit = async () => {
    if (formSubmitting() || !ready()) return;
    const current = form();
    const title = current.title.trim();
    if (!title) {
      setFormError('题目不能为空');
      return;
    }
    const options = splitVoteOptions(current.optionsText);
    if (options.length < 2) {
      setFormError('请至少填写两个选项（每行一个，支持回车/逗号分隔）');
      return;
    }
    // end_at 在提交时统一解析（0 = 不限），避免 datetime-local 输入中途被回填清空。
    const end_at = parseLocalInput(current.endAtInput);
    setFormSubmitting(true);
    setFormError(null);
    try {
      if (editing()) {
        await updateVote(editing()!.id, { title, options, end_at });
      } else {
        await createVote({ account_id: accountId(), title, options, end_at });
      }
      setFormOpen(false);
      feedback.toast(editing() ? '投票已更新' : '投票已创建');
      // 两个分区展示同一批投票，创建/更新/删除后同步刷新。
      void paged.refresh();
      void statsPaged.refresh();
    } catch (err) {
      setFormError(err instanceof Error ? err.message : '保存失败，请稍后重试');
    } finally {
      setFormSubmitting(false);
    }
  };

  const onDelete = (row: VoteItem) =>
    feedback.runAction({
      confirm: { title: '删除投票', message: `确定删除投票「${row.title}」吗？`, danger: true },
      action: () => deleteVote(row.id),
      success: '投票已删除',
      onDone: () => {
        void paged.refresh();
        void statsPaged.refresh();
      },
    });

  const openStats = async (row: VoteItem) => {
    if (statsLoading()) return;
    setStatsLoading(true);
    try {
      const tally = await getVoteResults(row.id);
      const options = parseVoteOptions(row.options_json);
      setStats({
        vote: row,
        options,
        tally,
        total: tally.reduce((sum, n) => sum + n, 0),
      });
      setStatsOpen(true);
    } catch (err) {
      feedback.toast(err instanceof Error ? err.message : '加载统计失败，请稍后重试', 'error');
    } finally {
      setStatsLoading(false);
    }
  };

  const activityColumns: Column<VoteItem>[] = [
    { key: 'title', title: '标题', render: (r) => <span class="font-medium">{r.title}</span> },
    {
      key: 'options_json',
      title: '选项摘要',
      render: (r) => {
        const options = parseVoteOptions(r.options_json);
        if (options.length === 0) {
          return <span class="text-base-content/40">-</span>;
        }
        const summary = options.join('、');
        return (
          <span
            class="inline-block max-w-xs truncate align-middle text-sm text-base-content/70"
            title={summary}
          >
            {summary}
          </span>
        );
      },
    },
    {
      key: 'end_at',
      title: '结束时间',
      render: (r) =>
        r.end_at > 0 ? (
          <span class="text-sm text-base-content/70">{formatDateTime(r.end_at)}</span>
        ) : (
          <span class="text-base-content/40">不限</span>
        ),
    },
    {
      key: 'created_at',
      title: '创建时间',
      render: (r) => <span class="text-sm text-base-content/70">{formatDateTime(r.created_at)}</span>,
    },
  ];

  const statsColumns: Column<VoteItem>[] = [
    { key: 'title', title: '标题', render: (r) => <span class="font-medium">{r.title}</span> },
    {
      key: 'created_at',
      title: '创建时间',
      render: (r) => <span class="text-sm text-base-content/70">{formatDateTime(r.created_at)}</span>,
    },
  ];

  return (
    <div class="space-y-4">
      <div>
        <h2 class="text-xl font-semibold">投票</h2>
        <p class="text-sm text-base-content/60">投票活动创建、编辑与票数统计</p>
      </div>

      <AccountRequiredBanner />

      <Tabs tabs={[...TABS]} active={tab()} onChange={setTab} />

      <Show when={tab() === '投票活动'}>
        <AdminCrudPage
          title="投票活动"
          description={ready() ? `当前公众号：${accountName()}` : undefined}
          total={paged.total()}
          onCreate={ready() ? openCreate : undefined}
          createLabel="新增投票"
          onRefresh={() => void paged.refresh()}
        >
          <DataTable
            columns={activityColumns}
            rows={paged.items()}
            rowKey={(r) => r.id}
            total={paged.total()}
            page={paged.page()}
            totalPages={paged.totalPages()}
            pageSize={paged.pageSize()}
            loading={paged.loading()}
            error={paged.error()}
            emptyText="暂无投票"
            onPageChange={(p) => void paged.reload(p)}
            onPageSizeChange={(size) => paged.setPageSize(size)}
            actions={(row) => (
              <>
                <button type="button" class="btn btn-ghost btn-xs" onClick={() => openEdit(row)}>
                  编辑
                </button>
                <button type="button" class="btn btn-ghost btn-xs text-error" onClick={() => void onDelete(row)}>
                  删除
                </button>
              </>
            )}
          />
        </AdminCrudPage>
      </Show>

      <Show when={tab() === '投票统计'}>
        <AdminCrudPage
          title="投票统计"
          description="各投票主题下每个选项的票数与占比"
          total={statsPaged.total()}
          onRefresh={() => void statsPaged.refresh()}
        >
          <DataTable
            columns={statsColumns}
            rows={statsPaged.items()}
            rowKey={(r) => r.id}
            total={statsPaged.total()}
            page={statsPaged.page()}
            totalPages={statsPaged.totalPages()}
            pageSize={statsPaged.pageSize()}
            loading={statsPaged.loading()}
            error={statsPaged.error()}
            emptyText="暂无投票"
            onPageChange={(p) => void statsPaged.reload(p)}
            onPageSizeChange={(size) => statsPaged.setPageSize(size)}
            actions={(row) => (
              <button
                type="button"
                class="btn btn-ghost btn-xs text-primary"
                disabled={statsLoading()}
                onClick={() => void openStats(row)}
              >
                统计
              </button>
            )}
          />
        </AdminCrudPage>
      </Show>

      <FormModal
        open={formOpen()}
        title={editing() ? `编辑投票 #${editing()!.id}` : '新增投票'}
        onSubmit={onFormSubmit}
        onClose={() => setFormOpen(false)}
        submitting={formSubmitting()}
        error={formError()}
        submitLabel={editing() ? '保存修改' : '创建'}
      >
        <FormField label="题目" required>
          <input
            type="text"
            class="input input-bordered input-sm w-full"
            placeholder="例如：你最喜欢的颜色是？"
            value={form().title}
            onInput={(e) => setFormField('title', e.currentTarget.value)}
            required
          />
        </FormField>
        <FormField label="选项" required hint="每行一个选项，也支持用逗号分隔；至少两个选项">
          <textarea
            class="textarea textarea-bordered textarea-sm h-24 w-full"
            placeholder="每行一个选项，支持回车/逗号分隔"
            value={form().optionsText}
            onInput={(e) => setFormField('optionsText', e.currentTarget.value)}
            required
          />
        </FormField>
        <FormField label="结束时间" hint="留空表示不限截止时间">
          <input
            type="datetime-local"
            class="input input-bordered input-sm w-full"
            value={form().endAtInput}
            onInput={(e) => setFormField('endAtInput', e.currentTarget.value)}
          />
        </FormField>
      </FormModal>

      <FormModal open={statsOpen()} title="投票统计" onClose={() => setStatsOpen(false)}>
        <Show when={stats()} fallback={<p class="text-sm text-base-content/50">加载中…</p>}>
          {(data) => (
            <>
              <FormField label="题目">
                <p class="text-sm font-medium">{data().vote.title}</p>
              </FormField>
              <Show
                when={data().total > 0}
                fallback={<p class="text-sm text-base-content/50">暂无投票记录</p>}
              >
                <FormField label="选项票数" hint={`共 ${data().total} 票`}>
                  <div class="space-y-3">
                    <For each={data().options}>
                      {(option, i) => {
                        const count = data().tally[i()] ?? 0;
                        const pct = data().total > 0 ? Math.round((count / data().total) * 100) : 0;
                        return (
                          <div>
                            <div class="flex items-baseline justify-between gap-3 text-sm">
                              <span>{option}</span>
                              <span class="shrink-0 text-xs text-base-content/60">
                                {count} 票 · {pct}%
                              </span>
                            </div>
                            <progress class="progress progress-primary mt-1 h-2" value={pct} max={100} />
                          </div>
                        );
                      }}
                    </For>
                  </div>
                </FormField>
              </Show>
            </>
          )}
        </Show>
      </FormModal>
    </div>
  );
}

export default Vote;
