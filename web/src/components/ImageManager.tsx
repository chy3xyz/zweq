import { createEffect, createMemo, createSignal, For, Show } from 'solid-js';

import BaseModal, { type ModalSize } from '#ui/components/BaseModal';
import {
  createGroup,
  deleteGroup,
  listFiles,
  listGroups,
  uploadFile,
} from '#ui/api/file/query';
import { fileUrl, type FileItem, type UploadGroup } from '#ui/api/file/types';

interface Props {
  open: boolean;
  /** Called with the chosen items (in selection order) when 确定 is pressed. */
  onSelect: (items: FileItem[]) => void;
  onClose: () => void;
  /** Allow picking more than one image. Default true. */
  multiple?: boolean;
  /** Max selectable when multiple. Default 9. */
  max?: number;
  /** Modal size. Default "xl" (the manager needs room). */
  size?: ModalSize;
}

/**
 * Reusable image picker / file manager, modelled on the zmcanyin `Upload.vue`:
 * left column = categories (+ add/delete), right column = image grid with
 * multi-select and an upload button. Selection is handed back to the caller,
 * who decides what to do with the URLs. Renders nothing when closed.
 */
export default function ImageManager(props: Props) {
  const [groups, setGroups] = createSignal<UploadGroup[]>([]);
  const [activeGroup, setActiveGroup] = createSignal<number | null>(null);
  const [files, setFiles] = createSignal<FileItem[]>([]);
  const [selected, setSelected] = createSignal<Map<number, FileItem>>(new Map());
  const [loading, setLoading] = createSignal(false);
  const [uploading, setUploading] = createSignal(false);
  const [creating, setCreating] = createSignal(false);
  const [newName, setNewName] = createSignal('');
  const [error, setError] = createSignal<string | null>(null);

  const multiple = () => props.multiple ?? true;
  const max = () => props.max ?? 9;

  const loadGroups = () => listGroups().then(setGroups).catch(() => setGroups([]));

  const loadFiles = () => {
    setLoading(true);
    listFiles({ page: 1, pageSize: 60, groupId: activeGroup() ?? 0, type: 'image/' })
      .then((res) => setFiles(res.list))
      .catch(() => setFiles([]))
      .finally(() => setLoading(false));
  };

  createEffect(() => {
    if (!props.open) return;
    setError(null);
    setSelected(new Map());
    void loadGroups();
    loadFiles();
  });

  createEffect(() => {
    // Reload file list whenever the active category changes (only while open).
    if (props.open) loadFiles();
    // eslint-disable-next-line solid/reactivity
  });

  const toggle = (item: FileItem) => {
    const next = new Map(selected());
    if (next.has(item.id)) {
      next.delete(item.id);
    } else {
      if (!multiple()) next.clear();
      if (next.size >= max()) return;
      next.set(item.id, item);
    }
    setSelected(next);
  };

  const selectedList = createMemo(() => {
    // Preserve first-selected → last-selected order.
    return [...selected().values()];
  });

  const onUpload = async (e: Event & { currentTarget: HTMLInputElement }) => {
    const input = e.currentTarget;
    const fileList = input.files;
    if (!fileList || fileList.length === 0) return;
    setUploading(true);
    setError(null);
    try {
      for (const f of Array.from(fileList)) {
        await uploadFile(f, activeGroup() ?? 0);
      }
      await loadFiles();
    } catch {
      setError('上传失败，请重试');
    } finally {
      setUploading(false);
      input.value = '';
    }
  };

  const submitGroup = async () => {
    const name = newName().trim();
    if (!name) return;
    try {
      await createGroup(name, groups().length);
      setNewName('');
      setCreating(false);
      await loadGroups();
    } catch {
      setError('创建分类失败');
    }
  };

  const removeGroup = async (g: UploadGroup) => {
    if (!window.confirm(`确定删除分类「${g.group_name}」？分类下若有文件则无法删除。`)) return;
    try {
      await deleteGroup(g.id);
      if (activeGroup() === g.id) setActiveGroup(null);
      await loadGroups();
      await loadFiles();
    } catch (err) {
      setError((err as Error).message || '删除分类失败');
    }
  };

  const confirmSelection = () => {
    props.onSelect(selectedList());
    props.onClose();
  };

  return (
    <BaseModal
      open={props.open}
      title="图片管理器"
      onClose={props.onClose}
      size={props.size ?? 'xl'}
    >
      <Show when={error()}>
        <div class="alert alert-error mb-3 py-2 text-sm">{error()}</div>
      </Show>

      <div class="grid grid-cols-1 gap-4 md:grid-cols-[160px_1fr]">
        {/* Categories */}
        <div class="flex flex-col gap-1 border-r border-base-200 pr-2">
          <button
            class="btn btn-ghost btn-sm justify-start"
            classList={{ 'btn-active': activeGroup() === null }}
            onClick={() => setActiveGroup(null)}
          >
            全部图片
          </button>
          <For each={groups()}>
            {(g) => (
              <div class="group flex items-center justify-between rounded px-2 py-1 hover:bg-base-200">
                <button
                  class="flex-1 truncate text-left text-sm"
                  classList={{ 'font-semibold text-primary': activeGroup() === g.id }}
                  onClick={() => setActiveGroup(g.id)}
                >
                  {g.group_name}
                </button>
                <button
                  class="opacity-0 transition group-hover:opacity-100 text-xs text-error"
                  title="删除分类"
                  onClick={() => removeGroup(g)}
                >
                  删
                </button>
              </div>
            )}
          </For>

          <Show
            when={!creating()}
            fallback={
              <div class="flex flex-col gap-1">
                <input
                  class="input input-bordered input-xs"
                  placeholder="分类名称"
                  value={newName()}
                  onInput={(e) => setNewName(e.currentTarget.value)}
                />
                <div class="flex gap-1">
                  <button class="btn btn-primary btn-xs flex-1" onClick={submitGroup}>
                    保存
                  </button>
                  <button class="btn btn-ghost btn-xs" onClick={() => setCreating(false)}>
                    取消
                  </button>
                </div>
              </div>
            }
          >
            <button class="btn btn-outline btn-xs mt-1" onClick={() => setCreating(true)}>
              + 新建分类
            </button>
          </Show>
        </div>

        {/* Grid */}
        <div class="flex flex-col gap-3">
          <div class="flex items-center justify-between">
            <span class="text-xs text-base-content/60">
              已选 {selectedList().length}
              {multiple() ? ` / ${max()}` : ''}
            </span>
            <label class="btn btn-primary btn-sm">
              {uploading() ? '上传中…' : '上传图片'}
              <input type="file" class="hidden" accept="image/*" multiple onChange={onUpload} disabled={uploading()} />
            </label>
          </div>

          <Show
            when={!loading()}
            fallback={<div class="py-10 text-center text-sm text-base-content/50">加载中…</div>}
          >
            <Show
              when={files().length > 0}
              fallback={<div class="py-10 text-center text-sm text-base-content/40">该分类暂无图片</div>}
            >
              <div class="grid max-h-[52vh] grid-cols-3 gap-3 overflow-y-auto pr-1 sm:grid-cols-4 lg:grid-cols-5">
                <For each={files()}>
                  {(item) => (
                    <button
                      type="button"
                      class="relative aspect-square overflow-hidden rounded border-2 transition"
                      classList={{
                        'border-primary ring-2 ring-primary/30': selected().has(item.id),
                        'border-base-200 hover:border-primary/50': !selected().has(item.id),
                      }}
                      onClick={() => toggle(item)}
                      title={item.name}
                    >
                      <img src={fileUrl(item)} alt={item.name} class="h-full w-full object-cover" loading="lazy" />
                      <Show when={selected().has(item.id)}>
                        <span class="absolute right-1 top-1 flex h-5 w-5 items-center justify-center rounded-full bg-primary text-xs text-white">
                          ✓
                        </span>
                      </Show>
                    </button>
                  )}
                </For>
              </div>
            </Show>
          </Show>
        </div>
      </div>

      <div class="-mx-5 -mb-4 mt-4 flex justify-end gap-2 border-t border-base-200 bg-base-200/40 px-5 py-3">
        <button class="btn btn-ghost btn-sm" onClick={props.onClose}>
          取消
        </button>
        <button class="btn btn-primary btn-sm" disabled={selectedList().length === 0} onClick={confirmSelection}>
          确定
        </button>
      </div>
    </BaseModal>
  );
}
