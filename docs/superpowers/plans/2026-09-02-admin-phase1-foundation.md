# 后台页面重构 · 阶段 1 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完成基础设施与紧急 bug 修复：抽离 `Tabs` 组件、修复 `RichEditor` 无法输入、修复 `Menu` 接口契约、修复 `ShopOrders` 脆弱 URL、补齐 404 页面。

**Architecture:** 基于现有 SolidJS + Tailwind v4 + daisyUI 栈，新增共享 `Tabs.tsx`，修补编辑器事件处理，修正 Menu 前后端请求/响应格式，新增 `SHOP_PATH.adminOrders` 常量，升级 `NotFound.tsx`。

**Tech Stack:** SolidJS 1.9, Rsbuild, Tailwind CSS v4, daisyUI v5, TypeScript, Axios.

## Global Constraints

- 不更换前端框架或样式库。
- 不修改数据库表结构。
- 所有金额/折扣字段保持现有整数存储语义。
- 每任务完成后运行 `npm run typecheck`。
- 共享组件必须导出到 `web/src/components/index.ts`。

---

## Task 1: 新增共享 `Tabs` 组件

**Files:**
- Create: `web/src/components/Tabs.tsx`
- Modify: `web/src/components/index.ts`
- Test: 手动在 `Payments.tsx` 替换手写 tabs 验证

**Interfaces:**
- Consumes: 无。
- Produces: `Tabs<T extends string>(props: { tabs: T[]; active: T; onChange: (tab: T) => void; class?: string }) => JSX.Element`。

- [ ] **Step 1: 创建 `Tabs.tsx`**

```tsx
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
```

- [ ] **Step 2: 导出到组件 barrel**

在 `web/src/components/index.ts` 追加：

```ts
export { default as Tabs } from './Tabs';
```

- [ ] **Step 3: 在 `Payments.tsx` 试用并验证**

将 `Payments.tsx:132-146` 的手写 tablist 替换为：

```tsx
import { Tabs } from '#ui/components';

<Tabs tabs={[...TABS]} active={tab()} onChange={setTab} />
```

- [ ] **Step 4: 运行类型检查**

Run: `cd web && npm run typecheck`
Expected: 无错误。

- [ ] **Step 5: 验证 UI**

Run: 已启动的 dev server http://localhost:3001/payments
Expected: tab 切换正常，样式与之前一致。

---

## Task 2: 修复 `RichEditor` 无法输入

**Files:**
- Modify: `web/src/components/RichEditor.tsx`
- Test: 手动在 http://localhost:3001/materials 新建图文，正文可打字

**Interfaces:**
- Consumes: 无。
- Produces: 修复后的 `RichEditor` 组件，props 不变。

- [ ] **Step 1: 复现问题**

Run: 打开 http://localhost:3001/materials → 新建图文 → 点击富文本区域 → 尝试输入中文/英文。
Expected: 当前无法输入（光标可能出现但内容不变）。

- [ ] **Step 2: 修复 `contentEditable` 与 Solid 信号的冲突**

当前 `createEffect` 在每次 `props.value` 变化时设置 `ref.innerHTML`，可能覆盖用户正在输入的 DOM。需要改为仅在组件挂载和 `props.value` 与当前 DOM 不一致且不是由当前组件自己触发时同步。

修改 `RichEditor.tsx`：

1. 移除 `onMount` 中的 `ref.innerHTML = props.value ?? ''`（合并到 `createEffect`）。
2. `createEffect` 中增加 `isTyping` 标志，当 `onInput`/`onBlur` 触发时设置为 true，避免 effect 回写。
3. 或者更简单地，在 effect 中比较 `props.value` 与 `ref.innerHTML`，仅在两者不同且不是由最近一次 `emit()` 产生时设置。

推荐实现（最小改动）：

