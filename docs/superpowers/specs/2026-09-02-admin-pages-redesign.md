# 后台管理页面重构设计文档

## 1. 概述

对 Zweq 管理后台（`web/src/pages`）进行全面交互升级：所有新增/编辑表单移入 Modal，多列表/多表单页面使用 Tabs 分隔，补齐 404 页面，并修复当前阻塞性 bug。同时补齐后端缺失的更新/删除接口，让前端 CRUD 完整。

## 2. 目标

- 统一后台交互范式：**列表/详情页 + Modal 表单 + Tabs 分栏**。
- 修复已知运行时 bug：
  - `Materials` 富文本编辑器无法输入。
  - `Menu` 保存/拉取接口请求/响应格式不匹配。
  - `ShopOrders` 接口 URL 依赖字符串替换，脆弱且已报错。
- 补齐 404 页面，提供品牌感与返回入口。
- 为以下页面补齐后端 update/delete/详情接口：coupon、vote、seckill、member-card level、module。

## 3. 非目标

- 不更换前端框架或样式库（保持 SolidJS + Tailwind v4 + daisyUI）。
- 不重构全局状态/路由/鉴权。
- 不改数据库表结构（仅在现有表上补 service/api 方法）。
- 不做营销型视觉 overhaul，保持后台工具感。

## 4. 基础设施（阶段 1）

### 4.1 新增/复用共享组件

- `Tabs.tsx`：基于 daisyUI `tabs tabs-box`，接收 `tabs: string[]`、`active`、`onChange`。
- `RichEditor` 修复：定位无法输入原因（`contentEditable` 与 Solid 信号更新冲突、焦点丢失或事件拦截），保证光标和输入正常。
- `NotFound.tsx` 升级：保持简洁，增加返回首页、返回上一页、联系管理员入口。

### 4.2 紧急 bug 修复

| 页面 | 问题 | 修复方式 |
|---|---|---|
| Materials | RichEditor 无法输入 | 修复编辑器事件/焦点处理 |
| Menu | `saveMenu` 发送 `{ buttons }`，后端期望 `{ menu_json }`；`fetchMenu` 返回原始文本而非 envelope | 前端改发 `{ menu_json }`，或后端/前端统一；`fetchMenu` 特殊处理原始响应 |
| ShopOrders | `listShopOrders` 用 `replace('/products', '/admin/orders')` 拼 URL | 新增 `SHOP_PATH.adminOrders` 常量，直接拼接 |

## 5. 现有页面改造（阶段 2）

统一模式：外壳 `AdminCrudPage` + `DataTable` + `FormModal` + `SearchBar` + `useFeedback`。多列表/多表单用 `Tabs`。

| 页面 | 改造要点 |
|---|---|
| /modules | Tabs：模块列表 / 账号绑定 / 模块配置；Modal 注册/编辑模块；配置 modal 调用 `GET/PUT /accounts/{id}/modules/{module}/config` |
| /cloud | Tabs：授权码管理 / 应用市场；Modal 生成授权码、发布市场包 |
| /payments | Tabs 保留充值/提现；把内联表单移入 Modal |
| /rules | Modal 新增/编辑规则；配置 Modal 内 Tabs：关键词 / 回复；回复支持 news_pic_url（ImageManager） |
| /logs | 列表 + 详情 Modal；可选 Tab：消息日志 / 手动客服消息 |
| /materials | 已是 tabs，补文件编辑、修 RichEditor、加同步素材按钮 |
| /menu | 可视化菜单 builder + Raw JSON tab；用 DataTable 展示一级/二级菜单；Modal 编辑单个按钮 |
| /lucky-draw | Tabs：基础设置 / 奖品管理 / 模拟抽奖 / 中奖记录；奖品 Modal 增删改 |

## 6. 管理页补齐（阶段 3）

### 6.1 前端改造

| 页面 | 改造要点 |
|---|---|
| /coupon | Tabs：优惠券模板 / 领取记录；Modal 新增/编辑模板；补全 `per_user`、`start_at`、`end_at`、`status` 字段 |
| /vote | Tabs：投票列表 / 投票统计；Modal 新建/编辑投票（含 `end_at`）；结果展示 |
| /seckill | Tabs：活动管理 / 抢购记录；Modal 编辑活动；补 `start_at`/`end_at`/`per_user` |
| /member-card | Tabs：会员等级 / 会员列表；等级 Modal 编辑/删除；会员详情 Modal |
| /points | Tabs：积分商品 / 兑换记录；商品 Modal 增加封面图（ImageManager）和详情富文本（RichEditor） |
| /shop/orders | Tabs：订单列表 / 退款审核 / 自提核销；详情 Modal 拉 `GET /shop/orders/{id}` 展示商品清单；发货/核销/退款操作 |

### 6.2 后端接口补齐

| 模块 | 新增接口 | 说明 |
|---|---|---|
| coupon | `GET /coupons/{id}`、`PUT /coupons/{id}` | 单条详情与整体更新 |
| vote | `PUT /votes/{id}`、`DELETE /votes/{id}` | 更新与删除 |
| seckill | `PUT /seckills/{id}`、`DELETE /seckills/{id}` | 更新与删除 |
| member-card | `PUT /member-cards/{id}`、`DELETE /member-cards/{id}` | 等级更新与删除 |
| module | `PUT /modules/{id}` 或统一 upsert | 按 ID 更新模块元数据 |

后端实现遵循现有 service → persistence → api 分层，金额/折扣字段保持“分/千分之一”整数存储。

## 7. 数据流与状态

- 列表状态：继续使用 `usePaged`/`useLocalPaged`。
- Modal 状态：每个 Modal 独立 `open`/`submitting`/`error` 信号，关闭时 reset。
- 账号切换：关闭所有 modal，reset 表单，列表自动 reload（利用 `usePaged` watch）。
- 操作反馈：统一 `useFeedback().toast()` / `useFeedback().runAction({ confirm, action })`。

## 8. 验证计划

每阶段完成后执行：

1. `cd web && npm run typecheck` 无类型错误。
2. `cd web && npm run build` 能成功构建。
3. 手动访问该阶段涉及页面，验证：
   - 列表正常加载、分页正常。
   - 新增/编辑 Modal 能打开、提交、关闭后列表刷新。
   - Tabs 切换不丢状态。
   - 修复点（RichEditor、Menu、ShopOrders）不再报错。
4. 后端：运行 `zig build test`，确保新接口测试通过或至少不破坏现有测试。

## 9. 风险与回滚

- 风险：多页面并行改动可能引入类型或运行时回归。
- 缓解：分阶段实施，每阶段独立验证；使用 AgentSwarm 时，每个页面由独立 agent 负责，但共享组件变更（Tabs/RichEditor）放在阶段 1 先做。
- 回滚：按文件/模块回滚，不破坏未改动页面。

## 10. 排期

- 阶段 1：基础设施 + 紧急 bug（1 轮 swarm）
- 阶段 2：现有页面改造（1 轮 swarm，多页面并行）
- 阶段 3：管理页补齐 + 后端接口（1 轮 swarm 前端 + 1 轮后端）
