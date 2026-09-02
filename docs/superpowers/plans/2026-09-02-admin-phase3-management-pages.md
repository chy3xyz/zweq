# Admin Phase 3 — Management Pages + Backend CRUD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 补齐 coupon / vote / seckill / member-card / points / shop-orders / module 七个后台功能的「列表 + Modal 新增/编辑/删除 + Tabs」管理范式，并同步补齐后端缺失的 update/delete/detail 接口与积分商品图片/详情字段。

**Architecture:** 后端按现有 `src/modules/<feature>/` 分层（model.zig → persistence.zig → service.zig → api.zig / api_dto.zig）补接口；积分商品加 `image`/`detail` 两列（zent 启动时自动 migrate）。前端按阶段 1/2 已确立的范式（`AdminCrudPage` + `DataTable` + `FormModal` + `Tabs` + `SearchBar` + `useFeedback`）改造页面，字段统一用 `FormField` 包裹。

**Tech Stack:** Zig + zent schema-as-code（SQLite/Postgres），SolidJS + Tailwind v4 + daisyUI，TypeScript。

**范围依据:** `docs/superpowers/specs/2026-09-02-admin-pages-redesign.md` 第 6 节 + 用户直接要求（/points 商品要图片与详情介绍、/shop/orders 修复接口错误）。与 spec 的两处偏差在下方 Global Constraints 中说明。

## Global Constraints

- 分支 `admin-phase2`。仓库当前有 **2 个未提交的既有改动**（`web/src/components/index.ts`、`web/src/pages/Materials.tsx`，阶段 2 终审修复产物）与 2 个无关 untracked 的 miniprogram 文档 —— **一律不动、不纳入提交**。
- 金额、折扣沿用“分 / 千分之一”整数存储：coupon 金额、seckill 价格用分（FE `yuanToFen`/`fenToYuan`）；member-card `discount` 千分比、`points_ratio` ×100。
- 时间字段 `start_at`/`end_at` 为 epoch 秒（Int）。FE 用 `datetime-local` 输入 ↔ epoch 秒互转，页面内联 helper（`toLocalInput(sec)` / `parseLocalInput(str)`），不新增全局 util。
- 后端新增接口遵循既有 meta 权限（coupon/seckill/member-card/vote/module 模块沿用同文件其他 route spec 的 `.meta.permission` 写法；coupon 读 `coupon:read`、写 `coupon:write`，类推）。
- 每个后端任务结束跑 `zig build`（必须编译通过）；允许 `zig build test` 仅存在**已知既有失败**：`file_store.create` 签名不匹配（core_test/platform_test），与本阶段无关，不得“顺手”修改 file_store。
- 后端接口必须在对应 FE 任务之前合入（先后端后前端）。
- 提交信息沿用既有约定（`feat(admin): ...` / `fix(...): ...` / `feat(<module>): ...`），每个任务独立 commit。
- **偏差 1（schema）：** spec“非目标：不改表结构”在 /points 上被用户要求覆盖 —— `PointsProduct` 增加 `image`、`detail` 两列（zent `migrateSchema` 启动自动加列，无需手写 SQL）。仅此一处 schema 变更。
- **偏差 2（/shop/orders 分栏）：** spec 6.1 的「退款审核」tab 与既有 `/shop/admin`（ShopAdmin.tsx 退款审核 tab）重复，且退款/发货/核销接口 meta 为 `shop:write`，而 `/shop/orders` 路由 gate 为 `shop:read`。故 /shop/orders 只做**订单中心**（列表 + 发货 + 自提核销 + 详情 Modal 拉取商品清单），退款审核留在 /shop/admin 不重复建设。

---

## File Structure

### 后端（Zig，`src/modules/<feature>/`）

| 文件 | 动作 | 职责 |
|---|---|---|
| `coupon/{persistence,service,api}.zig` | Modify | `getCouponById`、`updateCoupon`；`GET/PUT /coupons/{id}` |
| `vote/{persistence,service,api}.zig` | Modify | `updateVote`、`deleteVote`（连同投票记录删除）；`PUT/DELETE /votes/{id}` |
| `seckill/{persistence,service,api}.zig` | Modify | `updateActivity`、`deleteActivity`（连同订单）；`GET/PUT/DELETE /seckills/{id}`；orders 列表补活动标题 |
| `member_card/{persistence,service,api}.zig` | Modify | `updateLevel`、`deleteLevel`（有会员引用则拒绝）；`PUT/DELETE /member-cards/{id}` |
| `module/{persistence,service,api}.zig` | Modify | `updateModuleById`（PUT 语义）；`PUT /modules/{id}` |
| `points/{model,persistence,service,api}.zig` | Modify | `PointsProduct.image/detail`；orders row 携带 `created_at` |
| `shop/{trade_store,service,api,api_dto}.zig` | Modify | `OrderDto` 补 pickup 字段；`adminOrders` 支持 `pickup_type` 过滤 |
| `schema.zig` | - | 不动（各模块 graph 已挂载） |
| `main.zig` | - | 不动（路由已 mount） |

### 前端（`web/src/`）