```tsx
export default function RichEditor(props: Props) {
  let ref: HTMLDivElement | undefined;
  const [pickerOpen, setPickerOpen] = createSignal(false);
  const [lastHtml, setLastHtml] = createSignal(props.value ?? '');

  createEffect(() => {
    const v = props.value ?? '';
    if (ref && v !== ref.innerHTML && v !== lastHtml()) {
      ref.innerHTML = v;
      setLastHtml(v);
    }
  });

  const emit = () => {
    if (!ref) return;
    const html = ref.innerHTML;
    setLastHtml(html);
    props.onInput(html);
  };
  // ...其余不变
}
```

并确保 `contentEditable` 元素有正确的 `white-space: pre-wrap` 和 `user-select: text`。

- [ ] **Step 3: 运行类型检查**

Run: `cd web && npm run typecheck`
Expected: 无错误。

- [ ] **Step 4: 手动验证输入**

Run: http://localhost:3001/materials
Expected: 新建图文时，富文本编辑器可正常输入中文、英文、粘贴内容，工具栏按钮生效。

---

## Task 3: 修复 `Menu` 保存/拉取接口契约

**Files:**
- Modify: `web/src/pages/Menu.tsx`
- Modify: `web/src/api/menu/types.ts`
- Modify: `web/src/api/menu/query.ts`
- Modify: `src/modules/menu/api.zig`（fetch 响应包 envelope）
- Test: 手动在 http://localhost:3001/menu 保存、拉取菜单

**Interfaces:**
- Consumes: `MENU_PATH`, `SaveMenuRequest`, `WechatMenu`。
- Produces: 前端发送 `{ menu_json: string }`；后端 `fetchMenu` 返回 `{ code, msg, data: { menu_json: string } }`。

- [ ] **Step 1: 确认后端 `save` 契约**

Backend `src/modules/menu/api.zig:12-14` 已期望：

```zig
const SaveMenuReq = struct {
    menu_json: []const u8,
};
```

- [ ] **Step 2: 修改前端 `saveMenu` 调用**

在 `web/src/pages/Menu.tsx:35`：

```tsx
await saveMenu(accountId(), { menu_json: menuJson() });
```

同时确认 `web/src/api/menu/types.ts` 的 `SaveMenuRequest` 为：

```ts
export interface SaveMenuRequest {
  menu_json: string;
}
```

- [ ] **Step 3: 修复 `fetchMenu` 响应格式**

后端 `src/modules/menu/api.zig:183` 当前返回原始文本：

```zig
try ctx.text(200, data);
```

改为返回 envelope：

```zig
fn fetchMenu(ctx: *http.Context) !void {
    // ...
    const data = self.svc.fetchMenu(account_id) catch |err| { ... };
    defer ctx.allocator.free(data);
    try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = .{ .menu_json = data } });
}
```

- [ ] **Step 4: 前端 `fetchMenu` 保持 envelope 解析**

`web/src/api/menu/query.ts:25-28` 已经是 envelope 解析，无需改动，但需确认 `WechatMenu` 类型：

```ts
export interface WechatMenu {
  menu_json: string;
}
```

- [ ] **Step 5: 运行后端测试**

Run: `zig build test`
Expected: 全部通过（若 Menu 有测试则重点关注）。

- [ ] **Step 6: 手动验证 Menu 页面**

Run: http://localhost:3001/menu
Expected:
1. 选择一个公众号。
2. 在 textarea 输入合法 JSON 数组 `[{"name":"测试","type":"click","key":"test"}]`。
3. 点击“保存”成功。
4. 点击“从微信拉取”成功（若后端 mock 或微信配置正确）。
5. 无 400 “请求体格式错误”。

---

## Task 4: 修复 `ShopOrders` 脆弱 URL

**Files:**
- Modify: `web/src/api/shop/path.ts`
- Modify: `web/src/api/shop/query.ts`
- Test: 手动访问 http://localhost:3001/shop/orders 确认列表加载

**Interfaces:**
- Consumes: `APP_CONFIG.apiPrefix`。
- Produces: `SHOP_PATH.adminOrders = `${APP_CONFIG.apiPrefix}/shop/admin/orders``；`shopOrdersQuery(accountId, page, pageSize, status, openid)`。

