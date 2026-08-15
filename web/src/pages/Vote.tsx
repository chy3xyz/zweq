import { For, Show, createSignal } from 'solid-js';

import { createVote, getVoteResults, listVotes, toApiError, type VoteItem } from '#ui/api';
import DataTable, { type Column } from '#ui/components/DataTable';
import { useAccounts } from '#ui/hooks/useAccounts';
import { usePaged } from '#ui/hooks/usePaged';
import { formatDateTime } from '#ui/utils';

const PAGE_SIZE = 20;

function Vote() {
  const accounts = useAccounts();
  const [success, setSuccess] = createSignal<string | null>(null);
  const [error, setError] = createSignal<string | null>(null);
  const [title, setTitle] = createSignal('');
  const [optionsText, setOptionsText] = createSignal('');
  const [results, setResults] = createSignal<{ options: string[]; tally: number[] } | null>(null);

  const accountId = () => accounts.selected() ?? 0;
  const paged = usePaged<VoteItem>((page, pageSize) => listVotes(accountId(), page, pageSize), PAGE_SIZE);

  const columns: Column<VoteItem>[] = [
    { key: 'title', title: '题目', render: (r) => <span class="font-medium">{r.title}</span> },
    {
      key: 'options_json',
      title: '选项',
      render: (r) => {
        try {
          return <span class="text-sm text-base-content/70">{(JSON.parse(r.options_json) as string[]).join(' / ')}</span>;
        } catch {
          return <span>-</span>;
        }
      },
    },
    {
      key: 'created_at',
      title: '创建时间',
      render: (r) => <span class="text-sm text-base-content/70">{formatDateTime(r.created_at)}</span>,
    },
  ];

  const onAccountChange = (id: number) => {
    accounts.setSelected(id);
    setResults(null);
    void paged.reload(1);
  };

  const onCreate = async (e: SubmitEvent) => {
    e.preventDefault();
    if (accountId() === 0) return;
    setError(null);
    setSuccess(null);
    const options = optionsText()
      .split(/[\n,，]/)
      .map((s) => s.trim())
      .filter((s) => s.length > 0);
    if (options.length < 2) {
      setError('至少两个选项（逗号或换行分隔）');
      return;
    }
    try {
      await createVote({ account_id: accountId(), title: title().trim(), options });
      setTitle('');
      setOptionsText('');
      setSuccess('投票已创建');
      void paged.reload(1);
    } catch (err) {
      setError(toApiError(err).message);
    }
  };

  const onShowResults = async (row: VoteItem) => {
    try {
      const tally = await getVoteResults(row.id);
      const options = JSON.parse(row.options_json) as string[];
      setResults({ options, tally });
    } catch (err) {
      setError(toApiError(err).message);
    }
  };

  return (
    <div class="p-6 space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">投票</h1>
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

      <form onSubmit={onCreate} class="card bg-base-200 p-4 space-y-3">
        <h2 class="font-semibold">新建投票</h2>
        <input
          class="input input-bordered"
          placeholder="题目"
          value={title()}
          onInput={(e) => setTitle(e.currentTarget.value)}
        />
        <textarea
          class="textarea textarea-bordered h-24"
          placeholder="选项（逗号或换行分隔）"
          value={optionsText()}
          onInput={(e) => setOptionsText(e.currentTarget.value)}
        />
        <button class="btn btn-primary" type="submit">
          创建
        </button>
      </form>

      <DataTable
        columns={columns}
        rows={paged.items()}
        rowKey={(r) => r.id}
        total={paged.total()}
        page={paged.page()}
        totalPages={paged.totalPages()}
        loading={paged.loading()}
        error={paged.error()}
        emptyText="暂无投票"
        onPageChange={(p) => void paged.reload(p)}
        actions={(row) => (
          <button class="btn btn-xs btn-outline btn-primary" onClick={() => void onShowResults(row)}>
            查看结果
          </button>
        )}
      />

      <Show when={results()}>
        {(r) => (
          <div class="card bg-base-200 p-4">
            <h2 class="font-semibold mb-3">计票结果</h2>
            <For each={r().options}>
              {(opt, i) => (
                <div class="flex justify-between py-1 border-b border-base-300 last:border-0">
                  <span>{opt}</span>
                  <span class="font-semibold">{r().tally[i()] ?? 0} 票</span>
                </div>
              )}
            </For>
          </div>
        )}
      </Show>
    </div>
  );
}

export default Vote;
