import { For, Show, createMemo, createSignal } from 'solid-js';

import {
  addKeyword,
  addReply,
  createRule,
  deleteRule,
  listKeywords,
  listReplies,
  listRules,
  removeKeyword,
  removeReply,
  updateRule,
  type AddReplyRequest,
  type KeywordItem,
  type MatchType,
  type ReplyItem,
  type ReplyType,
  type RuleItem,
} from '#ui/api';
import { fileUrl, type FileItem } from '#ui/api/file/types';
import AccountRequiredBanner from '#ui/components/AccountRequiredBanner';
import AdminCrudPage from '#ui/components/AdminCrudPage';
import BaseModal from '#ui/components/BaseModal';
import DataTable, { type Column } from '#ui/components/DataTable';
import FormField from '#ui/components/FormField';
import FormModal from '#ui/components/FormModal';
import ImageManager from '#ui/components/ImageManager';
import SearchBar, { type SearchField, type SearchValues } from '#ui/components/SearchBar';
import Tabs from '#ui/components/Tabs';
import { useAccountId, useFeedback, usePaged } from '#ui/hooks';
import { formatDateTime } from '#ui/utils';

const PAGE_SIZE = 20;
const CONFIG_TABS = ['关键词', '回复'] as const;

const SEARCH_FIELDS: SearchField[] = [
  { kind: 'text', key: 'keyword', label: '规则名称', placeholder: '输入规则名称关键字' },
];

const MATCH_OPTIONS: { value: MatchType; label: string }[] = [
  { value: 'contain', label: '包含' },
  { value: 'full', label: '完全匹配' },
];

const STATUS_OPTIONS: { value: RuleItem['status']; label: string }[] = [
  { value: 'active', label: '启用' },
  { value: 'disabled', label: '停用' },
];

const REPLY_TYPE_OPTIONS: { value: ReplyType; label: string }[] = [
  { value: 'text', label: '文本' },
  { value: 'news', label: '图文' },
];

