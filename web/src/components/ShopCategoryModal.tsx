import { createEffect, createSignal, For, Show } from 'solid-js';

import {
  createShopCategory,
  deleteShopCategory,
  listShopCategories,
  toApiError,
  type ShopCategoryItem,
} from '#ui/api';
import BaseModal from '#ui/components/BaseModal';

interface Props {
  open: boolean;
  accountId: number;
  onClose: () => void;
  onChanged: () => void;
}

function ShopCategoryModal(props: Props) {
  const [categories, setCategories] = createSignal<ShopCategoryItem[]>([]);
  const [name, setName] = createSignal('');
  const [loading, setLoading] = createSignal(false);
  const [error, setError] = createSignal<string | null>(null);

  const reload = async () => {
    if (props.accountId <= 0) return;
    setLoading(true);
    try {
      setCategories(await listShopCategories(props.accountId));
    } catch (err) {
      setError(toApiError(err).message);
    } finally {
      setLoading(false);
    }
  };

  createEffect(() => {
    if (props.open && props.accountId > 0) void reload();
  });

  const onCreate = async (e: SubmitEvent) => {
    e.preventDefault();
    const n = name().trim();
    if (!n || props.accountId <= 0) return;
    try {
      await createShopCategory(props.accountId, n);
      setName('');
      await reload();
      props.onChanged();
    } catch (err) {
      setError(toApiError(err).message);
    }
  };

  const onDelete = async (id: number) => {
    if (!window.confirm('确定删除该分类？')) return;
    try {
      await deleteShopCategory(id);
      await reload();
      props.onChanged();
    } catch (err) {
      setError(toApiError(err).message);
    }
  };

  return (
    <BaseModal open={props.open} title="商品分类" onClose={props.onClose} size="md">
      <Show when={error()}>
        <div class="alert alert-error mb-3 py-2 text-sm">{error()}</div>
      </Show>
      <form onSubmit={onCreate} class="mb-4 flex gap-2">
        <input
          class="input input-bordered input-sm flex-1"
          placeholder="新分类名称"
          value={name()}
          onInput={(e) => setName(e.currentTarget.value)}
        />
        <button type="submit" class="btn btn-primary btn-sm" disabled={props.accountId <= 0}>
          添加
        </button>
      </form>
      <Show when={loading()}>
        <p class="text-sm text-base-content/50">加载中…</p>
      </Show>
      <div class="flex max-h-64 flex-wrap gap-2 overflow-y-auto">
        <For each={categories()}>
          {(c) => (
            <span class="badge badge-lg badge-outline gap-2">
              {c.name}
              <button type="button" class="text-error" onClick={() => void onDelete(c.id)}>
                ✕
              </button>
            </span>
          )}
        </For>
        <Show when={!loading() && categories().length === 0}>
          <p class="text-sm text-base-content/50">暂无分类</p>
        </Show>
      </div>
    </BaseModal>
  );
}

export default ShopCategoryModal;
