import { Show, createSignal } from 'solid-js';

import {
  getConfig,
  listDrawRecords,
  manualDraw,
  setConfig as updateConfig,
  toApiError,
  type DrawRecord,
} from '#ui/api';
import { fileUrl, type FileItem } from '#ui/api/file/types';
import AccountRequiredBanner from '#ui/components/AccountRequiredBanner';
import AdminCrudPage from '#ui/components/AdminCrudPage';
import DataTable, { type Column } from '#ui/components/DataTable';
import FormField from '#ui/components/FormField';
import FormModal from '#ui/components/FormModal';
import ImageManager from '#ui/components/ImageManager';
import Tabs from '#ui/components/Tabs';
import { useAccountId, useFeedback, usePaged } from '#ui/hooks';
import { formatDateTime } from '#ui/utils';

const TABS = ['基础设置', '奖品管理', '模拟抽奖', '中奖记录'] as const;
type Tab = (typeof TABS)[number];

const PAGE_SIZE = 20;

interface Prize {
  name: string;
  weight: number;
  points: number;
  image?: string;
}

interface LuckyDrawConfig {
  cost: number;
  daily_limit: number;
  prizes: Prize[];
}

const DEFAULT_CONFIG: LuckyDrawConfig = {
  cost: 0,
  daily_limit: 0,
  prizes: [
    { name: '10积分', weight: 50, points: 10 },
    { name: '50积分', weight: 30, points: 50 },
    { name: '谢谢参与', weight: 20, points: 0 },
  ],
};

function parseConfig(json: string): LuckyDrawConfig {
  if (!json || !json.trim()) return DEFAULT_CONFIG;
  try {
    const parsed = JSON.parse(json) as Partial<LuckyDrawConfig>;
    return {
      cost: typeof parsed.cost === 'number' ? parsed.cost : DEFAULT_CONFIG.cost,
      daily_limit: typeof parsed.daily_limit === 'number' ? parsed.daily_limit : DEFAULT_CONFIG.daily_limit,
      prizes: Array.isArray(parsed.prizes)
        ? parsed.prizes.filter((p): p is Prize => typeof p === 'object' && p != null && typeof p.name === 'string')
        : DEFAULT_CONFIG.prizes,
    };
  } catch {
    return DEFAULT_CONFIG;
  }
}

