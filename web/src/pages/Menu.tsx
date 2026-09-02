import { Show, createMemo, createSignal } from 'solid-js';

import {
  deleteRemoteMenu,
  fetchMenu,
  getMenu,
  publishMenu,
  saveMenu,
  type WechatMenuButton,
} from '#ui/api';
import AccountRequiredBanner from '#ui/components/AccountRequiredBanner';
import AdminCrudPage from '#ui/components/AdminCrudPage';
import DataTable, { type Column } from '#ui/components/DataTable';
import MenuButtonFormModal from '#ui/components/MenuButtonFormModal';
import Tabs from '#ui/components/Tabs';
import { useAccountId, useFeedback } from '#ui/hooks';

const TABS = ['菜单列表', '原始 JSON'] as const;

interface FlatRow {
  topIndex: number;
  subIndex: number | null;
  path: string;
  name: string;
  typeLabel: string;
  detail: string;
}

function parseMenuJson(json: string): { buttons: WechatMenuButton[]; error: string | null } {
  const trimmed = json.trim();
  if (!trimmed) return { buttons: [], error: null };
  try {
    const parsed = JSON.parse(trimmed);
    if (!Array.isArray(parsed)) return { buttons: [], error: '菜单 JSON 必须是一个数组' };
    return { buttons: parsed as WechatMenuButton[], error: null };
  } catch {
    return { buttons: [], error: '菜单 JSON 解析失败，请检查格式' };
  }
}

function typeLabel(type?: string): string {
  switch (type) {
    case 'click':
      return '点击推事件';
    case 'view':
      return '跳转 URL';
    case 'miniprogram':
      return '小程序';
    case 'media_id':
      return '下发消息';
    default:
      return type || '-';
  }
}

function detailText(button: WechatMenuButton): string {
  if (button.key) return `key: ${button.key}`;
  if (button.url) return `url: ${button.url}`;
  if (button.media_id) return `media_id: ${button.media_id}`;
  return '';
}

