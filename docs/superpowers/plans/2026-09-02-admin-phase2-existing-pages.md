# 后台页面重构 · 阶段 2 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 8 个现有后台页面统一改造成「列表/详情 + Modal 表单 + Tabs 分栏」模式，消除内联表单和原生 confirm/alert。

**Architecture：** 基于阶段 1 新增的 `Tabs` 组件和现有 `AdminCrudPage`/`FormModal`/`FormField`/`DataTable`/`useFeedback` 工具，逐个页面重构。本阶段尽量复用现有后端接口，不新增后端路由（除非某页面现有接口确实不支持编辑）。

**Tech Stack：** SolidJS 1.9, Rsbuild, Tailwind CSS v4, daisyUI v5, TypeScript, Axios.

## Global Constraints

- 不更换前端框架或样式库。
- 不修改数据库表结构。
- 新增/编辑表单必须放在 `FormModal` 中；页面主体只显示列表/详情。
- 多列表/多表单页面必须使用 `Tabs` 组件分栏。
- 操作反馈统一用 `useFeedback()`（toast + 确认对话框），禁止 `window.alert` / `window.confirm`。
- 共享组件必须导出到 `web/src/components/index.ts`。
- 每任务完成后运行 `cd web && npm run typecheck`。
- 在 `admin-phase2` 分支上工作。

---

## Task 1: `/modules` 页面重构

**Files:**
- Modify: `web/src/pages/Modules.tsx`
- Modify: `web/src/api/module/query.ts`（如需要，确认/增加 config API 调用）
- Modify: `web/src/api/module/types.ts`（如需要）

**Interfaces:**
- Consumes: `Tabs`, `AdminCrudPage`, `DataTable`, `FormModal`, `FormField`, `SearchBar`, `useFeedback`, `usePaged`, `useAccountId`。
- Produces: 页面改为 tabs + modal；新增/编辑模块复用同一个 `ModuleFormModal`（或行内）；配置弹窗调用 `GET/PUT /accounts/{id}/modules/{module}/config`。

- [ ] **Step 1: 拆分 Tabs**
  - 定义 `const TABS = ['模块列表', '账号绑定', '模块配置'] as const`。
  - 用 `<Tabs tabs={[...TABS]} active={tab()} onChange={setTab} />` 替换现有两栏布局。

- [ ] **Step 2: 模块列表 Tab**
  - 仅保留 `DataTable` + 搜索 + 新增按钮。
  - 把顶部注册表单移到 `FormModal`。
  - 表格 actions 列保留（或新增）编辑：点击打开 modal 预填 name/title/version/status；name 在编辑时只读（后端按 name upsert）。

- [ ] **Step 3: 账号绑定 Tab**
  - 用 `DataTable` 展示当前账号已绑定模块。
  - 绑定操作放入 modal：选择模块、设置 status。
  - 解绑用 `useFeedback().runAction({ confirm, action })` 确认。

- [ ] **Step 4: 模块配置 Tab**
  - 列表展示当前账号已绑定模块。
  - 每行「配置」按钮打开 `FormModal`，加载 `GET /accounts/{id}/modules/{module}/config`，编辑 JSON 后 `PUT` 保存。

- [ ] **Step 5: 类型检查 + 手动验证**
  Run: `cd web && npm run typecheck`
  Verify: http://localhost:3001/modules 三个 tab 切换正常，modal 能打开/保存。

---

## Task 2: `/cloud` 页面重构

**Files:**
- Modify: `web/src/pages/Cloud.tsx`
- Modify: `web/src/api/cloud/types.ts`（如需要补全字段）

**Interfaces:**
- Consumes: `Tabs`, `AdminCrudPage`, `DataTable`, `FormModal`, `FormField`, `SearchBar`, `useFeedback`, `usePaged`, `useAccountId`。
- Produces: tabs + modal 化授权码/市场包操作。

- [ ] **Step 1: 拆分 Tabs**
  - 定义 `const TABS = ['授权码管理', '应用市场'] as const`。

- [ ] **Step 2: 授权码 Tab**
  - 列表：`DataTable` 展示授权码。
  - 新增授权码：modal 输入有效天数。
  - 撤销：用 `useFeedback().runAction()` 确认。
  - 校验授权码：保留行内快速校验或放入小 modal。

- [ ] **Step 3: 应用市场 Tab**
  - 列表：`DataTable` 展示市场包。
  - 发布市场包：modal 输入 name/title/version/download_url/description（当前 description 被写死成 title，需补字段）。
  - 安装：确认对话框。

- [ ] **Step 4: 类型检查 + 手动验证**
  Run: `cd web && npm run typecheck`
  Verify: http://localhost:3001/cloud tab 切换正常，modal 提交后列表刷新。

---

## Task 3: `/payments` 页面重构

**Files:**
- Modify: `web/src/pages/Payments.tsx`

**Interfaces:**
- Consumes: `Tabs`（已替换）、`FormModal`、`FormField`、`useFeedback`、`usePaged`、`useAccountId`。
- Produces: 把充值/提现内联表单移入 modal；tab 状态不共享表单值。

