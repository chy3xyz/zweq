import { createSignal } from 'solid-js';

import {
  deleteShopProduct,
  listShopCategories,
  listShopProducts,
  type ShopCategoryItem,
  type ShopProductItem,
} from '#ui/api';
import AccountRequiredBanner from '#ui/components/AccountRequiredBanner';
import AdminCrudPage from '#ui/components/AdminCrudPage';
import DataTable, { type Column } from '#ui/components/DataTable';
import SearchBar, { type SearchField, type SearchValues } from '#ui/components/SearchBar';
import ShopCategoryModal from '#ui/components/ShopCategoryModal';
import ShopProductFormModal, { type ShopProductFormMode } from '#ui/components/ShopProductFormModal';
import { useAccountId, useFeedback, usePaged } from '#ui/hooks';
import { formatDateTime, intParam } from '#ui/utils';
import { formatYuan } from '#ui/utils/money';

function Shop() {
  const { accountId, ready, accountName, onAccountChange } = useAccountId();
  const feedback = useFeedback();
  const [filters, setFilters] = createSignal<SearchValues>({});
  const [categories, setCategories] = createSignal<ShopCategoryItem[]>([]);

  const [productModalOpen, setProductModalOpen] = createSignal(false);
  const [productModalMode, setProductModalMode] = createSignal<ShopProductFormMode>('create');
  const [editingProduct, setEditingProduct] = createSignal<ShopProductItem | null>(null);
  const [categoryModalOpen, setCategoryModalOpen] = createSignal(false);

  const paged = usePaged<ShopProductItem>(
    (page, pageSize) =>
      listShopProducts(
        accountId(),
        page,
        pageSize,
        filters().keyword?.trim() ?? '',
        Number(filters().category_id ?? 0),
        intParam(filters().status, -1),
      ),
    20,
    () => [accountId(), filters()],
  );

  const searchFields = (): SearchField[] => [
    { kind: 'text', key: 'keyword', label: '商品名称', placeholder: '搜索商品名' },
    {
      kind: 'select',
      key: 'category_id',
      label: '分类',
      options: [
        { value: '0', label: '全部分类' },
        ...categories().map((c) => ({ value: String(c.id), label: c.name })),
      ],
    },
    {
      kind: 'select',
      key: 'status',
      label: '状态',
      options: [
        { value: '', label: '全部' },
        { value: '1', label: '上架' },
        { value: '0', label: '下架' },
      ],
    },
  ];

  const reloadCategories = async () => {
    if (!ready()) return;
    try {
      setCategories(await listShopCategories(accountId()));
    } catch {
      setCategories([]);
    }
  };

  onAccountChange(() => {
    void reloadCategories();
  });

  const categoryName = (id: number) => categories().find((c) => c.id === id)?.name ?? '未分类';

  const openCreate = () => {
    setProductModalMode('create');
    setEditingProduct(null);
    setProductModalOpen(true);
  };

  const openEdit = (product: ShopProductItem) => {
    setProductModalMode('edit');
    setEditingProduct(product);
    setProductModalOpen(true);
  };

  const onDelete = (product: ShopProductItem) =>
    feedback.runAction({
      confirm: {
        title: '删除商品',
        message: `确定删除商品「${product.name}」吗？`,
        danger: true,
      },
      action: () => deleteShopProduct(product.id),
      success: '商品已删除',
      onDone: () => void paged.refresh(),
    });

  const columns: Column<ShopProductItem>[] = [
    {
      key: 'image',
      title: '封面',
      render: (r) =>
        r.image ? (
          <img src={r.image} alt="" class="h-12 w-12 rounded object-cover" />
        ) : (
          <div class="flex h-12 w-12 items-center justify-center rounded bg-base-200 text-xs text-base-content/40">
            无图
          </div>
        ),
    },
    {
      key: 'name',
      title: '商品',
      render: (r) => (
        <div>
          <p class="font-medium">{r.name}</p>
          <p class="text-xs text-base-content/50">
            ID {r.id} · {categoryName(r.category_id)}
          </p>
        </div>
      ),
    },
    {
      key: 'price',
      title: '售价 / 原价',
      render: (r) => (
        <div>
          <p class="font-semibold text-error">{formatYuan(r.price)}</p>
          <p class="text-xs text-base-content/50 line-through">{formatYuan(r.original_price)}</p>
        </div>
      ),
    },
    {
      key: 'stock',
      title: '库存 / 销量',
      render: (r) => (
        <span>
          {r.stock} / <span class="text-base-content/60">{r.sales}</span>
        </span>
      ),
    },
    {
      key: 'status',
      title: '状态',
      render: (r) => (
        <span class={`badge badge-sm ${r.status === 1 ? 'badge-success' : 'badge-ghost'}`}>
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

  return (
    <AdminCrudPage
      title="商品管理"
      description={ready() ? `当前公众号：${accountName()}` : undefined}
      total={paged.total()}
      onCreate={ready() ? openCreate : undefined}
      createLabel="新增商品"
      onRefresh={() => void paged.refresh()}
      extra={
        <button
          type="button"
          class="btn btn-outline btn-sm"
          disabled={!ready()}
          onClick={() => setCategoryModalOpen(true)}
        >
          分类管理
        </button>
      }
      search={
        <SearchBar
          fields={searchFields()}
          values={{ category_id: '0', status: '' }}
          loading={paged.loading()}
          onSearch={setFilters}
        />
      }
    >
      <AccountRequiredBanner />

      <DataTable
        columns={columns}
        rows={paged.items()}
        rowKey={(r) => r.id}
        total={paged.total()}
        page={paged.page()}
        totalPages={paged.totalPages()}
        pageSize={paged.pageSize()}
        loading={paged.loading()}
        error={paged.error()}
        emptyText="暂无商品"
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

      <ShopProductFormModal
        open={productModalOpen()}
        mode={productModalMode()}
        accountId={accountId()}
        product={editingProduct()}
        onClose={() => setProductModalOpen(false)}
        onSaved={() => {
          feedback.toast(productModalMode() === 'create' ? '商品已创建' : '商品已更新');
          void paged.refresh();
        }}
      />
      <ShopCategoryModal
        open={categoryModalOpen()}
        accountId={accountId()}
        onClose={() => setCategoryModalOpen(false)}
        onChanged={() => void reloadCategories()}
      />
    </AdminCrudPage>
  );
}

export default Shop;
