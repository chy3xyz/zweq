import { createSignal } from 'solid-js';

import { toApiError } from '#ui/api';
import { deleteSetting, listSettings, setSetting } from '#ui/api/setting/query';
import type { SettingItem } from '#ui/api/setting/types';
import AdminCrudPage from '#ui/components/AdminCrudPage';
import DataTable, { type Column } from '#ui/components/DataTable';
import FormField from '#ui/components/FormField';
import FormModal from '#ui/components/FormModal';
import { useFeedback, usePaged } from '#ui/hooks';
import { formatDateTime } from '#ui/utils';

const PAGE_SIZE = 20;

interface SettingFormState {
  key: string;
  value: string;
}

function Settings() {
  const feedback = useFeedback();

  const paged = usePaged<SettingItem>(
    (page, pageSize) => listSettings(page, pageSize),
    PAGE_SIZE,
  );

  const [modalOpen, setModalOpen] = createSignal(false);
  const [editing, setEditing] = createSignal<SettingItem | null>(null);
  const [form, setForm] = createSignal<SettingFormState>({ key: '', value: '' });
  const [submitting, setSubmitting] = createSignal(false);
  const [error, setError] = createSignal<string | null>(null);

  const setFormField = <K extends keyof SettingFormState>(key: K, value: SettingFormState[K]) => {
    setForm((prev) => ({ ...prev, [key]: value }));
  };

  const openCreate = () => {
    setEditing(null);
    setForm({ key: '', value: '' });
    setError(null);
    setModalOpen(true);
  };

  const openEdit = (item: SettingItem) => {
    setEditing(item);
    setForm({ key: item.key, value: item.value });
    setError(null);
    setModalOpen(true);
  };

  const onSubmit = async (e: SubmitEvent) => {
    e.preventDefault();
    if (submitting()) return;
    const key = form().key.trim();
    if (!key) {
      setError('配置键不能为空');
      return;
    }
    setSubmitting(true);
    setError(null);
    const editingItem = editing();
    try {
      await setSetting(key, { value: form().value });
      setModalOpen(false);
      feedback.toast(editingItem ? `设置「${key}」已更新` : `设置「${key}」已新增`, 'success');
      void paged.refresh();
    } catch (err) {
      setError(toApiError(err).message);
    } finally {
      setSubmitting(false);
    }
  };

  const onDelete = (item: SettingItem) =>
    feedback.runAction({
      confirm: { title: '删除设置', message: `确定删除配置「${item.key}」吗？`, danger: true },
      action: () => deleteSetting(item.key),
      success: `设置「${item.key}」已删除`,
      onDone: () => void paged.refresh(),
    });

  const columns: Column<SettingItem>[] = [
    { key: 'key', title: '配置键', render: (s) => <span class="font-mono text-sm">{s.key}</span> },
    { key: 'value', title: '配置值', render: (s) => <span class="text-sm">{s.value}</span> },
    {
      key: 'updated_at',
      title: '更新时间',
      render: (s) => <span class="text-sm text-base-content/70">{formatDateTime(s.updated_at)}</span>,
    },
  ];

  return (
    <AdminCrudPage
      title="站点设置"
      description="管理站点键值配置"
      total={paged.total()}
      onCreate={openCreate}
      createLabel="新增设置"
      onRefresh={() => void paged.refresh()}
    >
      <DataTable
        columns={columns}
        rows={paged.items()}
        rowKey={(s) => s.key}
        total={paged.total()}
        page={paged.page()}
        totalPages={paged.totalPages()}
        pageSize={paged.pageSize()}
        loading={paged.loading()}
        error={paged.error()}
        emptyText="暂无设置"
        onPageChange={(p) => void paged.reload(p)}
        onPageSizeChange={(size) => paged.setPageSize(size)}
        actions={(s) => (
          <>
            <button type="button" class="btn btn-ghost btn-xs" onClick={() => openEdit(s)}>
              编辑
            </button>
            <button type="button" class="btn btn-ghost btn-xs text-error" onClick={() => void onDelete(s)}>
              删除
            </button>
          </>
        )}
      />

      <FormModal
        open={modalOpen()}
        title={editing() ? '编辑设置' : '新增设置'}
        onSubmit={onSubmit}
        onClose={() => setModalOpen(false)}
        submitting={submitting()}
        error={error()}
        size="md"
      >
        <FormField label="配置键" required>
          <input
            type="text"
            class="input input-bordered input-sm w-full"
            placeholder="site_name"
            value={form().key}
            onInput={(e) => setFormField('key', e.currentTarget.value)}
            disabled={!!editing()}
            required
          />
        </FormField>
        <FormField label="配置值" required>
          <textarea
            class="textarea textarea-bordered w-full font-mono text-sm"
            rows={6}
            value={form().value}
            onInput={(e) => setFormField('value', e.currentTarget.value)}
            placeholder="配置内容"
            required
          />
        </FormField>
      </FormModal>
    </AdminCrudPage>
  );
}

export default Settings;