- [ ] **Step 1: 充值 Modal**
  - 新建 `RechargeModal`（或直接用 `FormModal`）：字段 fan_id、amount。
  - 打开时重置表单，提交后刷新钱包余额和订单列表。

- [ ] **Step 2: 提现 Modal**
  - 新建 `WithdrawModal`：字段 fan_id、amount。
  - 与充值 modal 独立状态，避免 tab 切换残留值。

- [ ] **Step 3: 页面主体只保留列表**
  - 移除两个内联 `<form>`。
  - 每个 tab 的 `AdminCrudPage` 或标题区放「新增充值」/「新增提现」按钮。

- [ ] **Step 4: 状态映射优化**
  - 把 withdraw status 和后端原始字符串映射成中文 badge。
  - 充值状态也补全映射。

- [ ] **Step 5: 类型检查 + 手动验证**
  Run: `cd web && npm run typecheck`
  Verify: http://localhost:3001/payments tab 切换、modal 提交、列表刷新正常。

---

## Task 4: `/rules` 页面重构

**Files:**
- Modify: `web/src/pages/Rules.tsx`
- Modify: `web/src/api/rule/types.ts`（如需要补 `news_pic_url` 等字段）

**Interfaces:**
- Consumes: `Tabs`, `AdminCrudPage`, `DataTable`, `FormModal`, `FormField`, `SearchBar`, `useFeedback`, `usePaged`, `useAccountId`。
- Produces: rule 新增/编辑 modal；rule 配置 modal 内 tabs（关键词/回复）。

- [ ] **Step 1: Rule 列表 + 新增/编辑 Modal**
  - 用 `AdminCrudPage` 包列表。
  - 新增/编辑共用 `RuleFormModal`：字段 name、status。
  - 表格 actions：编辑、配置、删除。

- [ ] **Step 2: 配置 Modal（内嵌 Tabs）**
  - Modal 内 tabs：`['关键词', '回复']`。
  - 关键词 tab：列表 + 输入框 + match 选择 + 添加按钮。
  - 回复 tab：列表 + 回复类型选择 + 内容输入；news 类型显示 title/description/url/pic_url，pic_url 用 `ImageManager`。

- [ ] **Step 3: 替换原生 confirm/alert**
  - 删除用 `useFeedback().runAction()`。
  - 错误用 modal 内 `error` 或 toast。

- [ ] **Step 4: 类型检查 + 手动验证**
  Run: `cd web && npm run typecheck`
  Verify: http://localhost:3001/rules 创建规则、添加关键词/回复、删除正常。

---

## Task 5: `/logs` 页面重构

**Files:**
- Modify: `web/src/pages/Logs.tsx`

**Interfaces:**
- Consumes: `AdminCrudPage`, `DataTable`, `BaseModal`/`FormModal`, `useFeedback`, `usePaged`, `useAccountId`。
- Produces: 列表 + 详情 modal；可选手动客服消息 tab。

- [ ] **Step 1: 页面外壳**
  - 用 `AdminCrudPage` 替换手写 header。
  - 增加刷新按钮、搜索槽。

- [ ] **Step 2: 详情 Modal**
  - 行操作「详情」打开 modal，展示完整 `content` / `reply_content` / 时间等字段（不再截断）。

- [ ] **Step 3: 可选 Tab**
  - 若后端有发送客服消息接口，可增加「手动客服消息」tab，提供 openid + 内容输入。
  - 如后端接口不存在，本步骤可跳过，只完成详情 modal。

- [ ] **Step 4: 类型检查 + 手动验证**
  Run: `cd web && npm run typecheck`
  Verify: http://localhost:3001/logs 列表加载、详情 modal 展示完整内容。

---

## Task 6: `/materials` 页面优化

**Files:**
- Modify: `web/src/pages/Materials.tsx`
- Modify: `web/src/api/material/query.ts`（如需要补 update file）

**Interfaces:**
- Consumes: 已有 tabs/modal 模式，`RichEditor`（阶段 1 已修）。
- Produces: 文件编辑 modal、同步素材按钮、移除无用 `success()` 信号。

- [ ] **Step 1: 移除 dead `success()` 信号**
  - 删除 `success()` 信号和对应 alert，统一用 `useFeedback().toast()`。

- [ ] **Step 2: 文件编辑**
  - 若后端有 `PUT /materials/files/{id}`，则加编辑 modal；否则仅优化现有 create/delete UI。

- [ ] **Step 3: 同步/上传素材按钮**
  - 在图文素材 tab 顶部增加「同步图文」「上传到微信」按钮（调用已存在但前端未用的后端接口）。
  - 需要确认后端接口可用再实现；如不可用，先加占位或跳过。

- [ ] **Step 4: 类型检查 + 手动验证**
  Run: `cd web && npm run typecheck`
  Verify: http://localhost:3001/materials 富文本可输入、新建/编辑图文正常。

---

