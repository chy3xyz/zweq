import { For, Show, createSignal } from 'solid-js';

import {
  createMaterialFile,
  createNews,
  deleteMaterialFile,
  deleteNews,
  listMaterialFiles,
  listNews,
  syncFiles,
  syncNews,
  updateNews,
  uploadNews,
  type MaterialFileItem,
  type MaterialKind,
  type NewsItem,
} from '#ui/api';
import AccountRequiredBanner from '#ui/components/AccountRequiredBanner';
import DataTable, { type Column } from '#ui/components/DataTable';
import FormField from '#ui/components/FormField';
import FormModal from '#ui/components/FormModal';
import ImageManager from '#ui/components/ImageManager';
import RichEditor from '#ui/components/RichEditor';
import Tabs from '#ui/components/Tabs';
import { fileUrl as publicFileUrl } from '#ui/api/file/types';
import { useAccountId, useFeedback, usePaged } from '#ui/hooks';
import { formatDateTime } from '#ui/utils';

const PAGE_SIZE = 20;
const KIND_LABEL: Record<MaterialKind, string> = { image: '图片', voice: '语音', video: '视频' };
const TABS = ['图文素材', '素材文件'] as const;

const KIND_OPTIONS: { value: MaterialKind; label: string }[] = [
  { value: 'image', label: '图片' },
  { value: 'voice', label: '语音' },
  { value: 'video', label: '视频' },
];

