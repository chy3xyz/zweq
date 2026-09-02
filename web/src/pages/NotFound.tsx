import { A, useNavigate } from '@solidjs/router';

import { ROUTE_PATH } from '#ui/constants';

function NotFound() {
  const navigate = useNavigate();
  return (
    <div class="flex min-h-screen flex-col items-center justify-center gap-6 bg-base-200 p-6 text-center">
      <div class="space-y-2">
        <p class="text-8xl font-bold text-base-content/10">404</p>
        <h1 class="text-2xl font-semibold">页面不存在</h1>
        <p class="text-base-content/60">你访问的地址可能已被移除，或者输入有误。</p>
      </div>
      <div class="flex gap-3">
        <button type="button" class="btn btn-ghost" onClick={() => navigate(-1)}>
          返回上一页
        </button>
        <A href={ROUTE_PATH.index} class="btn btn-primary">
          返回首页
        </A>
      </div>
    </div>
  );
}

export default NotFound;
