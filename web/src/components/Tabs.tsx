import { For } from 'solid-js';

interface Props<T extends string> {
  tabs: T[];
  active: T;
  onChange: (tab: T) => void;
  class?: string;
}

export default function Tabs<T extends string>(props: Props<T>) {
  return (
    <div role="tablist" class={`tabs tabs-box ${props.class ?? ''}`}>
      <For each={props.tabs}>
        {(item) => (
          <button
            type="button"
            role="tab"
            class="tab"
            classList={{ 'tab-active': props.active === item }}
            onClick={() => props.onChange(item)}
          >
            {item}
          </button>
        )}
      </For>
    </div>
  );
}