function Rules() {
  const { accountId, onAccountChange } = useAccountId();
  const feedback = useFeedback();
  const [filters, setFilters] = createSignal<SearchValues>({});

  const paged = usePaged<RuleItem>(
    (page, pageSize) => listRules(page, pageSize, accountId()),
    PAGE_SIZE,
    accountId,
  );

  // Rule create/edit modal
  const [ruleOpen, setRuleOpen] = createSignal(false);
  const [editingRule, setEditingRule] = createSignal<RuleItem | null>(null);
  const [name, setName] = createSignal('');
  const [status, setStatus] = createSignal<RuleItem['status']>('active');
  const [saving, setSaving] = createSignal(false);
  const [ruleError, setRuleError] = createSignal<string | null>(null);

  // Rule configuration modal
  const [configOpen, setConfigOpen] = createSignal(false);
  const [activeRule, setActiveRule] = createSignal<RuleItem | null>(null);
  const [activeTab, setActiveTab] = createSignal<(typeof CONFIG_TABS)[number]>('关键词');
  const [keywords, setKeywords] = createSignal<KeywordItem[]>([]);
  const [replies, setReplies] = createSignal<ReplyItem[]>([]);
  const [kwInput, setKwInput] = createSignal('');
  const [kwMatch, setKwMatch] = createSignal<MatchType>('contain');
  const [replyType, setReplyType] = createSignal<ReplyType>('text');
  const [replyText, setReplyText] = createSignal('');
  const [newsTitle, setNewsTitle] = createSignal('');
  const [newsDesc, setNewsDesc] = createSignal('');
  const [newsUrl, setNewsUrl] = createSignal('');
  const [newsPicUrl, setNewsPicUrl] = createSignal('');
  const [imageOpen, setImageOpen] = createSignal(false);
  const [configLoading, setConfigLoading] = createSignal(false);
  const [configError, setConfigError] = createSignal<string | null>(null);

  onAccountChange(() => {
    setRuleOpen(false);
    setConfigOpen(false);
  });

  const filteredItems = createMemo(() => {
    const keyword = filters().keyword?.trim().toLowerCase();
    if (!keyword) return paged.items();
    return paged.items().filter((r) => r.name.toLowerCase().includes(keyword));
  });

  const openCreateRule = () => {
    setEditingRule(null);
    setName('');
    setStatus('active');
    setRuleError(null);
    setRuleOpen(true);
  };

  const openEditRule = (rule: RuleItem) => {
    setEditingRule(rule);
    setName(rule.name);
    setStatus(rule.status);
    setRuleError(null);
    setRuleOpen(true);
  };

  const openConfig = async (rule: RuleItem) => {
    setActiveRule(rule);
    setActiveTab('关键词');
    setConfigError(null);
    setConfigLoading(true);
    setConfigOpen(true);
    try {
      const [kws, rps] = await Promise.all([listKeywords(rule.id), listReplies(rule.id)]);
      setKeywords(kws);
      setReplies(rps);
    } catch (err) {
      setConfigError(err instanceof Error ? err.message : '加载配置失败');
    } finally {
      setConfigLoading(false);
    }
  };

  const closeConfig = () => {
    setConfigOpen(false);
    setActiveRule(null);
    setKeywords([]);
    setReplies([]);
    setKwInput('');
    setReplyText('');
    setNewsTitle('');
    setNewsDesc('');
    setNewsUrl('');
    setNewsPicUrl('');
    setConfigError(null);
  };

  const onSaveRule = async (e: SubmitEvent) => {
    e.preventDefault();
    if (saving() || accountId() === 0) return;
    setSaving(true);
    setRuleError(null);
    try {
      const n = name().trim();
      if (!n) throw new Error('规则名称不能为空');
      const editing = editingRule();
      if (editing) {
        await updateRule(editing.id, { name: n, status: status() });
        feedback.toast('规则已更新');
      } else {
        await createRule({ account_id: accountId(), name: n });
        feedback.toast('规则已创建');
      }
      setRuleOpen(false);
      void paged.reload();
    } catch (err) {
      setRuleError(err instanceof Error ? err.message : '保存失败，请稍后重试');
    } finally {
      setSaving(false);
    }
  };

  const loadKeywords = async (ruleId: number) => {
    setKeywords(await listKeywords(ruleId));
  };

  const loadReplies = async (ruleId: number) => {
    setReplies(await listReplies(ruleId));
  };

  const onAddKeyword = async () => {
    const ruleId = activeRule()?.id;
    if (!ruleId) return;
    const keyword = kwInput().trim();
    if (!keyword) {
      setConfigError('关键词不能为空');
      return;
    }
    setConfigLoading(true);
    setConfigError(null);
    try {
      await addKeyword(ruleId, { keyword, match_type: kwMatch() });
      setKwInput('');
      await loadKeywords(ruleId);
      feedback.toast('关键词已添加');
    } catch (err) {
      setConfigError(err instanceof Error ? err.message : '添加关键词失败');
    } finally {
      setConfigLoading(false);
    }
  };

  const onRemoveKeyword = (k: KeywordItem) => {
    const ruleId = activeRule()?.id;
    if (!ruleId) return;
    void feedback.runAction({
      confirm: { title: '删除关键词', message: `确定删除关键词「${k.keyword}」吗？`, danger: true },
      action: () => removeKeyword(ruleId, k.id),
      success: '关键词已删除',
      onDone: () => void loadKeywords(ruleId),
    });
  };

  const buildReplyBody = (): AddReplyRequest => {
    if (replyType() === 'text') {
      return { reply_type: 'text', content: replyText().trim() };
    }
    return {
      reply_type: 'news',
      news_title: newsTitle().trim(),
      news_description: newsDesc().trim(),
      news_url: newsUrl().trim(),
      news_pic_url: newsPicUrl().trim(),
    };
  };

  const onAddReply = async () => {
    const ruleId = activeRule()?.id;
    if (!ruleId) return;
    const body = buildReplyBody();
    if (body.reply_type === 'text' && !body.content) {
      setConfigError('文本回复内容不能为空');
      return;
    }
    if (body.reply_type === 'news' && !body.news_title) {
      setConfigError('图文回复标题不能为空');
      return;
    }
    setConfigLoading(true);
    setConfigError(null);
    try {
      await addReply(ruleId, body);
      setReplyText('');
      setNewsTitle('');
      setNewsDesc('');
      setNewsUrl('');
      setNewsPicUrl('');
      await loadReplies(ruleId);
      feedback.toast('回复已添加');
    } catch (err) {
      setConfigError(err instanceof Error ? err.message : '添加回复失败');
    } finally {
      setConfigLoading(false);
    }
  };

  const onRemoveReply = (r: ReplyItem) => {
    const ruleId = activeRule()?.id;
    if (!ruleId) return;
    const label = r.reply_type === 'text' ? r.content : r.news_title;
    void feedback.runAction({
      confirm: { title: '删除回复', message: `确定删除回复「${label || ''}」吗？`, danger: true },
      action: () => removeReply(ruleId, r.id),
      success: '回复已删除',
      onDone: () => void loadReplies(ruleId),
    });
  };

  const onDeleteRule = (rule: RuleItem) =>
    feedback.runAction({
      confirm: {
        title: '删除规则',
        message: `确定删除规则「${rule.name}」吗？该操作不可恢复。`,
        danger: true,
      },
      action: () => deleteRule(rule.id),
      success: `规则「${rule.name}」已删除`,
      onDone: () => {
        if (activeRule()?.id === rule.id) setConfigOpen(false);
        void paged.refresh();
      },
    });

  const onSelectImage = (items: FileItem[]) => {
    if (items[0]) setNewsPicUrl(fileUrl(items[0]));
  };

  const columns: Column<RuleItem>[] = [
    { key: 'id', title: 'ID', render: (r) => <span class="font-mono text-xs">{r.id}</span> },
    { key: 'name', title: '规则名称', render: (r) => <span class="font-medium">{r.name}</span> },
    {
      key: 'status',
      title: '状态',
      render: (r) => (
        <span class={`badge badge-sm ${r.status === 'active' ? 'badge-success' : 'badge-outline'}`}>
          {r.status === 'active' ? '启用' : '停用'}
        </span>
      ),
    },
    {
      key: 'created_at',
      title: '创建时间',
      render: (r) => <span class="text-sm text-base-content/70">{formatDateTime(r.created_at)}</span>,
    },
  ];

  return (
    <AdminCrudPage
      title="自动回复"
      description="关键词规则 — 未命中走 AI 自动回复或默认回复"
      total={paged.total()}
      onCreate={openCreateRule}
      createLabel="新增规则"
      onRefresh={() => void paged.refresh()}
      search={<SearchBar fields={SEARCH_FIELDS} loading={paged.loading()} onSearch={setFilters} />}
    >
      <AccountRequiredBanner />

      <DataTable
        columns={columns}
        rows={filteredItems()}
        rowKey={(r) => r.id}
        total={paged.total()}
        page={paged.page()}
        totalPages={paged.totalPages()}
        pageSize={paged.pageSize()}
        loading={paged.loading()}
        error={paged.error()}
        emptyText="暂无规则"
        onPageChange={(p) => void paged.reload(p)}
        onPageSizeChange={(size) => paged.setPageSize(size)}
        actions={(rule) => (
          <div class="flex justify-end gap-1">
            <button type="button" class="btn btn-ghost btn-xs" onClick={() => openEditRule(rule)}>
              编辑
            </button>
            <button type="button" class="btn btn-ghost btn-xs" onClick={() => void openConfig(rule)}>
              配置
            </button>
            <button type="button" class="btn btn-ghost btn-xs text-error" onClick={() => void onDeleteRule(rule)}>
              删除
            </button>
          </div>
        )}
      />

      <FormModal
        open={ruleOpen()}
        title={editingRule() ? '编辑规则' : '新增规则'}
        onSubmit={onSaveRule}
        onClose={() => setRuleOpen(false)}
        submitting={saving()}
        error={ruleError()}
      >
        <FormField label="规则名称" required>
          <input
            type="text"
            class="input input-bordered input-sm w-full"
            placeholder="例如：问候语"
            value={name()}
            onInput={(e) => setName(e.currentTarget.value)}
            required
          />
        </FormField>
        <FormField label="状态" required>
          <select
            class="select select-bordered select-sm w-full"
            value={status()}
            onChange={(e) => setStatus(e.currentTarget.value as RuleItem['status'])}
          >
            <For each={STATUS_OPTIONS}>
              {(opt) => <option value={opt.value}>{opt.label}</option>}
            </For>
          </select>
        </FormField>
      </FormModal>

      <BaseModal
        open={configOpen()}
        title={`规则配置 — ${activeRule()?.name ?? ''}`}
        onClose={closeConfig}
        size="lg"
      >
        <Show when={configError()}>
          <div role="alert" class="alert alert-error mb-4 py-2 text-sm">
            {configError()}
          </div>
        </Show>

        <Tabs tabs={[...CONFIG_TABS]} active={activeTab()} onChange={setActiveTab} class="mb-4" />

        <Show when={configLoading()}>
          <div class="py-6 text-center text-sm text-base-content/50">
            <span class="loading loading-spinner loading-sm mr-2" />
            加载中…
          </div>
        </Show>

        <Show when={!configLoading() && activeTab() === '关键词'}>
          <div class="space-y-3">
            <div class="flex flex-wrap gap-2">
              <For each={keywords()}>
                {(k) => (
                  <span class="badge badge-outline gap-1">
                    {k.keyword}
                    <span class="text-xs text-base-content/50">{k.match_type === 'full' ? '完全' : '包含'}</span>
                    <button
                      type="button"
                      class="ml-1 text-error"
                      onClick={() => onRemoveKeyword(k)}
                      title="删除"
                    >
                      ×
                    </button>
                  </span>
                )}
              </For>
              <Show when={keywords().length === 0}>
                <span class="text-sm text-base-content/50">暂无关键词</span>
              </Show>
            </div>

            <div class="flex flex-wrap items-end gap-2">
              <FormField label="关键词" class="w-48">
                <input
                  type="text"
                  class="input input-bordered input-sm w-full"
                  placeholder="关键词"
                  value={kwInput()}
                  onInput={(e) => setKwInput(e.currentTarget.value)}
                />
              </FormField>
              <FormField label="匹配方式" class="w-32">
                <select
                  class="select select-bordered select-sm w-full"
                  value={kwMatch()}
                  onChange={(e) => setKwMatch(e.currentTarget.value as MatchType)}
                >
                  <For each={MATCH_OPTIONS}>
                    {(opt) => <option value={opt.value}>{opt.label}</option>}
                  </For>
                </select>
              </FormField>
              <button
                type="button"
                class="btn btn-primary btn-sm"
                disabled={configLoading()}
                onClick={() => void onAddKeyword()}
              >
                添加
              </button>
            </div>
          </div>
        </Show>

        <Show when={!configLoading() && activeTab() === '回复'}>
          <div class="space-y-3">
            <div class="space-y-2">
              <For each={replies()}>
                {(r) => (
                  <div class="flex items-center justify-between rounded bg-base-100 px-3 py-2 text-sm">
                    <div class="min-w-0">
                      <span class="badge badge-sm badge-ghost mr-2">{r.reply_type === 'text' ? '文本' : '图文'}</span>
                      <span class="text-base-content/80">
                        {r.reply_type === 'text' ? r.content : `${r.news_title} ${r.news_url ? `(${r.news_url})` : ''}`}
                      </span>
                    </div>
                    <button
                      type="button"
                      class="btn btn-ghost btn-xs text-error shrink-0"
                      onClick={() => onRemoveReply(r)}
                    >
                      删除
                    </button>
                  </div>
                )}
              </For>
              <Show when={replies().length === 0}>
                <span class="text-sm text-base-content/50">暂无回复</span>
              </Show>
            </div>

            <div class="space-y-3 rounded-lg border border-base-200 bg-base-200/30 p-3">
              <FormField label="回复类型">
                <select
                  class="select select-bordered select-sm w-full"
                  value={replyType()}
                  onChange={(e) => setReplyType(e.currentTarget.value as ReplyType)}
                >
                  <For each={REPLY_TYPE_OPTIONS}>
                    {(opt) => <option value={opt.value}>{opt.label}</option>}
                  </For>
                </select>
              </FormField>

              <Show
                when={replyType() === 'text'}
                fallback={
                  <>
                    <FormField label="标题">
                      <input
                        type="text"
                        class="input input-bordered input-sm w-full"
                        placeholder="图文标题"
                        value={newsTitle()}
                        onInput={(e) => setNewsTitle(e.currentTarget.value)}
                      />
                    </FormField>
                    <FormField label="摘要">
                      <input
                        type="text"
                        class="input input-bordered input-sm w-full"
                        placeholder="图文摘要"
                        value={newsDesc()}
                        onInput={(e) => setNewsDesc(e.currentTarget.value)}
                      />
                    </FormField>
                    <FormField label="跳转链接">
                      <input
                        type="text"
                        class="input input-bordered input-sm w-full"
                        placeholder="https://..."
                        value={newsUrl()}
                        onInput={(e) => setNewsUrl(e.currentTarget.value)}
                      />
                    </FormField>
                    <FormField
                      label="封面图片"
                      labelExtra={
                        <button
                          type="button"
                          class="btn btn-outline btn-xs"
                          onClick={() => setImageOpen(true)}
                        >
                          选择图片
                        </button>
                      }
                    >
                      <input
                        type="text"
                        class="input input-bordered input-sm w-full"
                        placeholder="图片 URL"
                        value={newsPicUrl()}
                        onInput={(e) => setNewsPicUrl(e.currentTarget.value)}
                      />
                    </FormField>
                  </>
                }
              >
                <FormField label="回复内容">
                  <input
                    type="text"
                    class="input input-bordered input-sm w-full"
                    placeholder="回复内容"
                    value={replyText()}
                    onInput={(e) => setReplyText(e.currentTarget.value)}
                  />
                </FormField>
              </Show>

              <div class="flex justify-end">
                <button
                  type="button"
                  class="btn btn-primary btn-sm"
                  disabled={configLoading()}
                  onClick={() => void onAddReply()}
                >
                  添加回复
                </button>
              </div>
            </div>
          </div>
        </Show>
      </BaseModal>

      <ImageManager
        open={imageOpen()}
        onClose={() => setImageOpen(false)}
        onSelect={onSelectImage}
        multiple={false}
        max={1}
      />
    </AdminCrudPage>
  );
}

export default Rules;