- [ ] **Step 1: 新增 `adminOrders` 路径常量**

在 `web/src/api/shop/path.ts` 中：

```ts
export const SHOP_PATH = {
  categories: `${P}/categories`,
  products: `${P}/products`,
  adminProducts: `${P}/admin/products`,
  adminOrders: `${P}/admin/orders`,
  product: (id: number) => `${P}/products/${id}`,
} as const;
```

- [ ] **Step 2: 新增 `shopOrdersQuery` URL 构建函数**

在 `web/src/api/shop/path.ts` 中追加：

```ts
export const shopOrdersQuery = (
  accountId: number,
  page: number,
  pageSize: number,
  status = -1,
  openid = '',
) => {
  const params = new URLSearchParams({
    account_id: String(accountId),
    page: String(page),
    page_size: String(pageSize),
    status: String(status),
  });
  if (openid) params.set('openid', openid);
  return `${SHOP_PATH.adminOrders}?${params.toString()}`;
};
```

- [ ] **Step 3: 替换 `listShopOrders` 中的脆弱 URL**

在 `web/src/api/shop/query.ts:93-111`：

```ts
export async function listShopOrders(
  accountId: number,
  page: number,
  pageSize: number,
  status = -1,
  openid = '',
): Promise<ShopOrderListResult> {
  const { data } = await http.get<{ code: number; msg: string; data: ShopOrderListResult }>(
    shopOrdersQuery(accountId, page, pageSize, status, openid),
  );
  return unwrapEnvelope(data);
}
```

- [ ] **Step 4: 运行类型检查**

Run: `cd web && npm run typecheck`
Expected: 无错误。

- [ ] **Step 5: 手动验证订单列表**

Run: http://localhost:3001/shop/orders
Expected: 选择一个有订单的公众号后，列表正常加载，分页正常，无 404 请求。

---

## Task 5: 补齐 404 页面

**Files:**
- Modify: `web/src/pages/NotFound.tsx`
- Test: 访问任意不存在路由，如 http://localhost:3001/this-does-not-exist

**Interfaces:**
- Consumes: `ROUTE_PATH.index`, `@solidjs/router` `useNavigate`。
- Produces: 更完整的 404 UI。

- [ ] **Step 1: 升级 `NotFound.tsx`**

```tsx
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
```

- [ ] **Step 2: 运行类型检查**

Run: `cd web && npm run typecheck`
Expected: 无错误。

- [ ] **Step 3: 手动验证 404**

Run: http://localhost:3001/this-does-not-exist
Expected: 显示 404 文案、返回上一页、返回首页按钮均可用。

---

## Task 6: 阶段 1 集成验证

**Files:**
- 所有阶段 1 修改过的文件。

- [ ] **Step 1: 全量类型检查**

Run: `cd web && npm run typecheck`
Expected: 无错误。

- [ ] **Step 2: 生产构建验证**

Run: `cd web && npm run build`
Expected: 构建成功。

- [ ] **Step 3: 后端测试**

Run: `zig build test`
Expected: 全部通过。

- [ ] **Step 4: 关键路径手动回归**

| 页面 | 操作 | 期望 |
|---|---|---|
| /payments | tab 切换 | 正常 |
| /materials | 富文本输入 | 可打字 |
| /menu | 保存 + 拉取 | 无 400/格式错误 |
| /shop/orders | 加载列表 | 正常，URL 正确 |
| /任意不存在路由 | 404 页面 | 正常显示 |

---

## Spec Coverage Self-Review

| 设计文档要求 | 对应任务 |
|---|---|
| 抽出 `Tabs` 组件 | Task 1 |
| 修复 `RichEditor` 无法输入 | Task 2 |
| 修复 `/menu` 保存/拉取接口契约 | Task 3 |
| 修复 `/shop/orders` 接口 URL | Task 4 |
| 补齐 404 页面 | Task 5 |
| 阶段验证 | Task 6 |

无 TBD/TODO 占位；类型和路径名称在各任务中一致。
