import { For, Match, Switch, createSignal } from 'solid-js';

export type SearchValues = Record<string, string>;

export interface SearchOption {
  value: string | number;
  label: string;
}

interface Base {
  key: string;
  label: string;
  width?: string;
}

export type SearchField =
  | (Base & { kind: 'text'; placeholder?: string; inputType?: 'text' | 'search' })
  | (Base & { kind: 'number'; placeholder?: string; min?: number })
  | (Base & { kind: 'select'; options: SearchOption[] })
  | (Base & { kind: 'date' })
  | (Base & { kind: 'daterange' });

interface Props {
  fields: SearchField[];
  /** Initial draft values. */
  values?: SearchValues;
  loading?: boolean;
  onSearch: (values: SearchValues) => void;
  /** Fired after 重置 clears the draft (a search with empty values follows). */
  onReset?: () => void;
}

const DEFAULT_WIDTH: Record<SearchField['kind'], string> = {
  text: 'w-48',
  number: 'w-32',
  select: 'w-36',
  date: 'w-40',
  daterange: 'w-80',
};

/**
 * Standard admin filter bar (Element UI `el-form :inline` equivalent):
 * declarative fields + 查询 / 重置. Values stay a local draft and are only
 * published on 查询, so typing never triggers a request.
 */
export default function SearchBar(props: Props) {
  const [draft, setDraft] = createSignal<SearchValues>({ ...(props.values ?? {}) });

  const set = (key: string, value: string) => setDraft((prev) => ({ ...prev, [key]: value }));

  const onSubmit = (e: SubmitEvent) => {
    e.preventDefault();
    props.onSearch(draft());
  };

  const onReset = () => {
    setDraft({});
    props.onReset?.();
    props.onSearch({});
  };

  return (
    <form onSubmit={onSubmit} class="flex flex-wrap items-end gap-x-3 gap-y-2">
      <For each={props.fields}>
        {(field) => (
          <label class={`form-control ${field.width ?? DEFAULT_WIDTH[field.kind]}`}>
            <span class="label-text mb-1 text-xs">{field.label}</span>
            <Switch>
              <Match when={field.kind === 'select'}>
                <select
                  class="select select-bordered select-sm"
                  value={draft()[field.key] ?? ''}
                  onChange={(e) => set(field.key, e.currentTarget.value)}
                >
                  <For each={field.kind === 'select' ? field.options : []}>
                    {(opt) => <option value={opt.value}>{opt.label}</option>}
                  </For>
                </select>
              </Match>

              <Match when={field.kind === 'daterange'}>
                <div class="flex items-center gap-1">
                  <input
                    type="date"
                    class="input input-bordered input-sm w-full"
                    value={draft()[`${field.key}_start`] ?? ''}
                    onInput={(e) => set(`${field.key}_start`, e.currentTarget.value)}
                  />
                  <span class="text-base-content/50">-</span>
                  <input
                    type="date"
                    class="input input-bordered input-sm w-full"
                    value={draft()[`${field.key}_end`] ?? ''}
                    onInput={(e) => set(`${field.key}_end`, e.currentTarget.value)}
                  />
                </div>
              </Match>

              <Match when={field.kind === 'date' || field.kind === 'number' || field.kind === 'text'}>
                <input
                  class="input input-bordered input-sm w-full"
                  type={inputType(field)}
                  placeholder={placeholderOf(field)}
                  min={field.kind === 'number' ? field.min : undefined}
                  value={draft()[field.key] ?? ''}
                  onInput={(e) => set(field.key, e.currentTarget.value)}
                />
              </Match>
            </Switch>
          </label>
        )}
      </For>

      <div class="flex items-center gap-2">
        <button type="submit" class="btn btn-primary btn-sm" disabled={props.loading}>
          <span classList={{ 'loading loading-spinner loading-xs mr-1': !!props.loading }} />
          查询
        </button>
        <button type="button" class="btn btn-ghost btn-sm" onClick={onReset} disabled={props.loading}>
          重置
        </button>
      </div>
    </form>
  );
}

function inputType(field: SearchField): string {
  switch (field.kind) {
    case 'number':
      return 'number';
    case 'date':
      return 'date';
    case 'text':
      return field.inputType ?? 'text';
    default:
      return 'text';
  }
}

function placeholderOf(field: SearchField): string | undefined {
  return field.kind === 'text' || field.kind === 'number' ? field.placeholder : undefined;
}
