import { For, Show, createSignal } from 'solid-js';

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
  toApiError,
  type KeywordItem,
  type ReplyItem,
  type ReplyType,
  type RuleItem,
} from '#ui/api';
import DataTable, { type Column } from '#ui/components/DataTable';
import { useAccounts } from '#ui/hooks/useAccounts';
import { usePaged } from '#ui/hooks/usePaged';
import { formatDateTime } from '#ui/utils';

const PAGE_SIZE = 20;

function Rules() {
  const accounts = useAccounts();
  const [success, setSuccess] = createSignal<string | null>(null);
  const [nameInput, setNameInput] = createSignal('');
  const [creating, setCreating] = createSignal(false);

  // expanded rule detail
  const [expanded, setExpanded] = createSignal<number | null>(null);
  const [keywords, setKeywords] = createSignal<KeywordItem[]>([]);
  const [replies, setReplies] = createSignal<ReplyItem[]>([]);
  const [kwInput, setKwInput] = createSignal('');
  const [kwMatch, setKwMatch] = createSignal<'full' | 'contain'>('contain');
  const [replyType, setReplyType] = createSignal<ReplyType>('text');
  const [replyText, setReplyText] = createSignal('');
  const [newsTitle, setNewsTitle] = createSignal('');
  const [newsDesc, setNewsDesc] = createSignal('');
  const [newsUrl, setNewsUrl] = createSignal('');

  const accountId = () => accounts.selected() ?? 0;
  const paged = usePaged<RuleItem>((page, pageSize) => listRules(page, pageSize, accountId()), PAGE_SIZE);

  const onAccountChange = (id: number) => {
    accounts.setSelected(id);
    setExpanded(null);
    void paged.reload(1);
  };

  const onCreate = async (e: SubmitEvent) => {
    e.preventDefault();
    if (creating() || accountId() === 0) return;
    setCreating(true);
    setSuccess(null);
    try {
      await createRule({ account_id: accountId(), name: nameInput().trim() });
      setNameInput('');
      setSuccess('规则已创建');
      void paged.reload(1);
    } catch (err) {
      window.alert(toApiError(err).message);
    } finally {
      setCreating(false);
    }
  };

  const openRule = async (rule: RuleItem) => {
    if (expanded() === rule.id) {
      setExpanded(null);
      return;
    }
    setExpanded(rule.id);
    try {
      const [kws, rps] = await Promise.all([listKeywords(rule.id), listReplies(rule.id)]);
      setKeywords(kws);
      setReplies(rps);
    } catch (err) {
      window.alert(toApiError(err).message);
    }
  };

  const onAddKeyword = async (ruleId: number) => {
    try {
      await addKeyword(ruleId, { keyword: kwInput().trim(), match_type: kwMatch() });
      setKwInput('');
      setKeywords(await listKeywords(ruleId));
    } catch (err) {
      window.alert(toApiError(err).message);
    }
  };

  const onRemoveKeyword = async (ruleId: number, kid: number) => {
    try {
      await removeKeyword(ruleId, kid);
      setKeywords(await listKeywords(ruleId));
    } catch (err) {
      window.alert(toApiError(err).message);
    }
  };

  const onAddReply = async (ruleId: number) => {
    try {
      await addReply(ruleId, {
        reply_type: replyType(),
        content: replyType() === 'text' ? replyText().trim() : undefined,
        news_title: replyType() === 'news' ? newsTitle().trim() : undefined,
        news_description: replyType() === 'news' ? newsDesc().trim() : undefined,
        news_url: replyType() === 'news' ? newsUrl().trim() : undefined,
      });
      setReplyText('');
      setNewsTitle('');
      setNewsDesc('');
      setNewsUrl('');
      setReplies(await listReplies(ruleId));
    } catch (err) {
      window.alert(toApiError(err).message);
    }
  };

  const onRemoveReply = async (ruleId: number, rid: number) => {
    try {
      await removeReply(ruleId, rid);
      setReplies(await listReplies(ruleId));
    } catch (err) {
      window.alert(toApiError(err).message);
    }
  };

  const onDeleteRule = async (rule: RuleItem) => {
    if (!window.confirm(`确定删除规则「${rule.name}」吗？`)) return;
    try {
      await deleteRule(rule.id);
      if (expanded() === rule.id) setExpanded(null);
      setSuccess(`规则「${rule.name}」已删除`);
      void paged.reload();
    } catch (err) {
      window.alert(toApiError(err).message);
    }
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
    <div class="space-y-4">
      <div>
        <h2 class="text-xl font-semibold">自动回复</h2>
        <p class="text-sm text-base-content/60">关键词规则 — 未命中走 AI 自动回复或默认回复</p>
      </div>

      <label class="form-control w-full max-w-xs">
        <span class="label-text mb-1">选择账号</span>
        <select
          class="select select-bordered select-sm"
          value={accountId()}
          onChange={(e) => onAccountChange(Number(e.currentTarget.value))}
        >
          <For each={accounts.accounts()}>
            {(a) => (
              <option value={a.id}>
                {a.name}（{a.id}）
              </option>
            )}
          </For>
        </select>
      </label>

      <form onSubmit={onCreate} class="flex items-end gap-2">
        <label class="form-control w-full max-w-xs">
          <span class="label-text mb-1">新规则名称</span>
          <input
            type="text"
            class="input input-bordered input-sm"
            placeholder="例如：问候语"
            value={nameInput()}
            onInput={(e) => setNameInput(e.currentTarget.value)}
            required
          />
        </label>
        <button type="submit" class="btn btn-primary btn-sm" disabled={creating() || accountId() === 0}>
          {creating() ? '创建中…' : '创建规则'}
        </button>
      </form>

      <Show when={success()}>
        <div role="alert" class="alert alert-success py-2 text-sm">
          {success()}
        </div>
      </Show>

      <DataTable
        columns={columns}
        rows={paged.items()}
        rowKey={(r) => r.id}
        total={paged.total()}
        page={paged.page()}
        totalPages={paged.totalPages()}
        loading={paged.loading()}
        error={paged.error()}
        emptyText="暂无规则"
        onPageChange={(p) => void paged.reload(p)}
        actions={(rule) => (
          <div class="flex gap-1">
            <button type="button" class="btn btn-ghost btn-xs" onClick={() => void openRule(rule)}>
              {expanded() === rule.id ? '收起' : '配置'}
            </button>
            <button type="button" class="btn btn-ghost btn-xs text-error" onClick={() => onDeleteRule(rule)}>
              删除
            </button>
          </div>
        )}
      />

      <Show when={expanded() !== null}>
        <div class="rounded-lg border border-base-300 bg-base-200/40 p-4 space-y-4">
          <h3 class="text-sm font-semibold">规则 #{expanded()} — 关键词与回复</h3>

          <div>
            <p class="mb-2 text-sm font-medium">关键词</p>
            <div class="mb-2 flex flex-wrap gap-2">
              <For each={keywords()}>
                {(k) => (
                  <span class="badge badge-outline gap-1">
                    {k.keyword}
                    <span class="text-xs text-base-content/50">{k.match_type === 'full' ? '完全' : '包含'}</span>
                    <button type="button" class="ml-1 text-error" onClick={() => onRemoveKeyword(expanded()!, k.id)}>
                      ×
                    </button>
                  </span>
                )}
              </For>
            </div>
            <div class="flex items-end gap-2">
              <input
                type="text"
                class="input input-bordered input-sm w-40"
                placeholder="关键词"
                value={kwInput()}
                onInput={(e) => setKwInput(e.currentTarget.value)}
              />
              <select class="select select-bordered select-sm" value={kwMatch()} onChange={(e) => setKwMatch(e.currentTarget.value as 'full' | 'contain')}>
                <option value="contain">包含</option>
                <option value="full">完全匹配</option>
              </select>
              <button type="button" class="btn btn-primary btn-sm" onClick={() => onAddKeyword(expanded()!)}>
                添加
              </button>
            </div>
          </div>

          <div>
            <p class="mb-2 text-sm font-medium">回复</p>
            <div class="mb-2 space-y-1">
              <For each={replies()}>
                {(r) => (
                  <div class="flex items-center justify-between rounded bg-base-100 px-2 py-1 text-sm">
                    <span>
                      <span class="badge badge-sm badge-ghost mr-2">{r.reply_type === 'text' ? '文本' : '图文'}</span>
                      {r.reply_type === 'text' ? r.content : r.news_title}
                    </span>
                    <button type="button" class="btn btn-ghost btn-xs text-error" onClick={() => onRemoveReply(expanded()!, r.id)}>
                      删除
                    </button>
                  </div>
                )}
              </For>
            </div>
            <div class="flex items-end gap-2">
              <select class="select select-bordered select-sm" value={replyType()} onChange={(e) => setReplyType(e.currentTarget.value as ReplyType)}>
                <option value="text">文本</option>
                <option value="news">图文</option>
              </select>
              <Show
                when={replyType() === 'text'}
                fallback={
                  <>
                    <input type="text" class="input input-bordered input-sm w-40" placeholder="标题" value={newsTitle()} onInput={(e) => setNewsTitle(e.currentTarget.value)} />
                    <input type="text" class="input input-bordered input-sm w-40" placeholder="摘要" value={newsDesc()} onInput={(e) => setNewsDesc(e.currentTarget.value)} />
                    <input type="text" class="input input-bordered input-sm w-48" placeholder="跳转链接" value={newsUrl()} onInput={(e) => setNewsUrl(e.currentTarget.value)} />
                  </>
                }
              >
                <input type="text" class="input input-bordered input-sm w-72" placeholder="回复内容" value={replyText()} onInput={(e) => setReplyText(e.currentTarget.value)} />
              </Show>
              <button type="button" class="btn btn-primary btn-sm" onClick={() => onAddReply(expanded()!)}>
                添加回复
              </button>
            </div>
          </div>
        </div>
      </Show>
    </div>
  );
}

export default Rules;