| 文件 | 动作 | 职责 |
|---|---|---|
| `pages/Coupon.tsx` | Rewrite | Tabs：优惠券模板 / 领取记录；Modal 新增/编辑（含 per_user/start_at/end_at/status）；发券/核销保留 |
| `pages/Vote.tsx` | Rewrite | Tabs：投票活动 / 投票统计；Modal 新增/编辑（含 end_at）+ 删除；统计详情 Modal |
| `pages/Seckill.tsx` | Rewrite | Tabs：活动管理 / 抢购记录；Modal 新增/编辑（含 start_at/end_at/per_user）+ 删除 |
| `pages/MemberCard.tsx` | Rewrite | Tabs：会员等级 / 会员列表；等级 Modal 编辑/删除；会员详情 Modal |
| `pages/Points.tsx` | Rewrite | Tabs：积分商品 / 兑换记录；商品 Modal 加封面图（ImageManager）+ 详情（RichEditor） |
| `pages/ShopOrders.tsx` | Rewrite | 订单中心：状态/配送方式筛选 + 自提徽标；详情 Modal 拉 `GET /shop/orders/{id}` 展示商品清单；发货/核销 Modal |
| `pages/Modules.tsx` | Modify | 编辑 Modal 提交改为 `PUT /modules/{id}`（含 status），修死 UI |
| `api/coupon/**` `api/vote/**` `api/seckill/**` `api/memberCard/**` `api/points/**` `api/shop/**` | Modify | 各页面任务内同步（类型 + path + query） |
| `components/index.ts`、`pages/Materials.tsx` | - | **不动**（既有未提交改动） |

---

## Task 1 (后端): coupon GET/PUT 单条详情与整体更新

**Files:**
- Modify: `src/modules/coupon/persistence.zig`
- Modify: `src/modules/coupon/service.zig`
- Modify: `src/modules/coupon/api.zig`（routes 表 + handler + DTO）

**Interfaces:**
- Consumes: 现有 `Coupon` schema、`getCoupon`/`listCoupons`、`CreateCouponReq`（字段：account_id,title,amount,min_amount,total,per_user,start_at,end_at,status）。
- Produces（供 FE Coupon 任务使用）:
  - `GET /api/v1/coupons/{id}` → `CouponDto`（与列表 DTO 同构）
  - `PUT /api/v1/coupons/{id}`，请求体字段与 `CreateCouponReq` 相同（**不含 account_id**，account 作用域不变）；响应 `{id}` 或 204 风格（跟随本文件既有 PUT `.../status` 的响应写法）

- [ ] **Step 1: 通读模块并核对现状**

Run: 读 `src/modules/coupon/{persistence,service,api}.zig` 全文。确认 store 是否有按 id 取单条与更新方法、`getCoupon` 服务函数签名、现有 PUT `coupons/{id}/status` 的 handler/DTO/route-spec 写法与权限 meta。

- [ ] **Step 2: persistence 补两个方法**

在 `*Store` 增加（QueryBuilder 风格严格跟随文件内既有查询，例如 `dupCoupon` / `setStatus`）：
- `getById(id) -> ?CouponRow`（tenant 过滤，供 service 校验存在性）
- `update(id, title, amount, min_amount, total, per_user, start_at, end_at, status, now)` → 受影响行数

- [ ] **Step 3: service 补两个方法**

- `getCoupon(tid, id)` 已存在则保持；否则用 `getById` 补。
- `updateCoupon(tid, id, title, amount, min_amount, total, per_user, start_at, end_at, status) error`：`title` 空 → `error.InvalidInput`；先 `getById`，不存在 → `error.NotFound`；再调用 store `update`，影响 0 行也视为成功（幂等）。

- [ ] **Step 4: api 注册两条路由并实现 handler**

routes 表追加（nest 与现有一致）：
- `GET coupons/{id}`（meta 同列表）
- `PUT coupons/{id}`（meta 同创建/删除）
handler 解析路径 id、解析请求体 JSON（新 DTO `UpdateCouponReq`，字段同 `CreateCouponReq` 去 account_id，默认值跟随 Create），调用 service，返回与模块一致的成功响应。加 `CouponDto` 单条序列化复用。

- [ ] **Step 5: 编译验证**

Run: `zig build`
Expected: 成功（如 file_store 相关报错出现请报告，不得修改 file_store）。

- [ ] **Step 6: Commit**

```bash
git add src/modules/coupon
git commit -m "feat(coupon): add GET/PUT /coupons/{id} detail and update endpoints"
```

---

## Task 2 (后端): vote PUT/DELETE

**Files:**
- Modify: `src/modules/vote/{persistence,service,api}.zig`

**Interfaces:**
- Consumes: `Vote`/`VoteRecord` schema；`VoteDto`(id,account_id,title,options_json,end_at,created_at)；`CreateVoteReq`(account_id,title,options,end_at)；`getVote`；store `createRecord`/`tally`。
- Produces:
  - `PUT /api/v1/votes/{id}`，体字段同 `CreateVoteReq` 去 account_id（`options: []string` → 服务内 `options_json` 序列化同 create）；成功响应跟随文件风格
  - `DELETE /api/v1/votes/{id}` → 删除投票及其全部投票记录

- [ ] **Step 1: 通读模块**

Run: 读 `src/modules/vote/{persistence,service,api}.zig` 全文，记录 options_json 序列化 helper、结果 handler、权限 meta、错误响应风格。

- [ ] **Step 2: persistence**

- `update(id, title, options_json, end_at, now)`（tenant 过滤）
- `deleteById(id)`（tenant 过滤）
- `deleteRecordsByVoteId(vote_id)`（先删记录再删投票，避免孤儿）

