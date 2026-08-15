import { For, Show, createSignal } from 'solid-js';

import {
  createShopCategory,
  createShopProduct,
  deleteShopCategory,
  deleteShopProduct,
  listShopCategories,
  listShopProducts,
  toApiError,
  type ShopCategoryItem,
  type ShopProductItem,
} from '#ui/api';
import DataTable, { type Column } from '#ui/components/DataTable';
import { useAccounts } from '#ui/hooks/useAccounts';
import { usePaged } from '#ui/hooks/usePaged';
import { formatDateTime } from '#ui/utils';

const PAGE_SIZE = 20;
const yuan = (fen: number) => (fen / 100).toFixed(2);

function Shop() {
  const accounts = useAccounts();
  const [success, setSuccess] = createSignal<string | null>(null);
  const [error, setError] = createSignal<string | null>(null);
  const [keyword, setKeyword] = createSignal('');
  const [categories, setCategories] = createSignal<ShopCategoryItem[]>([]);
  // 新建表单
  const [name, setName] = createSignal('');
  const [price, setPrice] = createSignal(0);
  const [originalPrice, setOriginalPrice] = createSignal(0);
  const [stock, setStock] = createSignal(0);
  const [categoryId, setCategoryId] = createSignal(0);
  const [newCategory, setNewCategory] = createSignal('');

  const accountId = () => accounts.selected() ?? 0;
  const paged = usePaged<ShopProductItem>(
    (page, pageSize) => listShopProducts(accountId(), page, pageSize, keyword()),
    PAGE_SIZE,
  );

  const columns: Column<ShopProductItem>[] = [
    {
      key: 'image',
      title: '图',
      render: (r) =>
        r.image ? (
          <img src={r.image} alt="" class="w-10 h-10 rounded object-cover" />
        ) : (
          <span class="text-base-content/30">无</span>
        ),
    },
    { key: 'name', title: '商品名', render: (r) => <span class="font-medium">{r.name}</span> },
    {
      key: 'price',
      title: '售价',
      render: (r) => <span class="text-error font-semibold">¥{yuan(r.price)}</span>,
    },
    {
      key: 'original_price',
      title: '原价',
      render: (r) => <span class="line-through text-base-content/50">¥{yuan(r.original_price)}</span>,
    },
    {
      key: 'stock',
      title: '库存/销量',
      render: (r) => (
        <span>
          {r.stock} / {r.sales}
        </span>
      ),
    },
    {
      key: 'status',
      title: '状态',
      render: (r) => (
        <span class={r.status === 1 ? 'text-success' : 'text-base-content/50'}>
          {r.status === 1 ? '上架' : '下架'}
        </span>
      ),
    },
    {
      key: 'created_at',
      title: '创建时间',
      render: (r) => <span class="text-sm text-base-content/70">{formatDateTime(r.created_at)}</span>,
    },
  ];

  const onAccountChange = (id: number) => {
    accounts.setSelected(id);
    void paged.reload(1);
    void reloadCategories();
  };

  const reloadCategories = async () => {
    if (accountId() === 0) return;
    try {
      setCategories(await listShopCategories(accountId()));
    } catch {
      setCategories([]);
    }
  };

  const onCreateCategory = async () => {
    const n = newCategory().trim();
    if (!n) return;
    try {
      await createShopCategory(accountId(), n);
      setNewCategory('');
      setSuccess('分类已创建');
      void reloadCategories();
    } catch (err) {
      setError(toApiError(err).message);
    }
  };

  const onCreate = async (e: SubmitEvent) => {
    e.preventDefault();
    if (accountId() === 0) return;
    setError(null);
    setSuccess(null);
    try {
      await createShopProduct({
        account_id: accountId(),
        category_id: categoryId(),
        name: name().trim(),
        price: price(),
        original_price: originalPrice(),
        stock: stock(),
      });
      setName('');
      setSuccess('商品已创建');
      void paged.reload(1);
    } catch (err) {
      setError(toApiError(err).message);
    }
  };

  const onDelete = async (id: number) => {
    try {
      await deleteShopProduct(id);
      setSuccess('已删除');
      void paged.reload(1);
    } catch (err) {
      setError(toApiError(err).message);
    }
  };

  return (
    <div class="p-6 space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">商城</h1>
        <select
          class="select select-bordered"
          onChange={(e) => onAccountChange(Number(e.currentTarget.value))}
        >
          <option value={0}>选择公众号</option>
          <For each={accounts.accounts()}>
            {(a) => <option value={a.id}>{a.name}</option>}
          </For>
        </select>
      </div>

      <Show when={success()}>
        <div class="alert alert-success">{success()}</div>
      </Show>
      <Show when={error()}>
        <div class="alert alert-error">{error()}</div>
      </Show>

      <div class="grid md:grid-cols-2 gap-4">
        <form onSubmit={onCreate} class="card bg-base-200 p-4 space-y-2">
          <h2 class="font-semibold">新建商品</h2>
          <input
            class="input input-bordered"
            placeholder="商品名"
            value={name()}
            onInput={(e) => setName(e.currentTarget.value)}
          />
          <select
            class="select select-bordered"
            value={categoryId()}
            onChange={(e) => setCategoryId(Number(e.currentTarget.value))}
          >
            <option value={0}>未分类</option>
            <For each={categories()}>
              {(c) => <option value={c.id}>{c.name}</option>}
            </For>
          </select>
          <div class="flex gap-2">
            <input
              class="input input-bordered flex-1"
              type="number"
              placeholder="售价(分)"
              value={price()}
              onInput={(e) => setPrice(Number(e.currentTarget.value))}
            />
            <input
              class="input input-bordered flex-1"
              type="number"
              placeholder="原价(分)"
              value={originalPrice()}
              onInput={(e) => setOriginalPrice(Number(e.currentTarget.value))}
            />
            <input
              class="input input-bordered w-24"
              type="number"
              placeholder="库存"
              value={stock()}
              onInput={(e) => setStock(Number(e.currentTarget.value))}
            />
          </div>
          <button class="btn btn-primary" type="submit">
            创建
          </button>
        </form>

        <div class="card bg-base-200 p-4 space-y-2">
          <h2 class="font-semibold">分类管理</h2>
          <div class="flex gap-2">
            <input
              class="input input-bordered flex-1"
              placeholder="新分类名"
              value={newCategory()}
              onInput={(e) => setNewCategory(e.currentTarget.value)}
            />
            <button class="btn btn-secondary" onClick={() => void onCreateCategory()}>
              添加
            </button>
          </div>
          <div class="flex flex-wrap gap-2">
            <For each={categories()}>
              {(c) => (
                <span class="badge badge-outline gap-2">
                  {c.name}
                  <button
                    class="text-error"
                    onClick={() => void deleteShopCategory(c.id).then(() => void reloadCategories())}
                  >
                    ✕
                  </button>
                </span>
              )}
            </For>
          </div>
          <div class="flex gap-2 pt-2">
            <input
              class="input input-bordered flex-1"
              placeholder="搜索商品名"
              value={keyword()}
              onInput={(e) => setKeyword(e.currentTarget.value)}
            />
            <button class="btn btn-outline" onClick={() => void paged.reload(1)}>
              搜索
            </button>
          </div>
        </div>
      </div>

      <DataTable
        columns={columns}
        rows={paged.items()}
        rowKey={(r) => r.id}
        total={paged.total()}
        page={paged.page()}
        totalPages={paged.totalPages()}
        loading={paged.loading()}
        error={paged.error()}
        emptyText="暂无商品"
        onPageChange={(p) => void paged.reload(p)}
        actions={(row) => (
          <button class="btn btn-xs btn-outline btn-error" onClick={() => void onDelete(row.id)}>
            删除
          </button>
        )}
      />
    </div>
  );
}

export default Shop;