function Materials() {
  const { accountId, onAccountChange } = useAccountId();
  const feedback = useFeedback();
  const [tab, setTab] = createSignal<(typeof TABS)[number]>('图文素材');

  // 图文编辑弹窗
  const [newsOpen, setNewsOpen] = createSignal(false);
  const [editing, setEditing] = createSignal<NewsItem | null>(null);
  const [title, setTitle] = createSignal('');
  const [author, setAuthor] = createSignal('');
  const [digest, setDigest] = createSignal('');
  const [content, setContent] = createSignal('');
  const [thumbUrl, setThumbUrl] = createSignal('');
  const [linkUrl, setLinkUrl] = createSignal('');
  const [saving, setSaving] = createSignal(false);
  const [newsError, setNewsError] = createSignal<string | null>(null);
  const [thumbPicker, setThumbPicker] = createSignal(false);

  // 上传到微信弹窗（add_news）
  const [uploadOpen, setUploadOpen] = createSignal(false);
  const [upTitle, setUpTitle] = createSignal('');
  const [upAuthor, setUpAuthor] = createSignal('');
  const [upDigest, setUpDigest] = createSignal('');
  const [upContent, setUpContent] = createSignal('');
  const [upThumbMediaId, setUpThumbMediaId] = createSignal('');
  const [upSourceUrl, setUpSourceUrl] = createSignal('');
  const [uploading, setUploading] = createSignal(false);
  const [uploadError, setUploadError] = createSignal<string | null>(null);

  // 素材文件弹窗
  const [fileOpen, setFileOpen] = createSignal(false);
  const [fileKind, setFileKind] = createSignal<MaterialKind>('image');
  const [fileMediaId, setFileMediaId] = createSignal('');
  const [fileUrl, setFileUrl] = createSignal('');
  const [fileSaving, setFileSaving] = createSignal(false);
  const [fileError, setFileError] = createSignal<string | null>(null);
  const [kindFilter, setKindFilter] = createSignal<MaterialKind | ''>('');

  const news = usePaged<NewsItem>(
    (page, pageSize) => listNews(page, pageSize, accountId()),
    PAGE_SIZE,
    accountId,
  );
  const files = usePaged<MaterialFileItem>(
    (page, pageSize) => listMaterialFiles(page, pageSize, accountId(), kindFilter() || undefined),
    PAGE_SIZE,
    () => [accountId(), kindFilter()],
  );

  onAccountChange(() => {
    setNewsOpen(false);
  });

  const openCreateNews = () => {
    setEditing(null);
    setTitle('');
    setAuthor('');
    setDigest('');
    setContent('');
    setThumbUrl('');
    setLinkUrl('');
    setNewsError(null);
    setNewsOpen(true);
  };

  const openEditNews = (n: NewsItem) => {
    setEditing(n);
    setTitle(n.title);
    setAuthor(n.author);
    setDigest(n.digest);
    setContent(n.content);
    setThumbUrl(n.thumb_url);
    setLinkUrl(n.url);
    setNewsError(null);
    setNewsOpen(true);
  };

  const onSaveNews = async () => {
    if (saving() || accountId() === 0) return;
    setSaving(true);
    setNewsError(null);
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
        feedback.toast('图文已更新');
      } else {
        await createNews(body);
        feedback.toast('图文已创建');
      }
      setNewsOpen(false);
      void news.refresh();
    } catch (err) {
      setNewsError(err instanceof Error ? err.message : '保存失败，请稍后重试');
    } finally {
      setSaving(false);
    }
  };

  const onDeleteNews = (n: NewsItem) =>
    feedback.runAction({
      confirm: { title: '删除图文', message: `确定删除图文「${n.title}」吗？`, danger: true },
      action: () => deleteNews(n.id),
      onDone: () => void news.refresh(),
    });

  const openUploadNews = () => {
    setUpTitle('');
    setUpAuthor('');
    setUpDigest('');
    setUpContent('');
    setUpThumbMediaId('');
    setUpSourceUrl('');
    setUploadError(null);
    setUploadOpen(true);
  };

  const onUploadNews = async () => {
    if (uploading() || accountId() === 0) return;
    setUploading(true);
    setUploadError(null);
    try {
      await uploadNews({
        account_id: accountId(),
        title: upTitle().trim(),
        author: upAuthor().trim(),
        digest: upDigest().trim(),
        content: upContent().trim(),
        thumb_media_id: upThumbMediaId().trim(),
        content_source_url: upSourceUrl().trim(),
      });
      setUploadOpen(false);
      feedback.toast('图文已上传到微信');
      void news.refresh();
    } catch (err) {
      setUploadError(err instanceof Error ? err.message : '上传失败，请稍后重试');
    } finally {
      setUploading(false);
    }
  };

  const onSyncNews = () =>
    feedback.runAction({
      confirm: { title: '同步图文', message: '从微信后台拉取图文素材到本地？', danger: false },
      action: () => syncNews(accountId()),
      success: '图文已同步',
      onDone: () => void news.refresh(),
    });

  const onSyncFiles = () => {
    const kind = kindFilter() || 'image';
    return feedback.runAction({
      confirm: { title: '同步素材文件', message: `从微信后台拉取${KIND_LABEL[kind]}素材到本地？`, danger: false },
      action: () => syncFiles(accountId(), kind),
      success: '素材文件已同步',
      onDone: () => void files.refresh(),
    });
  };

  const onAddFile = async () => {
    if (fileSaving() || accountId() === 0) return;
    setFileSaving(true);
    setFileError(null);
    try {
      await createMaterialFile({
        account_id: accountId(),
        kind: fileKind(),
        media_id: fileMediaId().trim(),
        url: fileUrl().trim(),
      });
      setFileOpen(false);
      setFileMediaId('');
      setFileUrl('');
      feedback.toast('素材文件已添加');
      void files.reload(1);
    } catch (err) {
      setFileError(err instanceof Error ? err.message : '添加失败，请稍后重试');
    } finally {
      setFileSaving(false);
    }
  };

  const onDeleteFile = (f: MaterialFileItem) =>
    feedback.runAction({
      confirm: {
        title: '删除素材',
        message: `确定删除该${KIND_LABEL[f.kind]}素材吗？`,
        danger: true,
      },
      action: () => deleteMaterialFile(f.id),
      onDone: () => void files.refresh(),
    });

  const newsColumns: Column<NewsItem>[] = [
    { key: 'id', title: 'ID', render: (n) => <span class="font-mono text-xs">{n.id}</span> },
    { key: 'title', title: '标题', render: (n) => <span class="font-medium">{n.title}</span> },
    { key: 'author', title: '作者', render: (n) => <span class="text-sm text-base-content/70">{n.author || '-'}</span> },
    { key: 'url', title: '链接', render: (n) => (n.url ? <a class="link link-primary text-xs" href={n.url} target="_blank" rel="noreferrer">打开</a> : <span class="text-base-content/40">-</span>) },
    { key: 'updated_at', title: '更新时间', render: (n) => <span class="text-sm text-base-content/70">{formatDateTime(n.updated_at)}</span> },
  ];

  // 后端未暴露 PUT /materials/files/{id}，素材文件仅支持新增/删除。
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

      <AccountRequiredBanner />

      <Tabs tabs={[...TABS]} active={tab()} onChange={setTab} />

      <Show when={tab() === '图文素材'}>
        <section class="rounded-box border border-base-300 bg-base-100 p-4">
          <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
            <h3 class="text-lg font-semibold">图文素材</h3>
            <div class="flex flex-wrap items-center gap-2">
              <button
                type="button"
                class="btn btn-outline btn-sm"
                disabled={accountId() === 0}
                onClick={() => void onSyncNews()}
              >
                同步图文
              </button>
              <button
                type="button"
                class="btn btn-outline btn-sm"
                disabled={accountId() === 0}
                onClick={openUploadNews}
              >
                上传到微信
              </button>
              <button
                type="button"
                class="btn btn-primary btn-sm"
                disabled={accountId() === 0}
                onClick={openCreateNews}
              >
                新建图文
              </button>
            </div>
          </div>
          <DataTable
            columns={newsColumns}
            rows={news.items()}
            rowKey={(n) => n.id}
            total={news.total()}
            page={news.page()}
            totalPages={news.totalPages()}
            pageSize={news.pageSize()}
            loading={news.loading()}
            error={news.error()}
            emptyText="暂无图文素材"
            onPageChange={(p) => void news.reload(p)}
            onPageSizeChange={(size) => news.setPageSize(size)}
            actions={(n) => (
              <>
                <button type="button" class="btn btn-ghost btn-xs" onClick={() => openEditNews(n)}>
                  编辑
                </button>
                <button type="button" class="btn btn-ghost btn-xs text-error" onClick={() => void onDeleteNews(n)}>
                  删除
                </button>
              </>
            )}
          />
        </section>
      </Show>

      <Show when={tab() === '素材文件'}>
        <section class="rounded-box border border-base-300 bg-base-100 p-4">
          <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
            <h3 class="text-lg font-semibold">素材文件</h3>
            <div class="flex items-center gap-2">
              <select
                class="select select-bordered select-sm"
                value={kindFilter()}
                onChange={(e) => {
                  setKindFilter(e.currentTarget.value as MaterialKind | '');
                  void files.reload(1);
                }}
              >
                <option value="">全部</option>
                <For each={KIND_OPTIONS}>{(k) => <option value={k.value}>{k.label}</option>}</For>
              </select>
              <button
                type="button"
                class="btn btn-outline btn-sm"
                disabled={accountId() === 0}
                onClick={() => void onSyncFiles()}
              >
                同步素材文件
              </button>
              <button
                type="button"
                class="btn btn-primary btn-sm"
                disabled={accountId() === 0}
                onClick={() => {
                  setFileError(null);
                  setFileKind('image');
                  setFileMediaId('');
                  setFileUrl('');
                  setFileOpen(true);
                }}
              >
                新增素材
              </button>
            </div>
          </div>
          <DataTable
            columns={fileColumns}
            rows={files.items()}
            rowKey={(f) => f.id}
            total={files.total()}
            page={files.page()}
            totalPages={files.totalPages()}
            pageSize={files.pageSize()}
            loading={files.loading()}
            error={files.error()}
            emptyText="暂无素材文件"
            onPageChange={(p) => void files.reload(p)}
            onPageSizeChange={(size) => files.setPageSize(size)}
            actions={(f) => (
              <button type="button" class="btn btn-ghost btn-xs text-error" onClick={() => void onDeleteFile(f)}>
                删除
              </button>
            )}
          />
        </section>
      </Show>

      <FormModal
        open={newsOpen()}
        title={editing() ? `编辑图文 #${editing()!.id}` : '新建图文'}
        description="正文支持在发布后于微信后台补充排版；保存后可通过「同步素材」推送至微信"
        onSubmit={onSaveNews}
        onClose={() => setNewsOpen(false)}
        submitting={saving()}
        error={newsError()}
        submitLabel={editing() ? '保存修改' : '创建图文'}
      >
        <FormField label="标题" required>
          <input
            type="text"
            class="input input-bordered input-sm w-full"
            placeholder="图文标题"
            value={title()}
            onInput={(e) => setTitle(e.currentTarget.value)}
          />
        </FormField>
        <div class="grid grid-cols-2 gap-3">
          <FormField label="作者">
            <input
              type="text"
              class="input input-bordered input-sm w-full"
              placeholder="作者"
              value={author()}
              onInput={(e) => setAuthor(e.currentTarget.value)}
            />
          </FormField>
          <FormField label="摘要">
            <input
              type="text"
              class="input input-bordered input-sm w-full"
              placeholder="一句话摘要"
              value={digest()}
              onInput={(e) => setDigest(e.currentTarget.value)}
            />
          </FormField>
        </div>
        <FormField label="正文内容">
          <RichEditor value={content()} onInput={setContent} placeholder="支持加粗、标题、列表、链接与图片插入" />
        </FormField>
        <FormField label="封面图">
          <div class="flex flex-wrap items-center gap-3">
            <Show when={thumbUrl()}>
              <img src={thumbUrl()} alt="封面" class="h-16 w-16 rounded border object-cover" />
            </Show>
            <button type="button" class="btn btn-outline btn-sm" onClick={() => setThumbPicker(true)}>
              选择图片
            </button>
            <button type="button" class="btn btn-ghost btn-sm" onClick={() => setThumbUrl('')} disabled={!thumbUrl()}>
              清除
            </button>
            <input
              type="text"
              class="input input-bordered input-sm flex-1"
              placeholder="/uploads/... 或 https://..."
              value={thumbUrl()}
              onInput={(e) => setThumbUrl(e.currentTarget.value)}
            />
          </div>
          <ImageManager
            open={thumbPicker()}
            multiple={false}
            max={1}
            onSelect={(items) => items[0] && setThumbUrl(publicFileUrl(items[0]))}
            onClose={() => setThumbPicker(false)}
          />
        </FormField>
        <FormField label="跳转链接">
          <input
            type="text"
            class="input input-bordered input-sm w-full"
            placeholder="https://..."
            value={linkUrl()}
            onInput={(e) => setLinkUrl(e.currentTarget.value)}
          />
        </FormField>
      </FormModal>

      <FormModal
        open={uploadOpen()}
        title="上传图文到微信"
        description="调用微信 add_news 接口直接发布图文，需要填写封面图 MediaID"
        onSubmit={onUploadNews}
        onClose={() => setUploadOpen(false)}
        submitting={uploading()}
        error={uploadError()}
        submitLabel="上传"
      >
        <FormField label="标题" required>
          <input
            type="text"
            class="input input-bordered input-sm w-full"
            placeholder="图文标题"
            value={upTitle()}
            onInput={(e) => setUpTitle(e.currentTarget.value)}
          />
        </FormField>
        <div class="grid grid-cols-2 gap-3">
          <FormField label="作者">
            <input
              type="text"
              class="input input-bordered input-sm w-full"
              placeholder="作者"
              value={upAuthor()}
              onInput={(e) => setUpAuthor(e.currentTarget.value)}
            />
          </FormField>
          <FormField label="摘要">
            <input
              type="text"
              class="input input-bordered input-sm w-full"
              placeholder="一句话摘要"
              value={upDigest()}
              onInput={(e) => setUpDigest(e.currentTarget.value)}
            />
          </FormField>
        </div>
        <FormField label="正文内容">
          <RichEditor value={upContent()} onInput={setUpContent} placeholder="支持加粗、标题、列表、链接与图片插入" />
        </FormField>
        <FormField label="封面图 MediaID" required hint="需先上传封面图片到微信永久素材并获得 MediaID">
          <input
            type="text"
            class="input input-bordered input-sm w-full font-mono"
            placeholder="例如：MEDIA_ID_xxxxx"
            value={upThumbMediaId()}
            onInput={(e) => setUpThumbMediaId(e.currentTarget.value)}
          />
        </FormField>
        <FormField label="原文链接">
          <input
            type="text"
            class="input input-bordered input-sm w-full"
            placeholder="https://..."
            value={upSourceUrl()}
            onInput={(e) => setUpSourceUrl(e.currentTarget.value)}
          />
        </FormField>
      </FormModal>

      <FormModal
        open={fileOpen()}
        title="新增素材文件"
        description="关联微信永久素材：先在微信后台上传并复制 MediaID"
        onSubmit={onAddFile}
        onClose={() => setFileOpen(false)}
        submitting={fileSaving()}
        error={fileError()}
        submitLabel="添加"
        size="sm"
      >
        <FormField label="类型" required>
          <select
            class="select select-bordered select-sm w-full"
            value={fileKind()}
            onChange={(e) => setFileKind(e.currentTarget.value as MaterialKind)}
          >
            <For each={KIND_OPTIONS}>{(k) => <option value={k.value}>{k.label}</option>}</For>
          </select>
        </FormField>
        <FormField label="微信永久素材 MediaID" required>
          <input
            type="text"
            class="input input-bordered input-sm w-full font-mono"
            placeholder="例如：MEDIA_ID_xxxxx"
            value={fileMediaId()}
            onInput={(e) => setFileMediaId(e.currentTarget.value)}
          />
        </FormField>
        <FormField label="素材 URL" hint="微信返回的访问地址，可选">
          <input
            type="text"
            class="input input-bordered input-sm w-full"
            placeholder="https://..."
            value={fileUrl()}
            onInput={(e) => setFileUrl(e.currentTarget.value)}
          />
        </FormField>
      </FormModal>
    </div>
  );
}
export default Materials;