- [ ] **Step 3: service**

- `updateVote(tid, id, title, options, end_at)`：校验 title 非空、options 非空列表；`getVote` 不存在 → `error.NotFound`；序列化 options_json 与 create 一致后 store update
- `deleteVote(tid, id)`：不存在 → `error.NotFound`；先 `deleteRecordsByVoteId` 再 `deleteById`

- [ ] **Step 4: api**

routes 表追加 `PUT votes/{id}`、`DELETE votes/{id}`；新增 `UpdateVoteReq`；handler 调 service。删除/更新权限 meta 与创建一致。

- [ ] **Step 5: 编译**

Run: `zig build` → 成功。

- [ ] **Step 6: Commit**

```bash
git add src/modules/vote
git commit -m "feat(vote): add PUT/DELETE /votes/{id} endpoints"
```

---

## Task 3 (后端): seckill PUT/DELETE + 抢购记录补活动标题

**Files:**
- Modify: `src/modules/seckill/{persistence,service,api}.zig`

**Interfaces:**
- Consumes: `SeckillActivity`/`SeckillOrder` schema；`getActivity`(service.zig:54)；orders 列表 handler 当前返回裸 `SeckillOrderRow`（id/account_id/openid/activity_id/quantity/created_at）。
- Produces:
  - `GET /api/v1/seckills/{id}` → `ActivityDto`（编辑回填用）
  - `PUT /api/v1/seckills/{id}`，体同 `CreateActivityReq` 去 account_id（title,price,original_price,stock,per_user,start_at,end_at,status）
  - `DELETE /api/v1/seckills/{id}` → 删除活动及其订单
  - `GET /api/v1/seckills/orders` 每行新增 `activity_title` 字段

- [ ] **Step 1: 通读模块**

Run: 读 `src/modules/seckill/{persistence,service,api}.zig`，记录 orders handler、status PUT、权限 meta。

- [ ] **Step 2: persistence**

- `getById(id) -> ?ActivityRow`
- `update(id, title, price, original_price, stock, per_user, start_at, end_at, status, now)`
- `deleteById(id)`、`deleteOrdersByActivityId(activity_id)`
- （标题富化）确认存在 `getActivity`/`getById` 供 handler 循环取标题

- [ ] **Step 3: service**

- `updateActivity(tid, id, ...)`: `getById` 不存在 → `error.NotFound`；`stock < sold` → `error.InvalidInput`（库存不得小于已售）；余同 coupon
- `deleteActivity(tid, id)`: 不存在 → NotFound；先删订单再删活动
- 富化 helper：给定 `[]SeckillOrderRow`，按 distinct activity_id 取标题，产出带 `activity_title` 的 DTO 列表（订单 ≤ 100，N 次小查询可接受）

- [ ] **Step 4: api**

追加 `GET seckills/{id}`、`PUT seckills/{id}`、`DELETE seckills/{id}`；orders handler 改为经富化 DTO 输出 `activity_title`。

- [ ] **Step 5: 编译**

Run: `zig build` → 成功。

- [ ] **Step 6: Commit**

```bash
git add src/modules/seckill
git commit -m "feat(seckill): add detail/update/delete endpoints and activity title on orders"
```

---

## Task 4 (后端): member-card 等级 PUT/DELETE

**Files:**
- Modify: `src/modules/member_card/{persistence,service,api}.zig`

**Interfaces:**
- Consumes: `MemberCardLevel`/`MemberAccount` schema；`listMembers` 已有按 openid 匹配；status PUT 已有。
- Produces:
  - `PUT /api/v1/member-cards/{id}`，体同 `CreateLevelReq` 去 account_id（name,level,discount,points_ratio,threshold,status）
  - `DELETE /api/v1/member-cards/{id}`；存在引用该等级的会员时返回错误（不级联）

- [ ] **Step 1: 通读模块**

Run: 读 `src/modules/member_card/{persistence,service,api}.zig`。

- [ ] **Step 2: persistence**

- `getLevelById(id) -> ?LevelRow`
- `updateLevel(id, name, level, discount, points_ratio, threshold, status, now)`
- `deleteLevel(id)`
- `countMembersByLevel(level_id) -> i64`（供删除守卫）

- [ ] **Step 3: service**

- `updateLevel(tid, id, ...)`: name 空 → InvalidInput；不存在 → NotFound
- `deleteLevel(tid, id)`: 不存在 → NotFound；`countMembersByLevel(id) > 0` → `error.InvalidState`（消息如“该等级下存在会员，无法删除”）

- [ ] **Step 4: api**

追加 `PUT member-cards/{id}`、`DELETE member-cards/{id}`；新 DTO `UpdateLevelReq`。

- [ ] **Step 5: 编译**

Run: `zig build` → 成功。

- [ ] **Step 6: Commit**

```bash
git add src/modules/member_card
git commit -m "feat(member-card): add PUT/DELETE /member-cards/{id} endpoints"
```

---

## Task 5 (后端): module PUT /modules/{id}

**Files:**
- Modify: `src/modules/module/{persistence,service,api}.zig`

**Interfaces:**
- Consumes: `AppModule` schema（含 `status` String "active"）；`upsertModule(tenant_id, name, title, version, status, now)` 按 name upsert；`RegisterModuleReq`(name,title,version)。
- Produces:
  - `PUT /api/v1/modules/{id}`，体 `{ title, version, status }`（status ∈ "active"|"disabled"，service 内用既有 `validStatus` 校验）；成功响应同 POST

