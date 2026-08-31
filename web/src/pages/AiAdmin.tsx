import { For, Show, createSignal } from 'solid-js';

import {
  checkAiProvider,
  createAiProvider,
  deleteAiProvider,
  listAiApprovals,
  listAiMetrics,
  listAiProviders,
  listAiRuns,
  listAiSkills,
  resolveAiApproval,
  runAiWorkflow,
  toApiError,
  updateAiProvider,
  type AiApprovalItem,
  type AiProviderItem,
  type AiRunItem,
  type AiWorkflowResult,
} from '#ui/api';
import DataTable, { type Column } from '#ui/components/DataTable';
import FormField from '#ui/components/FormField';
import FormModal from '#ui/components/FormModal';
import { useFeedback, usePaged } from '#ui/hooks';
import { formatDateTime } from '#ui/utils';

const PAGE_SIZE = 20;

type Tab = 'providers' | 'approvals' | 'runs' | 'skills' | 'workflow';
const TABS: { key: Tab; label: string }[] = [
  { key: 'providers', label: 'Providers' },
  { key: 'approvals', label: '待审批' },
  { key: 'runs', label: '运行日志' },
  { key: 'skills', label: '能力与指标' },
  { key: 'workflow', label: '演示工作流' },
];

function AiAdmin() {
  const feedback = useFeedback();
  const [tab, setTab] = createSignal<Tab>('providers');

  // ----- Providers -----
  const providers = usePaged<AiProviderItem>((page, pageSize) => listAiProviders(page, pageSize), PAGE_SIZE);
  const [formOpen, setFormOpen] = createSignal(false);
  const [editing, setEditing] = createSignal<AiProviderItem | null>(null);
  const [name, setName] = createSignal('');
  const [endpoint, setEndpoint] = createSignal('');
  const [apiKeys, setApiKeys] = createSignal('');
  const [models, setModels] = createSignal('');
  const [fallback, setFallback] = createSignal('');
  const [enabled, setEnabled] = createSignal(true);
  const [formError, setFormError] = createSignal<string | null>(null);
  const [saving, setSaving] = createSignal(false);
  const [checkingId, setCheckingId] = createSignal<number | null>(null);

  // ----- Approvals -----
  const [approvalStatus, setApprovalStatus] = createSignal<'pending' | 'approved' | 'rejected' | ''>('pending');
  const approvals = usePaged<AiApprovalItem>(
    (page, pageSize) => listAiApprovals(page, pageSize, approvalStatus() || undefined),
    PAGE_SIZE,
    () => approvalStatus(),
  );

  // ----- Runs -----
  const runs = usePaged<AiRunItem>((page, pageSize) => listAiRuns(page, pageSize), PAGE_SIZE);

  // ----- Skills & Metrics -----
  const [skills, setSkills] = createSignal<string[]>([]);
  const [metrics, setMetrics] = createSignal('');
  const [skillsLoading, setSkillsLoading] = createSignal(false);
  const [skillsError, setSkillsError] = createSignal<string | null>(null);

  // ----- Workflow -----
  const [workflow, setWorkflow] = createSignal<AiWorkflowResult | null>(null);
  const [wfBusy, setWfBusy] = createSignal(false);
  const [wfError, setWfError] = createSignal<string | null>(null);

  const switchTab = (t: Tab) => {
    setTab(t);
    if (t === 'skills') void loadSkills();
  };

  // ---- Providers ----
  const openCreate = () => {
    setEditing(null);
    setName('');
    setEndpoint('');
    setApiKeys('');
    setModels('');
    setFallback('');
    setEnabled(true);
    setFormError(null);
    setFormOpen(true);
  };

  const openEdit = (p: AiProviderItem) => {
    setEditing(p);
    setName(p.name);
    setEndpoint(p.endpoint);
    setApiKeys('');
    setModels(p.models);
    setFallback(p.fallback_providers);
    setEnabled(p.enabled);
    setFormError(null);
    setFormOpen(true);
  };

  const onSaveProvider = async () => {
    if (saving()) return;
    if (!name().trim() || !endpoint().trim()) {
      setFormError('名称与端点不能为空');
      return;
    }
    setSaving(true);
    setFormError(null);
    try {
      const keys = apiKeys().split('\n').map((s) => s.trim()).filter(Boolean);
      const base = {
        name: name().trim(),
        endpoint: endpoint().trim(),
        models: models().trim(),
        fallback_providers: fallback().trim() || undefined,
        enabled: enabled(),
      };

      if (editing()) {
        await updateAiProvider(
          editing()!.id,
          keys.length ? { ...base, api_keys: keys } : base,
        );
        feedback.toast('Provider 已更新');
      } else {
        if (!keys.length) {
          setFormError('新增 Provider 必须至少填写一个 API 密钥');
          setSaving(false);
          return;
        }
        await createAiProvider({ ...base, api_keys: keys });
        feedback.toast('Provider 已创建');
      }
      setFormOpen(false);
      void providers.refresh();
    } catch (err) {
      setFormError(toApiError(err).message);
    } finally {
      setSaving(false);
    }
  };

  const onRemoveProvider = (p: AiProviderItem) =>
    feedback.runAction({
      confirm: { title: '删除 Provider', message: `确定删除 Provider「${p.name}」吗？此操作不可恢复。`, danger: true },
      action: () => deleteAiProvider(p.id),
      success: '已删除',
      onDone: () => void providers.refresh(),
    });

  const onCheckProvider = async (p: AiProviderItem) => {
    setCheckingId(p.id);
    try {
      await checkAiProvider(p.id);
      feedback.toast(`Provider「${p.name}」连接正常`, 'success');
    } catch (err) {
      feedback.toast(toApiError(err).message, 'error');
    } finally {
      setCheckingId(null);
    }
  };

  // ---- Approvals ----
  const onResolve = (a: AiApprovalItem, action: 'approve' | 'reject') =>
    feedback.runAction({
      confirm: {
        title: action === 'approve' ? '批准申请' : '拒绝申请',
        message: `确定${action === 'approve' ? '批准' : '拒绝'}技能「${a.skill_name}」的申请吗？`,
        danger: action === 'reject',
      },
      action: () => resolveAiApproval(a.id, action),
      success: action === 'approve' ? '已批准' : '已拒绝',
      onDone: () => void approvals.refresh(),
    });

  // ---- Skills & Metrics ----
  const loadSkills = async () => {
    setSkillsLoading(true);
    setSkillsError(null);
    try {
      const [s, m] = await Promise.all([listAiSkills(), listAiMetrics()]);
      setSkills(s.skills);
      setMetrics(m);
    } catch (err) {
      setSkillsError(toApiError(err).message);
    } finally {
      setSkillsLoading(false);
    }
  };

  // ---- Workflow ----
  const onRunWorkflow = async () => {
    setWfBusy(true);
    setWfError(null);
    try {
      setWorkflow(await runAiWorkflow());
    } catch (err) {
      setWfError(toApiError(err).message);
    } finally {
      setWfBusy(false);
    }
  };

  // ---- Columns ----
  const providerColumns: Column<AiProviderItem>[] = [
    { key: 'id', title: 'ID', render: (p) => <span class="font-mono text-xs">{p.id}</span> },
    { key: 'name', title: '名称', render: (p) => <span class="font-medium">{p.name}</span> },
    { key: 'endpoint', title: '端点', render: (p) => <span class="max-w-xs truncate font-mono text-xs text-base-content/70">{p.endpoint}</span> },
    { key: 'models', title: '模型', render: (p) => <span class="text-sm">{p.models || '-'}</span> },
    {
      key: 'keys',
      title: '密钥',
      render: (p) => (
        <span class={`badge badge-sm ${p.has_keys ? 'badge-success' : 'badge-error'}`}>
          {p.has_keys ? '已配置' : '缺失'}
        </span>
      ),
    },
    {
      key: 'enabled',
      title: '状态',
      render: (p) => (
        <span class={`badge badge-sm ${p.enabled ? 'badge-primary' : 'badge-ghost'}`}>
          {p.enabled ? '启用' : '停用'}
        </span>
      ),
    },
  ];

  const approvalColumns: Column<AiApprovalItem>[] = [
    { key: 'id', title: 'ID', render: (a) => <span class="font-mono text-xs">{a.id}</span> },
    { key: 'skill_name', title: '技能', render: (a) => <span class="font-mono text-xs">{a.skill_name}</span> },
    { key: 'args', title: '参数', render: (a) => <span class="max-w-xs truncate font-mono text-xs text-base-content/70">{a.args}</span> },
    { key: 'requested_by', title: '请求者', render: (a) => <span class="text-sm">{a.requested_by}</span> },
    {
      key: 'status',
      title: '状态',
      render: (a) => (
        <span class={`badge badge-sm ${a.status === 'pending' ? 'badge-warning' : a.status === 'approved' ? 'badge-success' : 'badge-ghost'}`}>
          {a.status === 'pending' ? '待审批' : a.status === 'approved' ? '已批准' : '已拒绝'}
        </span>
      ),
    },
    { key: 'created_at', title: '时间', render: (a) => <span class="text-sm text-base-content/70">{formatDateTime(a.created_at)}</span> },
  ];

  const runColumns: Column<AiRunItem>[] = [
    { key: 'id', title: 'ID', render: (r) => <span class="font-mono text-xs">{r.id}</span> },
    { key: 'user_id', title: '用户', render: (r) => <span class="font-mono text-xs">{r.user_id}</span> },
    { key: 'kind', title: '类型', render: (r) => <span class="text-sm">{r.kind}</span> },
    { key: 'model', title: '模型', render: (r) => <span class="font-mono text-xs text-base-content/70">{r.model || '-'}</span> },
    { key: 'prompt', title: '提示词', render: (r) => <span class="max-w-xs truncate text-sm text-base-content/70">{r.prompt}</span> },
    {
      key: 'usage',
      title: '用量',
      render: (r) => (
        <span class="text-xs text-base-content/70">
          {(r.tokens_in || 0) > 0 || (r.tokens_out || 0) > 0 ? `${r.tokens_in || 0}→${r.tokens_out || 0} tok` : '—'}
          {(r.steps || 0) > 0 || (r.tool_calls || 0) > 0
            ? ` · ${r.steps || 0}步/${r.tool_calls || 0}工具${(r.tool_errors || 0) > 0 ? `/${r.tool_errors}错` : ''}`
            : ''}
        </span>
      ),
    },
    {
      key: 'status',
      title: '状态',
      render: (r) => <span class={`badge badge-sm ${r.status === 'ok' ? 'badge-success' : 'badge-warning'}`}>{r.status || '-'}</span>,
    },
    { key: 'created_at', title: '时间', render: (r) => <span class="text-sm text-base-content/70">{formatDateTime(r.created_at)}</span> },
  ];

  return (
    <div class="space-y-4">
      <div>
        <h2 class="text-xl font-semibold">AI 模块管理</h2>
        <p class="text-sm text-base-content/60">AI Provider 配置、人工审批队列、运行记录与可用能力</p>
      </div>

      <div role="tablist" class="tabs tabs-box">
        <For each={TABS}>
          {(item) => (
            <button
              type="button"
              role="tab"
              class="tab"
              classList={{ 'tab-active': tab() === item.key }}
              onClick={() => switchTab(item.key)}
            >
              {item.label}
            </button>
          )}
        </For>
      </div>

      {/* Providers */}
      <Show when={tab() === 'providers'}>
        <section class="rounded-box border border-base-300 bg-base-100 p-4 space-y-4">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <h3 class="text-lg font-semibold">Providers</h3>
            <button type="button" class="btn btn-primary btn-sm" onClick={openCreate}>
              新增 Provider
            </button>
          </div>
          <DataTable
            columns={providerColumns}
            rows={providers.items()}
            rowKey={(p) => p.id}
            total={providers.total()}
            page={providers.page()}
            totalPages={providers.totalPages()}
            pageSize={providers.pageSize()}
            loading={providers.loading()}
            error={providers.error()}
            emptyText="暂无 Provider。配置一个 OpenAI 兼容端点 (需设置 ZWEQ_AI_KEY_SECRET)"
            onPageChange={(p) => void providers.reload(p)}
            onPageSizeChange={(size) => providers.setPageSize(size)}
            actions={(p) => (
              <>
                <button
                  type="button"
                  class="btn btn-outline btn-xs"
                  disabled={checkingId() === p.id}
                  onClick={() => void onCheckProvider(p)}
                >
                  {checkingId() === p.id ? '测试中…' : '测试'}
                </button>
                <button type="button" class="btn btn-ghost btn-xs" onClick={() => openEdit(p)}>
                  编辑
                </button>
                <button type="button" class="btn btn-ghost btn-xs text-error" onClick={() => void onRemoveProvider(p)}>
                  删除
                </button>
              </>
            )}
          />
        </section>
      </Show>

      {/* Approvals */}
      <Show when={tab() === 'approvals'}>
        <section class="rounded-box border border-base-300 bg-base-100 p-4 space-y-4">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <h3 class="text-lg font-semibold">人工审批队列</h3>
            <select
              class="select select-bordered select-sm"
              value={approvalStatus()}
              onChange={(e) => setApprovalStatus(e.currentTarget.value as 'pending' | 'approved' | 'rejected' | '')}
            >
              <option value="pending">待审批</option>
              <option value="approved">已批准</option>
              <option value="rejected">已拒绝</option>
              <option value="">全部</option>
            </select>
          </div>
          <DataTable
            columns={approvalColumns}
            rows={approvals.items()}
            rowKey={(a) => a.id}
            total={approvals.total()}
            page={approvals.page()}
            totalPages={approvals.totalPages()}
            pageSize={approvals.pageSize()}
            loading={approvals.loading()}
            error={approvals.error()}
            emptyText="暂无审批事项"
            onPageChange={(p) => void approvals.reload(p)}
            onPageSizeChange={(size) => approvals.setPageSize(size)}
            actions={(a) => (
              <>
                <button
                  type="button"
                  class="btn btn-success btn-xs"
                  disabled={a.status !== 'pending'}
                  onClick={() => void onResolve(a, 'approve')}
                >
                  批准
                </button>
                <button
                  type="button"
                  class="btn btn-error btn-xs"
                  disabled={a.status !== 'pending'}
                  onClick={() => void onResolve(a, 'reject')}
                >
                  拒绝
                </button>
              </>
            )}
          />
        </section>
      </Show>

      {/* Runs */}
      <Show when={tab() === 'runs'}>
        <section class="rounded-box border border-base-300 bg-base-100 p-4">
          <h3 class="mb-4 text-lg font-semibold">运行日志</h3>
          <DataTable
            columns={runColumns}
            rows={runs.items()}
            rowKey={(r) => r.id}
            total={runs.total()}
            page={runs.page()}
            totalPages={runs.totalPages()}
            pageSize={runs.pageSize()}
            loading={runs.loading()}
            error={runs.error()}
            emptyText="暂无运行记录"
            onPageChange={(p) => void runs.reload(p)}
            onPageSizeChange={(size) => runs.setPageSize(size)}
          />
        </section>
      </Show>

      {/* Skills & Metrics */}
      <Show when={tab() === 'skills'}>
        <div class="grid gap-4 lg:grid-cols-2">
          <section class="rounded-box border border-base-300 bg-base-100 p-4">
            <h3 class="mb-3 text-lg font-semibold">可用能力 (Skills)</h3>
            <Show when={skillsLoading()}>
              <span class="text-sm text-base-content/60">加载中…</span>
            </Show>
            <Show when={!skillsLoading() && skillsError()}>
              <div role="alert" class="alert alert-error py-2 text-sm">{skillsError()}</div>
            </Show>
            <Show when={!skillsLoading() && !skillsError()}>
              <div class="flex flex-wrap gap-2">
                <For each={skills()} fallback={<span class="text-sm text-base-content/50">暂无已注册技能</span>}>
                  {(s) => <span class="badge badge-outline">{s}</span>}
                </For>
              </div>
            </Show>
          </section>
          <section class="rounded-box border border-base-300 bg-base-100 p-4">
            <h3 class="mb-3 text-lg font-semibold">运行指标 (Prometheus)</h3>
            <Show when={skillsLoading()}>
              <span class="text-sm text-base-content/60">加载中…</span>
            </Show>
            <Show when={!skillsLoading() && skillsError()}>
              <div role="alert" class="alert alert-error py-2 text-sm">{skillsError()}</div>
            </Show>
            <Show when={!skillsLoading() && !skillsError()}>
              <pre class="max-h-80 overflow-auto rounded bg-base-200 p-3 font-mono text-xs">{metrics()}</pre>
            </Show>
          </section>
        </div>
      </Show>

      {/* Workflow */}
      <Show when={tab() === 'workflow'}>
        <section class="rounded-box border border-base-300 bg-base-100 p-4 space-y-3">
          <div class="flex items-center justify-between">
            <p class="text-sm text-base-content/60">演示工作流：依次执行「任务统计」→「租户列表」两个只读技能并汇总结果。</p>
            <button type="button" class="btn btn-primary btn-sm" disabled={wfBusy()} onClick={() => void onRunWorkflow()}>
              {wfBusy() ? '运行中…' : '运行工作流'}
            </button>
          </div>
          <Show when={wfError()}>
            <div role="alert" class="alert alert-error py-2 text-sm">{wfError()}</div>
          </Show>
          <Show when={workflow()}>
            <div class="space-y-2 rounded-lg border border-base-300 p-4">
              <p class="text-sm font-semibold">执行状态: {workflow()!.status}</p>
              <For each={workflow()!.steps}>
                {(s) => (
                  <div class="bg-base-200 rounded p-2 font-mono text-xs">
                    <div>步骤: {s.name} ({s.status})</div>
                    <pre class="mt-1 whitespace-pre-wrap">{s.output}</pre>
                  </div>
                )}
              </For>
            </div>
          </Show>
        </section>
      </Show>

      {/* Provider form */}
      <FormModal
        open={formOpen()}
        title={editing() ? `编辑 Provider #${editing()!.id}` : '新增 Provider'}
        description="配置一个 OpenAI 兼容端点 (需设置 ZWEQ_AI_KEY_SECRET 用于加密密钥)"
        onSubmit={() => void onSaveProvider()}
        onClose={() => setFormOpen(false)}
        submitting={saving()}
        error={formError()}
        submitLabel={editing() ? '保存修改' : '创建'}
      >
        <FormField label="名称" required>
          <input
            type="text"
            class="input input-bordered input-sm w-full"
            placeholder="例如: OpenAI Main"
            value={name()}
            onInput={(e) => setName(e.currentTarget.value)}
          />
        </FormField>
        <FormField label="Base URL 端点" required>
          <input
            type="text"
            class="input input-bordered input-sm w-full font-mono text-xs"
            placeholder="例如: https://api.openai.com/v1"
            value={endpoint()}
            onInput={(e) => setEndpoint(e.currentTarget.value)}
          />
        </FormField>
        <FormField
          label="API 密钥"
          required={!editing()}
          hint={editing() ? '留空表示保持原密钥' : '每行一个密钥，例如 sk-xxx'}
        >
          <textarea
            class="textarea textarea-bordered textarea-sm w-full font-mono text-xs"
            rows={3}
            placeholder={'sk-abc...\nsk-def...'}
            value={apiKeys()}
            onInput={(e) => setApiKeys(e.currentTarget.value)}
          />
        </FormField>
        <FormField label="可用模型" hint="逗号分隔, 例如: gpt-4o,gpt-4o-mini">
          <input
            type="text"
            class="input input-bordered input-sm w-full font-mono text-xs"
            placeholder="gpt-4o,gpt-4o-mini"
            value={models()}
            onInput={(e) => setModels(e.currentTarget.value)}
          />
        </FormField>
        <FormField label="备用 Provider" hint="逗号分隔的 provider 名称, 可选">
          <input
            type="text"
            class="input input-bordered input-sm w-full font-mono text-xs"
            placeholder="openai-backup,azure-main"
            value={fallback()}
            onInput={(e) => setFallback(e.currentTarget.value)}
          />
        </FormField>
        <FormField label="状态">
          <label class="label cursor-pointer justify-start gap-2">
            <input
              type="checkbox"
              class="checkbox checkbox-sm"
              checked={enabled()}
              onChange={(e) => setEnabled(e.currentTarget.checked)}
            />
            <span class="label-text">启用该 Provider</span>
          </label>
        </FormField>
      </FormModal>
    </div>
  );
}

export default AiAdmin;