function Menu() {
  const { accountId, onAccountChange } = useAccountId();
  const feedback = useFeedback();

  const [menuJson, setMenuJson] = createSignal('[]');
  const [activeTab, setActiveTab] = createSignal<(typeof TABS)[number]>('菜单列表');
  const [busy, setBusy] = createSignal(false);

  const [modalOpen, setModalOpen] = createSignal(false);
  const [modalMode, setModalMode] = createSignal<'create' | 'edit'>('create');
  const [modalParentIndex, setModalParentIndex] = createSignal<number | null>(null);
  const [modalEditIndex, setModalEditIndex] = createSignal<{ top: number; sub: number | null } | null>(null);
  const [modalInitial, setModalInitial] = createSignal<WechatMenuButton | undefined>(undefined);
  const [modalParentName, setModalParentName] = createSignal<string | undefined>(undefined);

  const parsed = createMemo(() => parseMenuJson(menuJson()));
  const buttons = () => parsed().buttons;
  const parseError = () => parsed().error;

  const rows = createMemo<FlatRow[]>(() => {
    const result: FlatRow[] = [];
    buttons().forEach((top, topIndex) => {
      result.push({
        topIndex,
        subIndex: null,
        path: top.name,
        name: top.name,
        typeLabel: typeLabel(top.type),
        detail: detailText(top),
      });
      (top.sub_button ?? []).forEach((sub, subIndex) => {
        result.push({
          topIndex,
          subIndex,
          path: `${top.name} / ${sub.name}`,
          name: sub.name,
          typeLabel: typeLabel(sub.type),
          detail: detailText(sub),
        });
      });
    });
    return result;
  });

  const load = async (id: number) => {
    if (id === 0) return;
    try {
      const m = await getMenu(id);
      setMenuJson(m.menu_json || '[]');
    } catch {
      setMenuJson('[]');
      feedback.toast('加载菜单失败', 'error');
    }
  };

  onAccountChange(() => {
    void load(accountId());
  });

  const syncJson = (newButtons: WechatMenuButton[]) => {
    setMenuJson(JSON.stringify(newButtons, null, 2));
  };

  const onSave = async () => {
    if (accountId() === 0) return;
    if (parseError()) {
      feedback.toast('请先修正菜单 JSON 格式', 'error');
      return;
    }
    setBusy(true);
    try {
      await saveMenu(accountId(), { menu_json: menuJson() });
      feedback.toast('菜单已保存');
    } catch (err) {
      feedback.toast(err instanceof Error ? err.message : '保存失败，请检查菜单 JSON 后重试', 'error');
    } finally {
      setBusy(false);
    }
  };

  const onPublish = async () => {
    if (accountId() === 0) return;
    if (parseError()) {
      feedback.toast('菜单 JSON 格式有误，无法发布', 'error');
      return;
    }
    setBusy(true);
    try {
      await publishMenu(accountId());
      feedback.toast('菜单已发布到微信');
    } catch (err) {
      feedback.toast(err instanceof Error ? err.message : String(err), 'error');
    } finally {
      setBusy(false);
    }
  };

  const onFetch = async () => {
    if (accountId() === 0) return;
    try {
      const m = await fetchMenu(accountId());
      setMenuJson(m.menu_json || '[]');
      feedback.toast('已从微信拉取');
    } catch (err) {
      feedback.toast(err instanceof Error ? err.message : String(err), 'error');
    }
  };

  const onDeleteRemote = async () => {
    if (accountId() === 0) return;
    await feedback.runAction({
      confirm: { title: '删除微信菜单', message: '确定删除已发布到微信的菜单吗？', danger: true },
      action: () => deleteRemoteMenu(accountId()),
      success: '已删除微信菜单',
    });
  };

  const openCreateTop = () => {
    setModalMode('create');
    setModalParentIndex(null);
    setModalEditIndex(null);
    setModalInitial(undefined);
    setModalParentName(undefined);
    setModalOpen(true);
  };

  const openCreateSub = (topIndex: number) => {
    const parent = buttons()[topIndex];
    if (!parent) return;
    setModalMode('create');
    setModalParentIndex(topIndex);
    setModalEditIndex(null);
    setModalInitial(undefined);
    setModalParentName(parent.name);
    setModalOpen(true);
  };

  const openEdit = (topIndex: number, subIndex: number | null) => {
    const top = buttons()[topIndex];
    if (!top) return;
    const button = subIndex === null ? top : top.sub_button?.[subIndex];
    if (!button) return;
    setModalMode('edit');
    setModalParentIndex(subIndex === null ? null : topIndex);
    setModalEditIndex({ top: topIndex, sub: subIndex });
    setModalInitial(button);
    setModalParentName(subIndex === null ? undefined : top.name);
    setModalOpen(true);
  };

  const handleModalSave = (button: WechatMenuButton) => {
    const current: WechatMenuButton[] = JSON.parse(JSON.stringify(buttons()));
    const mode = modalMode();
    const parentIndex = modalParentIndex();
    const editIndex = modalEditIndex();

    if (mode === 'create') {
      if (parentIndex === null) {
        current.push(button);
      } else {
        const parent = current[parentIndex];
        if (parent) {
          if (!parent.sub_button) parent.sub_button = [];
          parent.sub_button.push(button);
        }
      }
    } else if (editIndex) {
      const { top, sub } = editIndex;
      if (sub === null) {
        current[top] = { ...button, sub_button: current[top].sub_button };
      } else {
        const parent = current[top];
        if (parent?.sub_button) {
          parent.sub_button[sub] = button;
        }
      }
    }

    syncJson(current);
    setModalOpen(false);
    feedback.toast(mode === 'create' ? '菜单已添加' : '菜单已更新');
  };

  const onDeleteButton = (topIndex: number, subIndex: number | null) => {
    const top = buttons()[topIndex];
    if (!top) return;
    const label = subIndex === null ? top.name : top.sub_button?.[subIndex]?.name ?? '';
    void feedback.runAction({
      confirm: { title: '删除菜单', message: `确定删除菜单「${label}」吗？`, danger: true },
      action: async () => {
        const current: WechatMenuButton[] = JSON.parse(JSON.stringify(buttons()));
        if (subIndex === null) {
          current.splice(topIndex, 1);
        } else {
          const parent = current[topIndex];
          if (parent?.sub_button) {
            parent.sub_button = parent.sub_button.filter((_, i) => i !== subIndex);
          }
        }
        syncJson(current);
      },
      success: '菜单已删除',
    });
  };

  const columns: Column<FlatRow>[] = [
    {
      key: 'path',
      title: '路径',
      render: (r) => (
        <span class={r.subIndex === null ? 'font-medium' : 'pl-6 text-base-content/70'}>{r.path}</span>
      ),
    },
    {
      key: 'type',
      title: '类型',
      render: (r) => <span class="badge badge-sm badge-ghost">{r.typeLabel}</span>,
    },
    {
      key: 'detail',
      title: '详情',
      render: (r) => <span class="font-mono text-sm text-base-content/70">{r.detail}</span>,
    },
  ];

  return (
    <div class="p-6 space-y-6">
      <h1 class="text-2xl font-bold">公众号菜单</h1>
      <AccountRequiredBanner />

      <Tabs tabs={[...TABS]} active={activeTab()} onChange={setActiveTab} class="mb-4" />

      <Show when={activeTab() === '菜单列表'}>
        <AdminCrudPage
          title="菜单列表"
          description="可视化编辑公众号自定义菜单"
          total={rows().length}
          onCreate={openCreateTop}
          createLabel="添加一级按钮"
          onRefresh={() => void load(accountId())}
        >
          <Show when={parseError()}>
            <div role="alert" class="alert alert-error mb-4 py-2 text-sm">
              {parseError()}
            </div>
          </Show>

          <DataTable
            columns={columns}
            rows={rows()}
            rowKey={(r) => `${r.topIndex}-${r.subIndex ?? 'top'}`}
            total={rows().length}
            page={1}
            totalPages={1}
            pageSize={rows().length || 1}
            loading={false}
            error={null}
            emptyText="暂无菜单按钮"
            onPageChange={() => {}}
            onPageSizeChange={() => {}}
            actions={(r) => (
              <div class="flex justify-end gap-1">
                <button type="button" class="btn btn-ghost btn-xs" onClick={() => openEdit(r.topIndex, r.subIndex)}>
                  编辑
                </button>
                <Show when={r.subIndex === null}>
                  <button
                    type="button"
                    class="btn btn-ghost btn-xs"
                    onClick={() => openCreateSub(r.topIndex)}
                  >
                    添加子按钮
                  </button>
                </Show>
                <button
                  type="button"
                  class="btn btn-ghost btn-xs text-error"
                  onClick={() => void onDeleteButton(r.topIndex, r.subIndex)}
                >
                  删除
                </button>
              </div>
            )}
          />

          <div class="mt-4 flex flex-wrap gap-2">
            <button class="btn btn-primary" disabled={busy()} onClick={() => void onSave()}>
              保存
            </button>
            <button class="btn btn-secondary" disabled={busy()} onClick={() => void onPublish()}>
              发布到微信
            </button>
            <button class="btn btn-outline" disabled={busy()} onClick={() => void onFetch()}>
              从微信拉取
            </button>
            <button class="btn btn-outline btn-error" disabled={busy()} onClick={() => void onDeleteRemote()}>
              删除微信菜单
            </button>
          </div>
        </AdminCrudPage>
      </Show>

      <Show when={activeTab() === '原始 JSON'}>
        <div class="card bg-base-200 p-4 space-y-3">
          <h2 class="font-semibold">菜单 JSON（buttons 数组）</h2>
          <Show when={parseError()}>
            <div role="alert" class="alert alert-error py-2 text-sm">
              {parseError()}
            </div>
          </Show>
          <textarea
            class="textarea textarea-bordered font-mono h-96 w-full"
            value={menuJson()}
            onInput={(e) => setMenuJson(e.currentTarget.value)}
          />
          <div class="flex flex-wrap gap-2">
            <button class="btn btn-primary" disabled={busy()} onClick={() => void onSave()}>
              保存
            </button>
            <button class="btn btn-secondary" disabled={busy()} onClick={() => void onPublish()}>
              发布到微信
            </button>
            <button class="btn btn-outline" disabled={busy()} onClick={() => void onFetch()}>
              从微信拉取
            </button>
            <button class="btn btn-outline btn-error" disabled={busy()} onClick={() => void onDeleteRemote()}>
              删除微信菜单
            </button>
          </div>
        </div>
      </Show>

      <MenuButtonFormModal
        open={modalOpen()}
        mode={modalMode()}
        parentName={modalParentName()}
        initial={modalInitial()}
        onSave={handleModalSave}
        onClose={() => setModalOpen(false)}
      />
    </div>
  );
}

export default Menu;
