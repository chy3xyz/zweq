import { Show } from 'solid-js';

import { useAccountId } from '#ui/hooks/useAccountId';

function AccountRequiredBanner() {
  const { ready } = useAccountId();

  return (
    <Show when={!ready()}>
      <div class="alert alert-warning mb-4 py-2 text-sm">请先在右上角选择当前公众号</div>
    </Show>
  );
}

export default AccountRequiredBanner;