- [ ] **Step 1: 通读模块**

Run: 读 `src/modules/module/{persistence,service,api}.zig`，注意 `validStatus`（service.zig:25）与 upsert。

- [ ] **Step 2: persistence**

- `getModuleById(id) -> ?ModuleRow`（tenant 过滤）
- `updateModuleById(id, title, version, status, now)`（只 update title/version/status/updated_at）

- [ ] **Step 3: service**

- `updateModule(tid, id, title, version, status)`：`validStatus(status)` 失败 → InvalidInput；不存在 → NotFound；store update。

- [ ] **Step 4: api**

追加 route `PUT modules/{id}`（meta 同 POST）；新 DTO `UpdateModuleReq { title, version, status }`；handler 解析、校验、调用。

- [ ] **Step 5: 编译**

Run: `zig build` → 成功。

- [ ] **Step 6: Commit**

```bash
git add src/modules/module
git commit -m "feat(module): add PUT /modules/{id} to persist title/version/status"
```

---

## Task 6 (后端): points 积分商品 image/detail + 兑换记录补时间

**Files:**
- Modify: `src/modules/points/model.zig`（`PointsProduct`）
- Modify: `src/modules/points/persistence.zig`
- Modify: `src/modules/points/service.zig`
- Modify: `src/modules/points/api.zig`

**Interfaces:**
- Consumes: `PointsProduct`(name,points,stock,status)；`PointsOrderRow` 目前不含 created_at；`ProductReq`(account_id,name,points,stock,status)。
- Produces:
  - schema `PointsProduct` 增加 `image` String 默认 `""`、`detail` String 默认 `""`（detail 存富文本 HTML 字符串）
  - `ProductDto` 增加 `image`、`detail`；create/update 请求体增加 `image`、`detail`
  - `GET /api/v1/points/orders` 每行携带 `created_at`（Row + `dupOrder` 复制该列）

- [ ] **Step 1: 通读模块**

Run: 读 `src/modules/points/{model,persistence,service,api}.zig` 全文，记录 create/update 的 store 查询与 `dupOrder`。

- [ ] **Step 2: model 加列**

`PointsProduct` 的 `Schema(...)` 增加 `image` 与 `detail` 两列（String、Default("")）。zent 启动时自动 migrate。

- [ ] **Step 3: persistence**

- `dupProduct` 结构体与 create 查询增加 `image`、`detail`
- update 查询增加 `image`、`detail`
- `PointsOrderRow` 增加 `created_at`（i64）；`dupOrder` 复制 `created_at`

- [ ] **Step 4: service**

`createProduct(tid, account_id, name, points, stock, status, image, detail)`、`updateProduct(id, name, points, stock, status, image, detail)` 透传两字段（name 空校验保持）。

- [ ] **Step 5: api**

`ProductReq`（create 用）与 update 匿名体增加 `image`/`detail`（默认 `""`）；`ProductDto` 与序列化增加两字段；orders handler 的响应经 Row 自然带出 `created_at`（若 DTO 独立则补字段）。

- [ ] **Step 6: 编译**

Run: `zig build` → 成功。

- [ ] **Step 7: Commit**

```bash
git add src/modules/points
git commit -m "feat(points): add image/detail to products and created_at to orders"
```

---

## Task 7 (后端): shop 订单 DTO 补 pickup 字段 + 配送方式过滤

**Files:**
- Modify: `src/modules/shop/api_dto.zig`（`OrderDto`/`toOrderDto`）
- Modify: `src/modules/shop/trade_store.zig`（`listOrders`）
- Modify: `src/modules/shop/service.zig`（`listOrders` 透传）
- Modify: `src/modules/shop/handlers/trade.zig`（`adminOrders` 解析 query）
- Modify: `src/modules/shop/api.zig`（如路由表无需改则仅确认）

**Interfaces:**
- Consumes: `ShopOrderRow` 已含 pickup_type/pickup_code/store_id（trade_store.zig:387-389）；`listOrders(page,page_size,tid,account_id,openid,status)`。
- Produces:
  - `OrderDto` 增加 `pickup_type`(String)、`pickup_code`(String)、`store_id`(i64)
  - `GET /api/v1/shop/admin/orders` 新增可选 query `pickup_type`（`delivery`|`self`|空=全部），服务/store 逐层加谓词（`pickup_typeEQ`，仅当非空）
  - `svc.listOrders` 签名增加 `pickup_type: []const u8` 参数（C-end `orderList` 调用处传 `""`）

- [ ] **Step 1: 通读四处代码**

Run: 读 `api_dto.zig`(OrderDto/toOrderDto)、`trade_store.zig`(listOrders)、`service.zig`(listOrders)、`handlers/trade.zig`(adminOrders + orderList)、`api.zig` 路由表。确认所有 `svc.listOrders` 调用点（adminOrders 与 C-end orderList 两处）。

- [ ] **Step 2: DTO 补字段**

`OrderDto` 增 3 字段；`toOrderDto` 从 row 透传（此时无 store/account join 风险，row 均非空）。

- [ ] **Step 3: store 加谓词**

`listOrders` 增加 `pickup_type: []const u8` 入参，`pickup_type.len > 0` 时追加 `pickup_typeEQ`。

- [ ] **Step 4: service 透传**

