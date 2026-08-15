import { For, Show, createSignal } from 'solid-js';

import {
  getConfig,
  listDrawRecords,
  manualDraw,
  setConfig,
  toApiError,
  type DrawRecord,
} from '#ui/api';
import DataTable, { type Column } from '#ui/components/DataTable';
import { useAccounts } from '#ui/hooks/useAccounts';
import { usePaged } from '#ui/hooks/usePaged';
import { formatDateTime } from '#ui/utils';

const PAGE_SIZE = 20;

const DEFAULT_CONFIG = JSON.stringify(
  {
    cost: 0,
    daily_limit: 0,
    prizes: [
      { name: '10积分', weight: 50, points: 10 },
      { name: '50积分', weight: 30, points: 50 },
      { name: '谢谢参与', weight: 20, points: 0 },
    ],
  },
  null,
  2,
);

function LuckyDraw() {
  const accounts = useAccounts();
  const [success, setSuccess] = createSignal<string | null>(null);
  const [error, setError] = createSignal<string | null>(null);
  const [configJson, setConfigJson] = createSignal(DEFAULT_CONFIG);
  const [openidInput, setOpenidInput] = createSignal('');
  const [lastDraw, setLastDraw] = createSignal<string | null>(null);

  const accountId = () => accounts.selected() ?? 0;
  const paged = usePaged<DrawRecord>((page, pageSize) => listDrawRecords(accountId(), page, pageSize), PAGE_SIZE);

  const columns: Column<DrawRecord>[] = [
    { key: 'openid', title: '粉丝', render: (r) => <span class="font-mono text-xs">{r.openid}</span> },
    { key: 'prize_name', title: '奖品', render: (r) => <span class="font-medium">{r.prize_name}</span> },
    { key: 'points', title: '积分', render: (r) => <span>{r.points}</span> },
    {
      key: 'created_at',
      title: '时间',
      render: (r) => <span class="text-sm text-base-content/70">{formatDateTime(r.created_at)}</span>,
    },
  ];

  const onAccountChange = (id: number) => {
    accounts.setSelected(id);
    void paged.reload(1);
    void loadConfig(id);
  };

  const loadConfig = async (id: number) => {
    if (id === 0) return;
    try {
      const cfg = await getConfig(id);
      setConfigJson(cfg && cfg.length > 0 ? cfg : DEFAULT_CONFIG);
    } catch {
      setConfigJson(DEFAULT_CONFIG);
    }
  };

  const onSaveConfig = async () => {
    if (accountId() === 0) return;
    setError(null);
    setSuccess(null);
    try {
      JSON.parse(configJson()); // 校验 JSON
      await setConfig(accountId(), configJson());
      setSuccess('奖品配置已保存');
    } catch {
      setError('配置 JSON 格式错误');
    }
  };

  const onDraw = async () => {
    if (accountId() === 0) return;
    setError(null);
    setLastDraw(null);
    try {
      const result = await manualDraw({ account_id: accountId(), openid: openidInput().trim(), config: configJson() });
      setLastDraw(`抽中「${result.prize_name}」${result.points > 0 ? ` +${result.points} 积分` : ''}`);
      setOpenidInput('');
      void paged.reload(1);
    } catch (err) {
      setError(toApiError(err).message);
    }
  };

  return (
    <div class="p-6 space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">大转盘抽奖</h1>
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

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <div class="card bg-base-200 p-4 space-y-3">
          <h2 class="font-semibold">奖品配置（JSON）</h2>
          <textarea
            class="textarea textarea-bordered font-mono h-48"
            value={configJson()}
            onInput={(e) => setConfigJson(e.currentTarget.value)}
          />
          <button class="btn btn-primary" onClick={() => void onSaveConfig()}>
            保存配置
          </button>
        </div>

        <div class="card bg-base-200 p-4 space-y-3">
          <h2 class="font-semibold">手动抽奖</h2>
          <div class="flex gap-2">
            <input
              class="input input-bordered flex-1"
              placeholder="粉丝 openid"
              value={openidInput()}
              onInput={(e) => setOpenidInput(e.currentTarget.value)}
            />
            <button class="btn btn-secondary" onClick={() => void onDraw()}>
              抽奖
            </button>
          </div>
          <Show when={lastDraw()}>
            <div class="alert alert-info">{lastDraw()}</div>
          </Show>
          <p class="text-xs text-base-content/60">
            粉丝在公众号发送「抽奖」即可触发；奖品权重随机、可设每日次数限制与积分消耗。
          </p>
        </div>
      </div>

      <div class="card bg-base-200 p-4">
        <h2 class="font-semibold mb-3">中奖记录</h2>
        <DataTable
          columns={columns}
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
      </div>
    </div>
  );
}

export default LuckyDraw;
