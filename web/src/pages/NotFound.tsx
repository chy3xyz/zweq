import { A, useNavigate } from '@solidjs/router';

import { ROUTE_PATH } from '#ui/constants';

function NotFound() {
  const navigate = useNavigate();
  return (
    <div class="flex min-h-screen flex-col items-center justify-center gap-8 bg-base-200 p-6 text-center">
      <div class="space-y-4">
        <p class="text-8xl font-black leading-none tracking-tight text-primary" aria-hidden="true">
          404
        </p>
        <div class="space-y-2">
          <h1 class="text-2xl font-semibold">页面不存在</h1>
          <p class="mx-auto max-w-md text-base-content/60">
            你访问的地址可能已被移除，或者输入有误。可以回到首页，或返回上一页继续浏览。
          </p>
        </div>
      </div>
      <div class="flex flex-wrap justify-center gap-3">
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