`svc.listOrders` 增加 `pickup_type` 入参并透传 store；两处调用点更新（adminOrders 传解析出的 query 值，C-end `orderList` 传 `""` 保持原行为）。

- [ ] **Step 5: handler 解析 query**

`adminOrders` 读取可选 `pickup_type` query 字符串（空串默认），校验取值只能是 `""`|`"delivery"`|`"self"`，否则 400（复用本文件参数解析风格）。

- [ ] **Step 6: 编译**

Run: `zig build` → 成功。

- [ ] **Step 7: Commit**

```bash
git add src/modules/shop
git commit -m "feat(shop): expose pickup fields on order dto and add pickup_type filter"
```

---

## Task 8 (前端): Coupon 页面 Tabs + 编辑 Modal

**Files:**
- Modify: `web/src/pages/Coupon.tsx`
- Modify: `web/src/api/coupon/types.ts`
- Modify: `web/src/api/coupon/query.ts`

**Interfaces:**
- Consumes: 任务一后端契约（GET/PUT `/coupons/{id}`）；现有 `listCoupons/listCouponUsers/createCoupon/deleteCoupon/claimCoupon/useCoupon/setCouponStatus`；`CouponItem` 字段含 start_at/end_at/per_user。
- Produces:
  - `getCoupon(id)`、`updateCoupon(id, body)` 两个 query fn；`UpdateCouponRequest` 类型
  - 页面：Tabs `优惠券模板` / `领取记录`

- [ ] **Step 1: 读现状与范式**

Run: 读 `Coupon.tsx`、`LuckyDraw.tsx`（Tabs + 共用编辑 Modal 范式）、`Modules.tsx`（FormModal 复用于 create/edit）。确认 coupon 金额元↔分换算当前实现并沿用。

- [ ] **Step 2: api 层**

`types.ts`：新增 `UpdateCouponRequest`（字段同 CreateCouponRequest 去 account_id，全必填默认同 Create）。`query.ts`：`getCoupon(id)`、`updateCoupon(id, body)` 走 `PUT /coupons/{id}`（`path.ts` 增加 `coupon(id)` 常量，仿 points 的写法）。

- [ ] **Step 3: 改造页面主体**

- 顶部保留 `AdminCrudPage` 外壳语义改 `<Tabs tabs={['优惠券模板','领取记录']} ...>` + 两个 `<Show>` 分区。
- 优惠券模板区：列表列沿用并加 `per_user`、有效期(start_at~end_at)、状态徽标；行操作：编辑 / 上架·下架 / 发券 / 删除。表头“新增优惠券”打开新建 Modal。
- 领取记录区：沿用现有 SearchBar + DataTable（openid/keyword/status 过滤）。
- 表单字段统一 `FormField` 包裹：券名(text,required)、面额（元,number step 0.01）、使用门槛（元）、发放总量(0=不限)、每人限领(number,min 1)、生效时间/失效时间(datetime-local ↔ epoch 秒)、状态(select 上架/下架)。新建/编辑共用一个 `FormModal`（`editing: CouponItem | null` 区分，标题“编辑优惠券 #id”/“新增优惠券”），提交分支 `editing() ? updateCoupon(id, body) : createCoupon(body)`，成功后 `feedback.toast` + 关闭 + `refresh()`。
- 账号切换关闭 Modal、重置表单（沿用 `onAccountChange` + 各分区 `reload(1)`）。

- [ ] **Step 4: 类型检查与构建**

Run: `cd web && npm run typecheck` 与 `npm run build` → 均通过。

- [ ] **Step 5: Commit**

```bash
git add web/src/pages/Coupon.tsx web/src/api/coupon
git commit -m "feat(admin): refactor coupon page to tabs with edit modal"
```

---

## Task 9 (前端): Vote 页面重写（Tabs + CRUD + 统计）

**Files:**
- Modify: `web/src/pages/Vote.tsx`
- Modify: `web/src/api/vote/{types,query}.ts`、`path.ts`（如存在）

**Interfaces:**
- Consumes: 任务二后端契约；现有 `listVotes/createVote/getVoteResults/castVote`；`VoteItem.options_json`(JSON 字符串)。
- Produces:
  - `updateVote(id, body)`、`deleteVote(id)` query fn；`UpdateVoteRequest{title, options, end_at?}`；`VoteOptionCount = {options: string[], tally: number[]}` helper（页面内解析即可，不强求独立类型）
  - 页面：Tabs `投票活动` / `投票统计`

- [ ] **Step 1: api 层**

`types.ts` 增 `UpdateVoteRequest`；`query.ts` 增 `updateVote(id, body)`（PUT `/votes/{id}`）、`deleteVote(id)`；`path.ts` 增 `vote(id)`（仿 points `product(id)` 常量写法）。

- [ ] **Step 2: 重写页面**

- `AdminCrudPage` 外壳 + Tabs 两分区。
- Tab1 `投票活动`：`usePaged<VoteItem>`；列：标题 / 选项摘要（`JSON.parse(options_json).join('、')`，截断）/ 结束时间(formatDateTime) / 创建时间；行操作：编辑（打开共用 FormModal）、删除（`feedback.runAction` + danger confirm）。新建按钮同 Modal。表单：题目(text,required)、选项(textarea,placeholder 提示“每行一个选项，支持回车/逗号分隔”，提交时按既有 `/[\n,，]/` 拆分、过滤空行、≥2 校验)、结束时间(datetime-local ↔ epoch，可空)。
- Tab2 `投票统计`：独立的 `usePaged<VoteItem>`（同一 `listVotes`）；行操作“统计”→ 打开只读详情 `FormModal`（无 onSubmit）：展示标题、各选项 + 票数 + 简单百分比条（`getVoteResults(id)` 返回 tally i64[]，与 options 对齐；无 `total` 时兜底 0）；无票显示空态文案。
- 编辑回填：`options_json` 解析后 join('\n') 填 textarea；`end_at>0` 转 datetime-local。
- 账号切换重置两分区。

