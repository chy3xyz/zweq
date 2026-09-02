import { Show, createMemo, createSignal } from 'solid-js';

import { listLogs, sendCustomerText, type LogItem } from '#ui/api';
import AccountRequiredBanner from '#ui/components/AccountRequiredBanner';
import AdminCrudPage from '#ui/components/AdminCrudPage';
import BaseModal from '#ui/components/BaseModal';
import DataTable, { type Column } from '#ui/components/DataTable';
import FormField from '#ui/components/FormField';
import SearchBar, { type SearchField, type SearchValues } from '#ui/components/SearchBar';
import Tabs from '#ui/components/Tabs';
import { useAccountId, useFeedback, usePaged } from '#ui/hooks';
import { formatDateTime } from '#ui/utils';

const PAGE_SIZE = 20;
const TABS = ['消息日志', '手动客服消息'] as const;

const SEARCH_FIELDS: SearchField[] = [
  { kind: 'text', key: 'keyword', label: 'OpenID / 内容', placeholder: '输入关键字后查询' },
];

function Logs() {
  const { accountId } = useAccountId();
  const feedback = useFeedback();
  const [filters, setFilters] = createSignal<SearchValues>({});
  const [activeTab, setActiveTab] = createSignal<(typeof TABS)[number]>('消息日志');

  const paged = usePaged<LogItem>(
    (page, pageSize) => listLogs(page, pageSize, accountId()),
    PAGE_SIZE,
    accountId,
  );

  const filteredItems = createMemo(() => {
    const keyword = filters().keyword?.trim().toLowerCase();
    if (!keyword) return paged.items();
    return paged.items().filter(
      (l) =>
        l.openid.toLowerCase().includes(keyword) ||
        l.content.toLowerCase().includes(keyword) ||
        (l.reply_content && l.reply_content.toLowerCase().includes(keyword)),
    );
  });

  // Detail modal
  const [detailLog, setDetailLog] = createSignal<LogItem | null>(null);

  // Manual customer message
  const [manualOpenid, setManualOpenid] = createSignal('');
  const [manualContent, setManualContent] = createSignal('');
  const [manualSubmitting, setManualSubmitting] = createSignal(false);

  const openDetail = (log: LogItem) => setDetailLog(log);
  const closeDetail = () => setDetailLog(null);

  const onSendManual = async (e: SubmitEvent) => {
    e.preventDefault();
    if (manualSubmitting() || accountId() <= 0) return;

    const openid = manualOpenid().trim();
    const content = manualContent().trim();
    if (!openid || !content) {
      feedback.toast('OpenID 和消息内容不能为空', 'error');
      return;
    }

    setManualSubmitting(true);
    try {
      await sendCustomerText(accountId(), openid, content);
      feedback.toast('客服消息已发送');
      setManualContent('');
    } catch (err) {
      feedback.toast(err instanceof Error ? err.message : '发送失败', 'error');
    } finally {
      setManualSubmitting(false);
    }
  };

  const columns: Column<LogItem>[] = [
    { key: 'id', title: 'ID', render: (l) => <span class="font-mono text-xs">{l.id}</span> },
    {
      key: 'msg_type',
      title: '类型',
      render: (l) => (
        <span class="badge badge-sm badge-ghost">
          {l.msg_type}
          {l.event && ` / ${l.event}`}
        </span>
      ),
    },
    { key: 'openid', title: '粉丝', render: (l) => <span class="font-mono text-xs">{l.openid.slice(0, 20)}…</span> },
    { key: 'content', title: '消息内容', render: (l) => <span class="max-w-[240px] truncate text-sm">{l.content}</span> },
    {
      key: 'reply_content',
      title: '回复',
      render: (l) => (
        <span class={`max-w-[240px] truncate text-sm ${l.reply_content ? '' : 'text-base-content/40'}`}>
          {l.reply_content || '-'}
        </span>
      ),
    },
    { key: 'created_at', title: '时间', render: (l) => <span class="text-sm text-base-content/70">{formatDateTime(l.created_at)}</span> },
  ];

  return (
    <AdminCrudPage
      title="消息日志"
      description="微信公众号服务器回调日志"
      total={paged.total()}
      onRefresh={() => void paged.refresh()}
      search={<SearchBar fields={SEARCH_FIELDS} loading={paged.loading()} onSearch={setFilters} />}
    >
      <AccountRequiredBanner />

      <Tabs tabs={[...TABS]} active={activeTab()} onChange={setActiveTab} class="mb-4" />

      <Show when={activeTab() === '消息日志'}>
        <DataTable
          columns={columns}
          rows={filteredItems()}
          rowKey={(l) => l.id}
          total={paged.total()}
          page={paged.page()}
          totalPages={paged.totalPages()}
          loading={paged.loading()}
          error={paged.error()}
          emptyText="暂无日志"
          onPageChange={(p) => void paged.reload(p)}
          actions={(l) => (
            <button type="button" class="btn btn-ghost btn-xs" onClick={() => openDetail(l)}>
              详情
            </button>
          )}
        />
      </Show>

      <Show when={activeTab() === '手动客服消息'}>
        <form onSubmit={onSendManual} class="space-y-4">
          <FormField label="OpenID" required>
            <input
              type="text"
              class="input input-bordered input-sm w-full font-mono"
              placeholder="粉丝 OpenID"
              value={manualOpenid()}
              onInput={(e) => setManualOpenid(e.currentTarget.value)}
              disabled={accountId() <= 0}
              required
            />
          </FormField>

          <FormField label="消息内容" required>
            <textarea
              class="textarea textarea-bordered w-full"
              rows={5}
              placeholder="输入要发送的客服文本消息"
              value={manualContent()}
              onInput={(e) => setManualContent(e.currentTarget.value)}
              disabled={accountId() <= 0}
              required
            />
          </FormField>

          <div class="flex justify-end">
            <button
              type="submit"
              class="btn btn-primary btn-sm"
              disabled={manualSubmitting() || accountId() <= 0}
            >
              <Show when={manualSubmitting()}>
                <span class="loading loading-spinner loading-xs" />
              </Show>
              {manualSubmitting() ? '发送中…' : '发送'}
            </button>
          </div>
        </form>
      </Show>

      <BaseModal
        open={detailLog() !== null}
        title="消息详情"
        onClose={closeDetail}
        size="lg"
      >
        <Show when={detailLog()}>
          {(log) => (
            <div class="space-y-4 text-sm">
              <div class="grid grid-cols-2 gap-4">
                <FormField label="ID">
                  <span class="font-mono">{log().id}</span>
                </FormField>
                <FormField label="MsgID">
                  <span class="font-mono">{log().msg_id || '-'}</span>
                </FormField>
              </div>

              <FormField label="粉丝 OpenID">
                <span class="break-all font-mono">{log().openid}</span>
              </FormField>

              <div class="grid grid-cols-2 gap-4">
                <FormField label="消息类型">
                  <span class="badge badge-sm badge-ghost">{log().msg_type}</span>
                </FormField>
                <FormField label="事件">
                  <span class="badge badge-sm badge-ghost">{log().event || '-'}</span>
                </FormField>
              </div>

              <FormField label="消息内容">
                <div class="max-h-60 overflow-auto whitespace-pre-wrap rounded-lg border border-base-200 bg-base-100 p-3">
                  {log().content || '-'}
                </div>
              </FormField>

              <FormField label={`回复内容 (${log().reply_type || '-'})`}>
                <div class="max-h-60 overflow-auto whitespace-pre-wrap rounded-lg border border-base-200 bg-base-100 p-3">
                  {log().reply_content || '-'}
                </div>
              </FormField>

              <FormField label="创建时间">
                <span class="text-base-content/70">{formatDateTime(log().created_at)}</span>
              </FormField>
            </div>
          )}
        </Show>
      </BaseModal>
    </AdminCrudPage>
  );
}

export default Logs;