## Task 7: `/menu` 页面重构

**Files:**
- Modify: `web/src/pages/Menu.tsx`
- 新增组件（可选）: `web/src/components/MenuButtonFormModal.tsx`

**Interfaces:**
- Consumes: `Tabs`, `AdminCrudPage`, `DataTable`, `FormModal`, `FormField`, `useFeedback`, `useAccountId`。
- Produces: 可视化菜单 builder + Raw JSON tab；单个按钮编辑 modal。

- [ ] **Step 1: 解析菜单 JSON**
  - 把 `menuJson()` 解析为 `buttons: WechatMenuButton[]`，带错误处理。

- [ ] **Step 2: Tabs**
  - 定义 `const TABS = ['菜单列表', '原始 JSON'] as const`。

- [ ] **Step 3: 菜单列表 Tab**
  - 用 `DataTable` 展示一级/二级按钮（扁平化列表，显示层级路径）。
  - 操作：编辑、删除、添加子按钮。
  - 顶部「添加一级按钮」按钮。

- [ ] **Step 4: 按钮 Modal**
  - 字段：name、type（click/view/miniprogram/media_id）、url/key/media_id/appid 等（按 type 动态显示）。
  - 新增/编辑共用同一个 modal。

- [ ] **Step 5: 原始 JSON Tab**
  - 保留 textarea，实时同步列表 tab 的改动。

- [ ] **Step 6: 替换本地 alert**
  - 用 `useFeedback().toast()` / `runAction()`。

- [ ] **Step 7: 类型检查 + 手动验证**
  Run: `cd web && npm run typecheck`
  Verify: http://localhost:3001/menu 可视化增删改按钮、保存、Raw JSON 同步正常。

---

## Task 8: `/lucky-draw` 页面重构

**Files:**
- Modify: `web/src/pages/LuckyDraw.tsx`
- 新增组件（可选）: `web/src/components/LuckyDrawPrizeModal.tsx`

**Interfaces:**
- Consumes: `Tabs`, `AdminCrudPage`, `DataTable`, `FormModal`, `FormField`, `useFeedback`, `usePaged`, `useAccountId`。
- Produces: tabs + prize modal；配置 JSON 本地解析编辑后整体保存。

- [ ] **Step 1: Tabs**
  - 定义 `const TABS = ['基础设置', '奖品管理', '模拟抽奖', '中奖记录'] as const`。

- [ ] **Step 2: 基础设置 Tab**
  - 放置 cost、daily_limit 编辑表单（可保留简单表单或放入 modal）。
  - 保存时把整个 config JSON 发 `PUT`。

- [ ] **Step 3: 奖品管理 Tab**
  - 解析 config 中的 prizes 数组，用 `DataTable` 展示。
  - 新增/编辑奖品 modal：name、weight、points、可选图片（`ImageManager`）。
  - 删除奖品用确认对话框。
  - 改动后先更新本地 config，保存时再整体提交。

- [ ] **Step 4: 模拟抽奖 Tab**
  - 把现有手动抽奖表单移入此 tab，使用当前已保存的配置（不是编辑器里的未保存草稿）。

- [ ] **Step 5: 中奖记录 Tab**
  - 保留现有记录列表。

- [ ] **Step 6: 类型检查 + 手动验证**
  Run: `cd web && npm run typecheck`
  Verify: http://localhost:3001/lucky-draw tabs 切换正常，奖品增删改后保存正常。

---

## Task 9: 阶段 2 集成验证

**Files:** 所有阶段 2 修改过的文件。

- [ ] **Step 1: 全量类型检查**
  Run: `cd web && npm run typecheck`
  Expected: 无错误。

- [ ] **Step 2: 生产构建验证**
  Run: `cd web && npm run build`
  Expected: 构建成功。

- [ ] **Step 3: 关键页面手动回归**

| 页面 | 检查项 |
|---|---|
| /modules | tabs + modal + 配置 |
| /cloud | tabs + 授权码/市场 modal |
| /payments | tabs + 充值/提现 modal |
| /rules | rule modal + 配置 modal 内 tabs |
| /logs | 详情 modal |
| /materials | 图文/文件 tabs、富文本正常 |
| /menu | 菜单 builder + Raw JSON tab |
| /lucky-draw | tabs + 奖品 modal |

- [ ] **Step 4: 后端测试**
  Run: `zig build test`
  Expected: 与阶段 1 相同，仅既有 file_store 签名失败（本阶段不新增后端路由）。

---

## Spec Coverage Self-Review

| 设计文档要求 | 对应任务 |
|---|---|
| Modules modal + tabs | Task 1 |
| Cloud modal + tabs | Task 2 |
| Payments modal 化 | Task 3 |
| Rules modal + tabs | Task 4 |
| Logs 详情 modal | Task 5 |
| Materials 完善 | Task 6 |
| Menu builder + tabs | Task 7 |
| LuckyDraw tabs + prize modal | Task 8 |
| 阶段集成验证 | Task 9 |

无 TBD/TODO 占位。