- [ ] **Step 3: 类型检查与构建**

Run: `cd web && npm run typecheck` 与 `npm run build` → 均通过。

- [ ] **Step 4: Commit**

```bash
git add web/src/pages/Vote.tsx web/src/api/vote
git commit -m "feat(admin): rewrite vote page with tabs and edit/delete"
```

---

## Task 10 (前端): Seckill 页面 Tabs + 编辑 Modal

**Files:**
- Modify: `web/src/pages/Seckill.tsx`
- Modify: `web/src/api/seckill/{types,query,path}.ts`

**Interfaces:**
- Consumes: 任务三后端契约（含 orders 行 `activity_title`）；现有 `listSeckills/createSeckill/rushSeckill/setSeckillStatus/listSeckillOrders`。
- Produces:
  - `getSeckill(id)`、`updateSeckill(id, body)`、`deleteSeckill(id)` query fn；`UpdateSeckillRequest`
  - 页面：Tabs `活动管理` / `抢购记录`

- [ ] **Step 1: api 层**

`types.ts`：`SeckillOrderItem` 增加 `activity_title?: string`；增 `UpdateSeckillRequest`（同 Create 去 account_id）。`query.ts`：`getSeckill(id)`、`updateSeckill(id, body)`、`deleteSeckill(id)`；`path.ts` 增 `seckill(id)`。

- [ ] **Step 2: 页面改造**

- Tabs `活动管理` / `抢购记录`。活动列沿用并保留 售罄进度(sold/stock)；行操作：编辑 / 上架·下架 / 删除(danger confirm) / 抢购。
- 表单 `FormField` 包裹：活动名称(required)、秒杀价（元,step 0.01,min 0.01）、原价（元）、库存(number,min 1)、每人限购(number,min 1)、开始/结束时间(datetime-local ↔ epoch)、状态 select。新建/编辑共用 Modal。
- 抢购记录 tab：列 活动(activity_title 或 activity_id 兜底)/ 买家 openid / 数量 / 时间；保留手动抢购按钮在活动行（原逻辑）或记录区顶部（保持原交互即可，二选一不重复）。
- 编辑时若 stock 已售罄说明（hint：已售 X 件）。

- [ ] **Step 3: 类型检查与构建**

Run: `cd web && npm run typecheck` 与 `npm run build` → 均通过。

- [ ] **Step 4: Commit**

```bash
git add web/src/pages/Seckill.tsx web/src/api/seckill
git commit -m "feat(admin): refactor seckill page to tabs with edit/delete"
```

---

## Task 11 (前端): MemberCard 页面 Tabs + 等级编辑/删除 + 会员详情 Modal

**Files:**
- Modify: `web/src/pages/MemberCard.tsx`
- Modify: `web/src/api/memberCard/{types,query,path}.ts`

**Interfaces:**
- Consumes: 任务四后端契约；现有 `listMemberLevels/createMemberLevel/setMemberLevelStatus/listMembers/getMemberView/openMemberCard/adjustMemberPoints`。
- Produces:
  - `updateMemberLevel(id, body)`、`deleteMemberLevel(id)` query fn；`UpdateLevelRequest`
  - 页面：Tabs `会员等级` / `会员列表`

- [ ] **Step 1: api 层**

`types.ts` 增 `UpdateLevelRequest`（同 CreateLevelRequest 去 account_id）；`query.ts` 增 `updateMemberLevel`/`deleteMemberLevel`；`path.ts` 增 `memberLevel(id)`。

- [ ] **Step 2: 页面改造**