function LuckyDraw() {
  const { accountId, onAccountChange } = useAccountId();
  const feedback = useFeedback();
  const [activeTab, setActiveTab] = createSignal<Tab>('奖品管理');
  const [config, setConfig] = createSignal<LuckyDrawConfig>(DEFAULT_CONFIG);
  const [savedConfigJson, setSavedConfigJson] = createSignal<string>(JSON.stringify(DEFAULT_CONFIG));
  const [saving, setSaving] = createSignal(false);

  const [openidInput, setOpenidInput] = createSignal('');
  const [lastDraw, setLastDraw] = createSignal<string | null>(null);
  const [drawSubmitting, setDrawSubmitting] = createSignal(false);

  const [prizeOpen, setPrizeOpen] = createSignal(false);
  const [editingIndex, setEditingIndex] = createSignal<number | null>(null);
  const [prizeName, setPrizeName] = createSignal('');
  const [prizeWeight, setPrizeWeight] = createSignal(0);
  const [prizePoints, setPrizePoints] = createSignal(0);
  const [prizeImage, setPrizeImage] = createSignal('');
  const [prizeError, setPrizeError] = createSignal<string | null>(null);
  const [prizeSubmitting, setPrizeSubmitting] = createSignal(false);
  const [imageOpen, setImageOpen] = createSignal(false);

  const [costError, setCostError] = createSignal<string | null>(null);
  const [dailyLimitError, setDailyLimitError] = createSignal<string | null>(null);

  const paged = usePaged<DrawRecord>(
    (page, pageSize) => listDrawRecords(accountId(), page, pageSize),
    PAGE_SIZE,
    accountId,
  );

  const loadConfig = async (id: number) => {
    setCostError(null);
    setDailyLimitError(null);
    if (id === 0) {
      setConfig(DEFAULT_CONFIG);
      setSavedConfigJson(JSON.stringify(DEFAULT_CONFIG));
      return;
    }
    try {
      const cfg = await getConfig(id);
      const parsed = parseConfig(cfg);
      setConfig(parsed);
      setSavedConfigJson(JSON.stringify(parsed));
    } catch {
      setConfig(DEFAULT_CONFIG);
      setSavedConfigJson(JSON.stringify(DEFAULT_CONFIG));
    }
  };

  onAccountChange(() => {
    void loadConfig(accountId());
  });

  const clampNonNegativeNumber = (raw: string): { value: number; error: string | null } => {
    if (raw.trim() === '') return { value: 0, error: null };
    const num = Number(raw);
    if (Number.isNaN(num)) return { value: 0, error: '请输入有效数字' };
    if (num < 0) return { value: 0, error: '不能为负数' };
    return { value: num, error: null };
  };

  const normalizeConfig = (cfg: LuckyDrawConfig): LuckyDrawConfig => ({
    ...cfg,
    cost: Number.isNaN(cfg.cost) || cfg.cost < 0 ? 0 : cfg.cost,
    daily_limit: Number.isNaN(cfg.daily_limit) || cfg.daily_limit < 0 ? 0 : cfg.daily_limit,
  });

  const saveConfig = async () => {
    if (accountId() === 0 || saving()) return;
    setSaving(true);
    try {
      const cfg = normalizeConfig(config());
      setConfig(cfg);
      setCostError(null);
      setDailyLimitError(null);
      const json = JSON.stringify(cfg);
      await updateConfig(accountId(), json);
      setSavedConfigJson(json);
      feedback.toast('配置已保存');
    } catch (err) {
      feedback.toast(toApiError(err).message, 'error');
    } finally {
      setSaving(false);
    }
  };

  const openCreatePrize = () => {
    setEditingIndex(null);
    setPrizeName('');
    setPrizeWeight(0);
    setPrizePoints(0);
    setPrizeImage('');
    setPrizeError(null);
    setPrizeOpen(true);
  };

  const openEditPrize = (prize: Prize, index: number) => {
    setEditingIndex(index);
    setPrizeName(prize.name);
    setPrizeWeight(prize.weight);
    setPrizePoints(prize.points);
    setPrizeImage(prize.image ?? '');
    setPrizeError(null);
    setPrizeOpen(true);
  };

  const closePrizeModal = () => setPrizeOpen(false);

  const onSavePrize = (e: SubmitEvent) => {
    e.preventDefault();
    if (prizeSubmitting()) return;
    setPrizeSubmitting(true);
    setPrizeError(null);
    try {
      const name = prizeName().trim();
      if (!name) throw new Error('奖品名称不能为空');
      const weight = Number(prizeWeight());
      if (Number.isNaN(weight) || weight < 0) throw new Error('权重必须为非负数');
      const points = Number(prizePoints());
      if (Number.isNaN(points) || points < 0) throw new Error('积分必须为非负数');
      const image = prizeImage().trim() || undefined;
      const newPrize: Prize = { name, weight, points, image };

      setConfig((prev) => {
        const next = [...prev.prizes];
        const idx = editingIndex();
        if (idx != null && idx >= 0 && idx < next.length) {
          next[idx] = newPrize;
        } else {
          next.push(newPrize);
        }
        return { ...prev, prizes: next };
      });
      setPrizeOpen(false);
    } catch (err) {
      setPrizeError(err instanceof Error ? err.message : '保存失败');
    } finally {
      setPrizeSubmitting(false);
    }
  };

  const onDeletePrize = async (index: number) => {
    const prize = config().prizes[index];
    if (!prize) return;
    const confirmed = await feedback.confirm({
      title: '删除奖品',
      message: `确定删除奖品「${prize.name}」吗？`,
      danger: true,
    });
    if (!confirmed) return;
    setConfig((prev) => {
      const next = [...prev.prizes];
      next.splice(index, 1);
      return { ...prev, prizes: next };
    });
  };

  const onSelectImage = (items: FileItem[]) => {
    if (items[0]) setPrizeImage(fileUrl(items[0]));
  };

  const onDraw = async () => {
    if (accountId() === 0) return;
    const openid = openidInput().trim();
    if (!openid) {
      feedback.toast('请输入粉丝 openid', 'error');
      return;
    }
    setDrawSubmitting(true);
    setLastDraw(null);
    try {
      const result = await manualDraw({
        account_id: accountId(),
        openid,
        config: savedConfigJson(),
      });
      setLastDraw(`抽中「${result.prize_name}」${result.points > 0 ? ` +${result.points} 积分` : ''}`);
      setOpenidInput('');
      void paged.reload(1);
    } catch (err) {
      feedback.toast(toApiError(err).message, 'error');
    } finally {
      setDrawSubmitting(false);
    }
  };

  const recordColumns: Column<DrawRecord>[] = [
    { key: 'openid', title: '粉丝', render: (r) => <span class="font-mono text-xs">{r.openid}</span> },
    { key: 'prize_name', title: '奖品', render: (r) => <span class="font-medium">{r.prize_name}</span> },
    { key: 'points', title: '积分', render: (r) => <span>{r.points}</span> },
    {
      key: 'created_at',
      title: '时间',
      render: (r) => <span class="text-sm text-base-content/70">{formatDateTime(r.created_at)}</span>,
    },
  ];

  type PrizeRow = Prize & { idx: number };
  const prizeRows = () => config().prizes.map((p, idx): PrizeRow => ({ ...p, idx }));

  const prizeColumns: Column<PrizeRow>[] = [
    { key: 'name', title: '奖品', render: (r) => <span class="font-medium">{r.name}</span> },
    { key: 'weight', title: '权重', render: (r) => <span>{r.weight}</span> },
    { key: 'points', title: '积分', render: (r) => <span>{r.points}</span> },
    {
      key: 'image',
      title: '图片',
      render: (r) => (
        <Show when={r.image}>
          <img src={r.image} alt="" class="h-8 w-8 rounded object-cover" />
        </Show>
      ),
    },
  ];

  return (
    <div class="space-y-4">
      <div>
        <h2 class="text-xl font-semibold">大转盘抽奖</h2>
        <p class="text-sm text-base-content/60">奖品配置、模拟抽奖与中奖记录</p>
      </div>

      <AccountRequiredBanner />

      <Tabs tabs={[...TABS]} active={activeTab()} onChange={setActiveTab} />

      <Show when={activeTab() === '基础设置'}>
        <AdminCrudPage title="基础设置" description="设置每次抽奖消耗的积分与每日次数限制">
          <div class="max-w-md space-y-4">
            <FormField label="每次消耗积分">
              <input
                type="number"
                class="input input-bordered input-sm w-full"
                min={0}
                value={config().cost}
                onInput={(e) => {
                  const { value, error } = clampNonNegativeNumber(e.currentTarget.value);
                  setCostError(error);
                  setConfig((prev) => ({ ...prev, cost: value }));
                }}
              />
              <Show when={costError()}>
                <p class="mt-1 text-xs text-error">{costError()}</p>
              </Show>
            </FormField>
            <FormField label="每日次数限制">
              <input
                type="number"
                class="input input-bordered input-sm w-full"
                min={0}
                value={config().daily_limit}
                onInput={(e) => {
                  const { value, error } = clampNonNegativeNumber(e.currentTarget.value);
                  setDailyLimitError(error);
                  setConfig((prev) => ({ ...prev, daily_limit: value }));
                }}
              />
              <Show when={dailyLimitError()}>
                <p class="mt-1 text-xs text-error">{dailyLimitError()}</p>
              </Show>
            </FormField>
            <div class="flex justify-end">
              <button
                type="button"
                class="btn btn-primary btn-sm"
                onClick={() => void saveConfig()}
                disabled={saving()}
              >
                <Show when={saving()}>
                  <span class="loading loading-spinner loading-xs" />
                </Show>
                {saving() ? '保存中…' : '保存配置'}
              </button>
            </div>
          </div>
        </AdminCrudPage>
      </Show>

      <Show when={activeTab() === '奖品管理'}>
        <AdminCrudPage
          title="奖品管理"
          description="配置奖项、权重与积分"
          onCreate={openCreatePrize}
          createLabel="新增奖品"
        >
          <DataTable
            columns={prizeColumns}
            rows={prizeRows()}
            rowKey={(r) => r.idx}
            total={prizeRows().length}
            page={1}
            totalPages={1}
            loading={false}
            error={null}
            emptyText="暂无奖品"
            onPageChange={() => {}}
            actions={(r) => (
              <div class="flex justify-end gap-1">
                <button
                  type="button"
                  class="btn btn-ghost btn-xs"
                  onClick={() => openEditPrize(r, r.idx)}
                >
                  编辑
                </button>
                <button
                  type="button"
                  class="btn btn-ghost btn-xs text-error"
                  onClick={() => void onDeletePrize(r.idx)}
                >
                  删除
                </button>
              </div>
            )}
          />
          <div class="mt-4 flex justify-end">
            <button
              type="button"
              class="btn btn-primary btn-sm"
              onClick={() => void saveConfig()}
              disabled={saving()}
            >
              <Show when={saving()}>
                <span class="loading loading-spinner loading-xs" />
              </Show>
              {saving() ? '保存中…' : '保存配置'}
            </button>
          </div>
        </AdminCrudPage>
      </Show>

      <Show when={activeTab() === '模拟抽奖'}>
        <AdminCrudPage title="模拟抽奖" description="使用当前已保存的配置进行手动抽奖测试">
          <div class="max-w-md space-y-4">
            <FormField label="粉丝 openid" required>
              <input
                type="text"
                class="input input-bordered input-sm w-full"
                placeholder="粉丝 openid"
                value={openidInput()}
                onInput={(e) => setOpenidInput(e.currentTarget.value)}
              />
            </FormField>
            <div class="flex justify-end">
              <button
                type="button"
                class="btn btn-secondary btn-sm"
                onClick={() => void onDraw()}
                disabled={drawSubmitting()}
              >
                <Show when={drawSubmitting()}>
                  <span class="loading loading-spinner loading-xs" />
                </Show>
                {drawSubmitting() ? '抽奖中…' : '抽奖'}
              </button>
            </div>
            <Show when={lastDraw()}>
              <div class="alert alert-info">{lastDraw()}</div>
            </Show>
            <p class="text-xs text-base-content/60">
              粉丝在公众号发送「抽奖」即可触发；奖品权重随机、可设每日次数限制与积分消耗。
            </p>
          </div>
        </AdminCrudPage>
      </Show>

      <Show when={activeTab() === '中奖记录'}>
        <AdminCrudPage title="中奖记录" description="历史中奖明细">
          <DataTable
            columns={recordColumns}
            rows={paged.items()}
            rowKey={(r) => r.id}
            total={paged.total()}
            page={paged.page()}
            totalPages={paged.totalPages()}
            loading={paged.loading()}
            error={paged.error()}
            emptyText="暂无中奖记录"
            onPageChange={(p) => void paged.reload(p)}
          />
        </AdminCrudPage>
      </Show>

      <FormModal
        open={prizeOpen()}
        title={editingIndex() != null ? '编辑奖品' : '新增奖品'}
        onSubmit={onSavePrize}
        onClose={closePrizeModal}
        submitting={prizeSubmitting()}
        error={prizeError()}
      >
        <FormField label="奖品名称" required>
          <input
            type="text"
            class="input input-bordered input-sm w-full"
            placeholder="例如：10积分"
            value={prizeName()}
            onInput={(e) => setPrizeName(e.currentTarget.value)}
            required
          />
        </FormField>
        <FormField label="权重" required>
          <input
            type="number"
            class="input input-bordered input-sm w-full"
            min={0}
            value={prizeWeight()}
            onInput={(e) => setPrizeWeight(Number(e.currentTarget.value))}
            required
          />
        </FormField>
        <FormField label="积分" required>
          <input
            type="number"
            class="input input-bordered input-sm w-full"
            min={0}
            value={prizePoints()}
            onInput={(e) => setPrizePoints(Number(e.currentTarget.value))}
            required
          />
        </FormField>
        <FormField
          label="图片"
          labelExtra={
            <button type="button" class="btn btn-outline btn-xs" onClick={() => setImageOpen(true)}>
              选择图片
            </button>
          }
        >
          <input
            type="text"
            class="input input-bordered input-sm w-full"
            placeholder="图片 URL（可选）"
            value={prizeImage()}
            onInput={(e) => setPrizeImage(e.currentTarget.value)}
          />
        </FormField>
      </FormModal>

      <ImageManager
        open={imageOpen()}
        onClose={() => setImageOpen(false)}
        onSelect={onSelectImage}
        multiple={false}
        max={1}
      />
    </div>
  );
}

export default LuckyDraw;
