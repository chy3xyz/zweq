import { createEffect, createSignal, For, Show } from 'solid-js';

import {
  createShopProduct,
  getShopProduct,
  listShopCategories,
  toApiError,
  updateShopProduct,
  type ShopCategoryItem,
  type ShopProductItem,
} from '#ui/api';
import BaseModal from '#ui/components/BaseModal';
import { fenToYuan, yuanToFen } from '#ui/utils/money';

export type ShopProductFormMode = 'create' | 'edit';

interface Props {
  open: boolean;
  mode: ShopProductFormMode;
  accountId: number;
  product: ShopProductItem | null;
  onClose: () => void;
  onSaved: () => void;
}

function ShopProductFormModal(props: Props) {
  const [categories, setCategories] = createSignal<ShopCategoryItem[]>([]);
  const [name, setName] = createSignal('');
  const [categoryId, setCategoryId] = createSignal(0);
  const [priceYuan, setPriceYuan] = createSignal('');
  const [originalYuan, setOriginalYuan] = createSignal('');
  const [stock, setStock] = createSignal(0);
  const [image, setImage] = createSignal('');
  const [content, setContent] = createSignal('');
  const [status, setStatus] = createSignal(1);
  const [submitting, setSubmitting] = createSignal(false);
  const [error, setError] = createSignal<string | null>(null);

  const resetForm = (product: ShopProductItem | null) => {
    setError(null);
    if (product) {
      setName(product.name);
      setCategoryId(product.category_id);
      setPriceYuan(fenToYuan(product.price));
      setOriginalYuan(fenToYuan(product.original_price));
      setStock(product.stock);
      setImage(product.image);
      setContent(product.content);
      setStatus(product.status);
    } else {
      setName('');
      setCategoryId(0);
      setPriceYuan('');
      setOriginalYuan('');
      setStock(0);
      setImage('');
      setContent('');
      setStatus(1);
    }
  };

  createEffect(() => {
    if (!props.open || props.accountId <= 0) return;
    void listShopCategories(props.accountId).then(setCategories).catch(() => setCategories([]));
    if (props.mode === 'edit' && props.product) {
      void getShopProduct(props.product.id)
        .then((detail) => resetForm(detail.product))
        .catch(() => resetForm(props.product));
    } else {
      resetForm(null);
    }
  });

  const onSubmit = async (e: SubmitEvent) => {
    e.preventDefault();
    if (submitting() || props.accountId <= 0) return;
    const price = yuanToFen(Number(priceYuan()));
    const original = originalYuan() ? yuanToFen(Number(originalYuan())) : price;
    if (!name().trim() || price <= 0) {
      setError('请填写商品名和有效售价');
      return;
    }
    setSubmitting(true);
    setError(null);
    const body = {
      account_id: props.accountId,
      category_id: categoryId(),
      name: name().trim(),
      image: image().trim(),
      content: content().trim(),
      price,
      original_price: original,
      stock: stock(),
      status: status(),
    };
    try {
      if (props.mode === 'create') {
        await createShopProduct(body);
      } else if (props.product) {
        await updateShopProduct(props.product.id, body);
      }
      props.onSaved();
      props.onClose();
    } catch (err) {
      setError(toApiError(err).message);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <BaseModal
      open={props.open}
      title={props.mode === 'create' ? '新增商品' : `编辑商品 #${props.product?.id ?? ''}`}
      onClose={props.onClose}
      size="lg"
    >
      <Show when={error()}>
        <div class="alert alert-error mb-3 py-2 text-sm">{error()}</div>
      </Show>
      <form onSubmit={onSubmit} class="grid grid-cols-1 gap-3 md:grid-cols-2">
        <label class="form-control md:col-span-2">
          <span class="label-text mb-1">商品名称</span>
          <input
            class="input input-bordered"
            value={name()}
            onInput={(e) => setName(e.currentTarget.value)}
            required
          />
        </label>
        <label class="form-control">
          <span class="label-text mb-1">分类</span>
          <select
            class="select select-bordered"
            value={categoryId()}
            onChange={(e) => setCategoryId(Number(e.currentTarget.value))}
          >
            <option value={0}>未分类</option>
            <For each={categories()}>{(c) => <option value={c.id}>{c.name}</option>}</For>
          </select>
        </label>
        <label class="form-control">
          <span class="label-text mb-1">上架状态</span>
          <select
            class="select select-bordered"
            value={status()}
            onChange={(e) => setStatus(Number(e.currentTarget.value))}
          >
            <option value={1}>上架</option>
            <option value={0}>下架</option>
          </select>
        </label>
        <label class="form-control">
          <span class="label-text mb-1">售价（元）</span>
          <input
            class="input input-bordered"
            type="number"
            min={0.01}
            step={0.01}
            value={priceYuan()}
            onInput={(e) => setPriceYuan(e.currentTarget.value)}
            required
          />
        </label>
        <label class="form-control">
          <span class="label-text mb-1">原价（元）</span>
          <input
            class="input input-bordered"
            type="number"
            min={0}
            step={0.01}
            value={originalYuan()}
            onInput={(e) => setOriginalYuan(e.currentTarget.value)}
          />
        </label>
        <label class="form-control">
          <span class="label-text mb-1">库存</span>
          <input
            class="input input-bordered"
            type="number"
            min={0}
            value={stock()}
            onInput={(e) => setStock(Number(e.currentTarget.value))}
          />
        </label>
        <label class="form-control">
          <span class="label-text mb-1">封面图 URL</span>
          <input
            class="input input-bordered"
            value={image()}
            onInput={(e) => setImage(e.currentTarget.value)}
            placeholder="https://..."
          />
        </label>
        <label class="form-control md:col-span-2">
          <span class="label-text mb-1">详情描述</span>
          <textarea
            class="textarea textarea-bordered min-h-24"
            value={content()}
            onInput={(e) => setContent(e.currentTarget.value)}
          />
        </label>
        <div class="flex justify-end gap-2 md:col-span-2">
          <button type="button" class="btn" onClick={props.onClose}>
            取消
          </button>
          <button type="submit" class="btn btn-primary" disabled={submitting()}>
            {submitting() ? '保存中…' : '保存'}
          </button>
        </div>
      </form>
    </BaseModal>
  );
}

export default ShopProductFormModal;