- Tabs：会员等级 / 会员列表。
- 等级 tab：列 名称/等级/折扣(fenToYuan? 否——discount 千分比展示 `(discount/100).toFixed(1)` 折 + 阈值 + 积分倍率 + 状态 + 操作(编辑/启用停用/删除 danger)。新建/编辑共用 FormModal：等级名称(required)、等级值(number,min 1)、折扣（折,number,step 0.1,max 10,min 0.1）、升级门槛（积分）、积分倍率(number,min 0)。提交转千分比/×100 与现有一致。
- 会员列表 tab：沿用 SearchBar(openid)；列 openid/等级(level_id 展示，若需等级名可保留 level_id 数值并加 title)、积分/累计积分/开卡时间；行操作：详情 → 只读详情 Modal（先 `getMemberView(accountId, openid)`；未办卡显示“未办卡 + 开卡按钮”，已办卡显示 openid/等级名/折扣/积分/累计 + 积分调整 +100/−100 按钮，调用 `adjustMemberPoints` 后刷新详情与列表）。把原内联会员详情卡片整体迁入 Modal，删除内联区块。
- 删除等级用 `feedback.runAction` + danger；后端返回“该等级下存在会员”时 toast 展示错误消息。

- [ ] **Step 3: 类型检查与构建**

Run: `cd web && npm run typecheck` 与 `npm run build` → 均通过。

- [ ] **Step 4: Commit**

```bash
git add web/src/pages/MemberCard.tsx web/src/api/memberCard
git commit -m "feat(admin): refactor member-card page to tabs with level edit/delete"
```

---

## Task 12 (前端): Points 页面 Tabs + 商品图片/详情富文本

**Files:**
- Modify: `web/src/pages/Points.tsx`
- Modify: `web/src/api/points/{types,query}.ts`

**Interfaces:**
- Consumes: 任务六后端契约（ProductDto 增 image/detail；orders 行带 created_at）；现有 `listProducts/createProduct/updateProduct/deleteProduct/redeemPoints/adjustPoints/listPointsOrders`。
- Produces:
  - `PointsProduct` 类型增 `image`、`detail`；`CreateProductRequest`/`UpdateProductRequest` 增 `image`、`detail`
  - 页面：Tabs `积分商品` / `兑换记录`；商品表单含封面图（ImageManager + URL 直填）与详情富文本（RichEditor）

- [ ] **Step 1: api 层**

同步 types：`PointsProduct {…, image: string, detail: string}`；Create/UpdateRequest 加 `image?`/`detail?`。query 透传两字段（create/update 调用处增加参数或并入 body）。

- [ ] **Step 2: 页面改造**

- 改为 Tabs：积分商品 / 兑换记录（`Show when={tab()==='…'}` 切换；兑换记录沿用现有 `useLocalPaged<PointsOrder>` 与 openid/product_name 客户端过滤逻辑，仅迁移进 tab 区）。
- 商品表单 `FormField` 包裹并新增：
  - 封面图：FormField 内 预览 `<img>`（`fileUrl`/`publicFileUrl` 与 Materials 一致）+ “选择图片”按钮开 `<ImageManager multiple={false} max={1} onSelect={(items)=> items[0] && setImage(publicFileUrl(items[0]))} />` + “清除” + URL 文本直填（仿 `Materials.tsx` thumbUrl 区块）。
  - 商品详情：`<FormField label="商品详情"><RichEditor value={detail()} onInput={setDetail} placeholder="请输入商品详情介绍…"/></FormField>`（仿 Materials 正文区块；提交用 `detail().trim()`）。
  - 保留：商品名称(required)、所需积分(number,min 1)、库存(number,min 0)、状态 select。
- 列表列新增 图片（缩略 40px 圆角，无图显示占位）与 详情摘要（detail 去标签后截断或省略不展示——仅列表不加详情列也可，确保编辑 Modal 回填两字段）。编辑回填 image/detail。

- [ ] **Step 3: 类型检查与构建**

Run: `cd web && npm run typecheck` 与 `npm run build` → 均通过。

- [ ] **Step 4: Commit**

```bash
git add web/src/pages/Points.tsx web/src/api/points
git commit -m "feat(admin): refactor points page to tabs with product image and detail"
```

---

## Task 13 (前端): ShopOrders 订单中心（详情拉单 + 发货/核销 + 配送过滤）

**Files:**
- Modify: `web/src/pages/ShopOrders.tsx`
- Modify: `web/src/api/shop/{types,query,path}.ts`

**Interfaces:**
- Consumes: 任务七后端契约；现有 `listShopOrders/shipShopOrder`；`GET /api/v1/shop/orders/{id}`（public，返回 `{order: OrderDto, items: [OrderProductDto], commented_order_product_ids}`）；核销 `POST /api/v1/shop/admin/orders/{id}/pickup` body `{code}`（shop:write）。
- Produces:
  - `ShopOrderItem` 增 `pickup_type`/`pickup_code`/`store_id`；`ShopOrderProductItem`（id,order_id,product_id,sku_id,name,image,spec_json,price,quantity,created_at）；`ShopOrderDetail {order, items, commented_order_product_ids}`；`getShopOrderDetail(id)`、`pickupShopOrder(id, code)`、`listShopOrders` 增 `pickupType` 参数
  - 页面：状态/配送方式筛选 + 自提徽标 + 发货/核销动作 + 详情 Modal

- [ ] **Step 1: api 层**

`types.ts`：扩 `ShopOrderItem`；新增 `ShopOrderProductItem` 与 `ShopOrderDetail`。`path.ts`：确认既有 `adminOrders`；补 `order(id)`（`shop/orders/${id}`）。`query.ts`：`getShopOrderDetail(id)`（GET order(id)，注意该接口返回非 ruoyi envelope——`{order,items,…}`，直接用 unwrapEnvelope 之外的取数方式，参照该文件对非标准响应的处理）；`pickupShopOrder(id, code)`（POST admin orders pickup）；`listShopOrders` 签名加 `pickupType=''` 并拼进 query。

- [ ] **Step 2: 页面改造**

- 搜索区 SearchBar 增加字段：订单状态 select(全部/待支付/已支付/待发货…)沿用现有 STATUS map；配送方式 select(全部/配送/自提) → 值 ''/'delivery'/'self' → `pickupType`。
- 列：订单号/买家 openid/**类型徽标**（pickup_type==='self' → daisyUI badge “自提”，配送不显示）/实付/状态/物流或取件码(自提订单显示 pickup_code)/下单时间。
- 行操作：
  - 详情：打开 Modal，进入时 `getShopOrderDetail(id)` 拉取（loading 态 + 错误重试）；展示基础字段 + 收货地址（`JSON.parse(address_json)` 的 region+detail+name+mobile，容错 try/catch）+ **商品清单小表**（image 缩略 + name + spec_json + 单价 + 数量 + 小计）。
  - 发货：仅 `status===1 && pickup_type!=='self'`；沿用快递公司/单号 Modal。
  - 核销：仅 `status===1 && pickup_type==='self'`；Modal 只读展示取件码 = row.pickup_code，确认按钮提交 `pickupShopOrder(id, row.pickup_code)`（说明文案“核销后订单将标记为已完成”），成功后 refresh。
  - 写操作（发货/核销）按钮沿用当前无条件渲染（与该页既有行为一致）；若 `web/src` 有可用的权限判断 helper（读 `web/src/index.tsx` 的 PermissionGate/AuthContext 确认），存在则用其隐藏无 shop:write 权限者的写按钮，不存在则保持。
- 状态 map、formatYuan 展示沿用。

- [ ] **Step 3: 类型检查与构建**

Run: `cd web && npm run typecheck` 与 `npm run build` → 均通过。

- [ ] **Step 4: Commit**

```bash
git add web/src/pages/ShopOrders.tsx web/src/api/shop
git commit -m "feat(admin): rebuild shop orders as order center with detail and pickup"
```

---

## Task 14 (前端): Modules 编辑持久化 status

**Files:**
- Modify: `web/src/pages/Modules.tsx`
- Modify: `web/src/api/module/{types,query}.ts`（目录名以实际为准，见 Step 1）

**Interfaces:**
- Consumes: 任务五后端契约（PUT `/modules/{id}`，体 `{title,version,status}`）；Modules.tsx 编辑 Modal 已含 status select（死 UI）。
- Produces:
  - `updateModule(id, body)` query fn；`UpdateModuleRequest {title, version, status}`（或复用 Register 类型加 status? 并以 id 分支）
  - 编辑提交改走 PUT（新建仍 POST）

- [ ] **Step 1: 定位 module api 文件**

Run: 用 Glob/Grep 找 `web/src/api` 下 module 相关 types/query/path 文件（可能是 `api/modules/*` 或注册在 `api/module/*`），读 `Modules.tsx` 的 `openEditModule` 与提交函数。

- [ ] **Step 2: api 层**

新增 `updateModule(id, body)` → `PUT /modules/{id}`；types 增加/扩展（含 `status: 'active'|'disabled'`，可为可选，服务端默认 active 仅对新注册生效）。

- [ ] **Step 3: 页面接线**

`onModuleSubmit` 分支：`editing id 存在 ? updateModule(editing.id, {title, version, status: moduleForm().status}) : registerModule({name,title,version})`（新建仍不带 status，与后端一致）。编辑成功后 toast + 关闭 + reload；若后端返回 404（模块被删）提示刷新列表。

- [ ] **Step 4: 类型检查与构建**

Run: `cd web && npm run typecheck` 与 `npm run build` → 均通过。

- [ ] **Step 5: Commit**

```bash
git add web/src/pages/Modules.tsx web/src/api/module web/src/api/modules
git commit -m "fix(admin): persist module status through PUT /modules/{id}"
```

---

## Task 15 (验证收尾)

- [ ] **Step 1: 全量前端校验**

Run: `cd web && npm run typecheck && npm run build`
Expected: 均通过，无类型错误。

- [ ] **Step 2: 后端编译与测试**

Run: `zig build`（成功）；`zig build test`（允许且仅允许既有 `file_store.create` 签名类失败，其余必须全绿；如有新失败需报告并修复）。

- [ ] **Step 3: 手工冒烟（若 3001 前端可达）**

Run: 浏览器打开 `http://localhost:3001/coupons`、`/votes`、`/seckills`、`/member-cards`、`/points`、`/shop/orders`、`/modules`，逐页确认：列表加载、Tabs 切换、新建/编辑 Modal 打开与提交、删除确认、积分商品图/富文本输入、订单详情拉取与核销按钮显隐。记录每个页面结果；页面需要特定后端数据则说明。

- [ ] **Step 4: 阶段收尾汇报**

汇总改动文件清单、每个页面的验证结果、遗留 minor 与后续建议，报告给用户。

---

## Self-Review

**Spec 覆盖：** 6.1 六页前端改造全覆盖（coupon/vote/seckill/member-card/points/shop-orders）+ 6.2 后端五模块补接口全覆盖（coupon GET/PUT、vote PUT/DELETE、seckill PUT/DELETE、member-card PUT/DELETE、module PUT）。两点偏差已在 Global Constraints 记录：points schema 加列（用户要求 > spec 非目标）；shop-orders 不做退款审核 tab（与 /shop/admin 重复且越权，理由见前）。用户额外要求“points 商品图片与详情”已并入任务十二；"/modules status 无法持久化"（阶段 2 评审遗留）已并入任务五 + 任务十四。

**占位符检查：** 每个任务都有可执行步骤与验收命令；代码细节处要求实现者先读本模块既有文件并跟随其风格，避免凭空臆造 API 形态。

**类型一致性：** 前后端契约逐对列出（后端任务 Produces ↔ 前端任务 Consumes），字段名（image/detail/pickup_type/pickup_code/store_id/created_at/activity_title/options/end_at）全链一致；`listShopOrders` 增参、`svc.listOrders` 增参与 C-end 调用点 `""` 的处理已在任务七显式说明。
