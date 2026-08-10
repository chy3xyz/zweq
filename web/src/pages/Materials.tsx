import { For, Show, createSignal } from 'solid-js';

import {
  createMaterialFile,
  createNews,
  deleteMaterialFile,
  deleteNews,
  listMaterialFiles,
  listNews,
  toApiError,
  updateNews,
  type MaterialFileItem,
  type MaterialKind,
  type NewsItem,
} from '#ui/api';
import DataTable, { type Column } from '#ui/components/DataTable';
import { useAccounts } from '#ui/hooks/useAccounts';
import { usePaged } from '#ui/hooks/usePaged';
import { formatDateTime } from '#ui/utils';

const PAGE_SIZE = 20;
const KIND_LABEL: Record<MaterialKind, string> = { image: '图片', voice: '语音', video: '视频' };

function Materials() {
  const accounts = useAccounts();
  const [success, setSuccess] = createSignal<string | null>(null);

  // 图文编辑
  const [editing, setEditing] = createSignal<NewsItem | null>(null);
  const [title, setTitle] = createSignal('');
  const [author, setAuthor] = createSignal('');
  const [digest, setDigest] = createSignal('');
  const [content, setContent] = createSignal('');
  const [thumbUrl, setThumbUrl] = createSignal('');
  const [linkUrl, setLinkUrl] = createSignal('');
  const [saving, setSaving] = createSignal(false);

  // 素材文件
  const [kindFilter, setKindFilter] = createSignal<MaterialKind | ''>('');
  const [fileKind, setFileKind] = createSignal<MaterialKind>('image');
  const [fileMediaId, setFileMediaId] = createSignal('');
  const [fileUrl, setFileUrl] = createSignal('');

  const accountId = () => accounts.selected() ?? 0;
  const news = usePaged<NewsItem>((page, pageSize) => listNews(page, pageSize, accountId()), PAGE_SIZE);
  const files = usePaged<MaterialFileItem>(
    (page, pageSize) => listMaterialFiles(page, pageSize, accountId(), kindFilter() || undefined),
    PAGE_SIZE,
  );

  const onAccountChange = (id: number) => {
    accounts.setSelected(id);
    setEditing(null);
    void news.reload(1);
    void files.reload(1);
  };

  const onNewNews = () => {
    setEditing(null);
    setTitle('');
    setAuthor('');
    setDigest('');
    setContent('');
    setThumbUrl('');
    setLinkUrl('');
  };

  const onEditNews = (n: NewsItem) => {
    setEditing(n);
    setTitle(n.title);
    setAuthor(n.author);
    setDigest(n.digest);
    setContent(n.content);
    setThumbUrl(n.thumb_url);
    setLinkUrl(n.url);
  };

  const onSaveNews = async (e: SubmitEvent) => {
    e.preventDefault();
    if (saving() || accountId() === 0) return;
    setSaving(true);
    setSuccess(null);
    try {
      const body = {
        account_id: accountId(),
        title: title().trim(),
        author: author().trim(),
        digest: digest().trim(),
        content: content().trim(),
        thumb_url: thumbUrl().trim(),
        url: linkUrl().trim(),
      };
      if (editing()) {
        await updateNews(editing()!.id, body);
        setSuccess('图文已更新');
      } else {
        await createNews(body);
        setSuccess('图文已创建');
      }
      onNewNews();
      void news.reload(1);
    } catch (err) {
      window.alert(toApiError(err).message);
    } finally {
      setSaving(false);
    }
  };

  const onDeleteNews = async (n: NewsItem) => {
    if (!window.confirm(`确定删除图文「${n.title}」吗？`)) return;
    try {
      await deleteNews(n.id);
      if (editing()?.id === n.id) setEditing(null);
      void news.reload();
    } catch (err) {
      window.alert(toApiError(err).message);
    }
  };

  const onAddFile = async () => {
    if (accountId() === 0) return;
    try {
      await createMaterialFile({ account_id: accountId(), kind: fileKind(), media_id: fileMediaId().trim(), url: fileUrl().trim() });
      setFileMediaId('');
      setFileUrl('');
      void files.reload(1);
    } catch (err) {
      window.alert(toApiError(err).message);
    }
  };

  const onDeleteFile = async (f: MaterialFileItem) => {
    if (!window.confirm(`确定删除 ${KIND_LABEL[f.kind]} 素材吗？`)) return;
    try {
      await deleteMaterialFile(f.id);
      void files.reload();
    } catch (err) {
      window.alert(toApiError(err).message);
    }
  };

  const newsColumns: Column<NewsItem>[] = [
    { key: 'id', title: 'ID', render: (n) => <span class="font-mono text-xs">{n.id}</span> },
    { key: 'title', title: '标题', render: (n) => <span class="font-medium">{n.title}</span> },
    { key: 'author', title: '作者', render: (n) => <span class="text-sm text-base-content/70">{n.author || '-'}</span> },
    { key: 'url', title: '链接', render: (n) => (n.url ? <a class="link link-primary text-xs" href={n.url} target="_blank" rel="noreferrer">打开</a> : <span class="text-base-content/40">-</span>) },
    { key: 'updated_at', title: '更新时间', render: (n) => <span class="text-sm text-base-content/70">{formatDateTime(n.updated_at)}</span> },
  ];

  const fileColumns: Column<MaterialFileItem>[] = [
    { key: 'id', title: 'ID', render: (f) => <span class="font-mono text-xs">{f.id}</span> },
    { key: 'kind', title: '类型', render: (f) => <span class="badge badge-sm badge-ghost">{KIND_LABEL[f.kind]}</span> },
    { key: 'media_id', title: '微信 MediaID', render: (f) => <span class="font-mono text-xs">{f.media_id}</span> },
    { key: 'url', title: 'URL', render: (f) => (f.url ? <a class="link link-primary text-xs" href={f.url} target="_blank" rel="noreferrer">查看</a> : <span class="text-base-content/40">-</span>) },
    { key: 'created_at', title: '创建时间', render: (f) => <span class="text-sm text-base-content/70">{formatDateTime(f.created_at)}</span> },
  ];

  return (
    <div class="space-y-4">
      <div>
        <h2 class="text-xl font-semibold">素材库</h2>
        <p class="text-sm text-base-content/60">图文素材 + 图片/语音/视频素材（关联微信永久素材 media_id）</p>
      </div>

      <label class="form-control w-full max-w-xs">
        <span class="label-text mb-1">选择账号</span>
        <select class="select select-bordered select-sm" value={accountId()} onChange={(e) => onAccountChange(Number(e.currentTarget.value))}>
          <For each={accounts.accounts()}>
            {(a) => (
              <option value={a.id}>
                {a.name}（{a.id}）
              </option>
            )}
          </For>
        </select>
      </label>

      <Show when={success()}>
        <div role="alert" class="alert alert-success py-2 text-sm">
          {success()}
        </div>
      </Show>

      <div class="grid grid-cols-1 gap-4 lg:grid-cols-3">
        {/* 图文素材 */}
        <div class="lg:col-span-2">
          <div class="mb-2 flex items-center justify-between">
            <h3 class="text-sm font-semibold">图文素材</h3>
            <button type="button" class="btn btn-ghost btn-xs" onClick={onNewNews}>
              {editing() ? '取消编辑' : '新建图文'}
            </button>
          </div>
          <DataTable
            columns={newsColumns}
            rows={news.items()}
            rowKey={(n) => n.id}
            total={news.total()}
            page={news.page()}
            totalPages={news.totalPages()}
            loading={news.loading()}
            error={news.error()}
            emptyText="暂无图文素材"
            onPageChange={(p) => void news.reload(p)}
            actions={(n) => (
              <div class="flex gap-1">
                <button type="button" class="btn btn-ghost btn-xs" onClick={() => onEditNews(n)}>
                  编辑
                </button>
                <button type="button" class="btn btn-ghost btn-xs text-error" onClick={() => onDeleteNews(n)}>
                  删除
                </button>
              </div>
            )}
          />
        </div>

        {/* 图文编辑器 */}
        <div class="rounded-lg border border-base-300 bg-base-200/40 p-4 space-y-3">
          <span class="text-sm font-semibold">{editing() ? `编辑图文 #${editing()!.id}` : '新建图文'}</span>
          <form onSubmit={onSaveNews} class="space-y-2">
            <input type="text" class="input input-bordered input-sm w-full" placeholder="标题" value={title()} onInput={(e) => setTitle(e.currentTarget.value)} required />
            <div class="flex gap-2">
              <input type="text" class="input input-bordered input-sm w-1/2" placeholder="作者" value={author()} onInput={(e) => setAuthor(e.currentTarget.value)} />
              <input type="text" class="input input-bordered input-sm w-1/2" placeholder="摘要" value={digest()} onInput={(e) => setDigest(e.currentTarget.value)} />
            </div>
            <textarea class="textarea textarea-bordered textarea-sm w-full" rows={3} placeholder="正文内容" value={content()} onInput={(e) => setContent(e.currentTarget.value)} />
            <input type="text" class="input input-bordered input-sm w-full" placeholder="封面图 URL" value={thumbUrl()} onInput={(e) => setThumbUrl(e.currentTarget.value)} />
            <input type="text" class="input input-bordered input-sm w-full" placeholder="跳转链接" value={linkUrl()} onInput={(e) => setLinkUrl(e.currentTarget.value)} />
            <button type="submit" class="btn btn-primary btn-sm w-full" disabled={saving() || accountId() === 0}>
              {saving() ? '保存中…' : editing() ? '保存修改' : '创建图文'}
            </button>
          </form>
        </div>
      </div>

      {/* 素材文件 */}
      <div>
        <div class="mb-2 flex items-center justify-between">
          <h3 class="text-sm font-semibold">素材文件</h3>
          <select class="select select-bordered select-sm" value={kindFilter()} onChange={(e) => {
            setKindFilter(e.currentTarget.value as MaterialKind | '');
            void files.reload(1);
          }}>
            <option value="">全部</option>
            <option value="image">图片</option>
            <option value="voice">语音</option>
            <option value="video">视频</option>
          </select>
        </div>
        <div class="mb-2 flex items-end gap-2 rounded-lg border border-base-300 bg-base-200/40 p-3">
          <select class="select select-bordered select-sm" value={fileKind()} onChange={(e) => setFileKind(e.currentTarget.value as MaterialKind)}>
            <option value="image">图片</option>
            <option value="voice">语音</option>
            <option value="video">视频</option>
          </select>
          <input type="text" class="input input-bordered input-sm flex-1" placeholder="微信永久素材 MediaID" value={fileMediaId()} onInput={(e) => setFileMediaId(e.currentTarget.value)} required />
          <input type="text" class="input input-bordered input-sm flex-1" placeholder="URL" value={fileUrl()} onInput={(e) => setFileUrl(e.currentTarget.value)} />
          <button type="button" class="btn btn-primary btn-sm" onClick={onAddFile}>
            添加素材
          </button>
        </div>
        <DataTable
          columns={fileColumns}
          rows={files.items()}
          rowKey={(f) => f.id}
          total={files.total()}
          page={files.page()}
          totalPages={files.totalPages()}
          loading={files.loading()}
          error={files.error()}
          emptyText="暂无素材文件"
          onPageChange={(p) => void files.reload(p)}
          actions={(f) => (
            <button type="button" class="btn btn-ghost btn-xs text-error" onClick={() => onDeleteFile(f)}>
              删除
            </button>
          )}
        />
      </div>
    </div>
  );
}

export default Materials;
