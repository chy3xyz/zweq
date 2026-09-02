# unix 小程序 P1 营销场景 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 在 P0 商城闭环基础上，落地 6 个营销场景（积分商城、领券中心、大转盘、签到、会员卡、钱包/充值），并从首页场景宫格接入。

**架构：** 新建 6 个营销 API 客户端（对应后端 `app_bff/fan_api`、`app_bff/fan_scene_api`、`shop` 营销域），复用 `http`/`FanStore`/`NavBar`/`z-paging-x`；页面全部放分包 `src/sub/marketing/`，首页宫格跳转接入。

**技术栈：** uni-app X + UTS + Vue3 + uview-ultra + lime-request + x-pinia-s。

---

## 全局约定（继承 P0）

- 根路径 `/api/v1`；信封 `{ code, msg, data }`；`http.get<T>` 返回解包后的 `data`。
- 分页 `IPaged<T> = { list: T[], total: number, page: number, pageSize: number }`（已定义在 `src/api/shop.uts`，营销页复用 `import type { IPaged } from '@/src/api/shop'`）。
- 金额单位「分」（`fenToYuan`）；时间「秒级时间戳」（`formatTime`）。
- `account_id` 取 `src/utils/env.uts` 的 `DEFAULT_ACCOUNT_ID`。
- 所有 C 端请求带 fan token；营销接口大多需登录（调用前 `fanStore.hasLogin()` 判断，未登录跳 `/src/sub/auth/login`）。
- 编辑 `.uts/.uvue` 前调用 `uniapp-x-skill`；异步用 `.then()` 或 `async/await`（项目已确认两者可用）。

---

## 任务 1：营销 API 客户端

**文件：**
- 创建：`src/api/marketing.uts`（积分 + 券 + 抽奖 + 签到 + 会员卡，5 个域合并为一个文件，避免过度拆分）

### 步骤 1：类型定义 + API 函数（完整）

创建 `src/api/marketing.uts`：

```uts
import { http } from '../http/request'
import { DEFAULT_ACCOUNT_ID } from '../utils/env'

// ============ 积分 ============
export type IPointsProduct = {
  id: number
  account_id: number
  name: string
  points: number
  stock: number
}

export type IPointsOrder = {
  id: number
  product_id: number
  product_name: string
  points_spent: number
  status: string
}

// ============ 优惠券 ============
export type ICoupon = {
  id: number
  account_id: number
  title: string
  amount: number
  min_amount: number
  total: number
  per_user: number
  start_at: number
  end_at: number
}

export type ICouponUser = {
  id: number
  coupon_id: number
  code: string
  status: string
  created_at: number
}

// ============ 大转盘 ============
export type IDrawConfig = {
  cost: number
  daily_limit: number
  prize_count: number
}

export type IDrawRecord = {
  id: number
  prize_name: string
  points: number
  created_at: number
}

export type IDrawResult = {
  prize_name: string
  points: number
}

// ============ 签到 ============
export type ICheckinResult = {
  points: number
  fresh: boolean
}

export type ICheckinRecord = {
  id: number
  day: number
  points: number
  created_at: number
}

// ============ 会员卡 ============
export type IMemberCard = {
  openid: string
  level_name: string
  level: number
  discount: number
  points: number
  total_points: number
}

// 复用 shop.uts 的 IPaged（本文件不重复定义，调用方自行 import）

/** 积分商品列表 */
export function listPointsProducts(page: number, pageSize: number, accountId: number = DEFAULT_ACCOUNT_ID): Promise<IPaged<IPointsProduct>> {
  return http.get<IPaged<IPointsProduct>>(`/api/v1/app/points/products?account_id=${accountId}&page=${page}&page_size=${pageSize}`)
}

/** 积分兑换 */
export function redeemPoints(productId: number, accountId: number = DEFAULT_ACCOUNT_ID): Promise<{ order_id: number }> {
  return http.post<{ order_id: number }>('/api/v1/app/points/redeem', {
    account_id: accountId,
    product_id: productId,
  } as UTSJSONObject)
}

/** 我的积分兑换订单 */
export function listPointsOrders(accountId: number = DEFAULT_ACCOUNT_ID): Promise<IPointsOrder[]> {
  return http.get<IPointsOrder[]>(`/api/v1/app/points/orders?account_id=${accountId}`)
}

/** 领券中心券列表 */
export function listCoupons(page: number, pageSize: number, accountId: number = DEFAULT_ACCOUNT_ID): Promise<IPaged<ICoupon>> {
  return http.get<IPaged<ICoupon>>(`/api/v1/app/coupons?account_id=${accountId}&page=${page}&page_size=${pageSize}`)
}

/** 领券 */
export function claimCoupon(couponId: number, accountId: number = DEFAULT_ACCOUNT_ID): Promise<{ code: string }> {
  return http.post<{ code: string }>(`/api/v1/app/coupons/${couponId}/claim`, {
    account_id: accountId,
  } as UTSJSONObject)
}

/** 我的券 */
export function listMyCoupons(page: number, pageSize: number, accountId: number = DEFAULT_ACCOUNT_ID): Promise<IPaged<ICouponUser>> {
  return http.get<IPaged<ICouponUser>>(`/api/v1/app/my-coupons?account_id=${accountId}&page=${page}&page_size=${pageSize}`)
}

/** 抽奖配置 */
export function getDrawConfig(accountId: number = DEFAULT_ACCOUNT_ID): Promise<IDrawConfig> {
  return http.get<IDrawConfig>(`/api/v1/app/lucky-draw/config?account_id=${accountId}`)
}

/** 抽奖记录 */
export function listDrawRecords(page: number, pageSize: number, accountId: number = DEFAULT_ACCOUNT_ID): Promise<IPaged<IDrawRecord>> {
  return http.get<IPaged<IDrawRecord>>(`/api/v1/app/lucky-draw/records?account_id=${accountId}&page=${page}&page_size=${pageSize}`)
}

/** 抽奖 */
export function draw(accountId: number = DEFAULT_ACCOUNT_ID): Promise<IDrawResult> {
  return http.post<IDrawResult>('/api/v1/app/lucky-draw/draw', {
    account_id: accountId,
  } as UTSJSONObject)
}

/** 签到 */
export function checkin(accountId: number = DEFAULT_ACCOUNT_ID): Promise<ICheckinResult> {
  return http.post<ICheckinResult>('/api/v1/app/checkin', {
    account_id: accountId,
  } as UTSJSONObject)
}

/** 签到记录 */
export function listCheckinRecords(page: number, pageSize: number, accountId: number = DEFAULT_ACCOUNT_ID): Promise<IPaged<ICheckinRecord>> {
  return http.get<IPaged<ICheckinRecord>>(`/api/v1/app/checkin/records?account_id=${accountId}&page=${page}&page_size=${pageSize}`)
}

/** 会员卡视图（未办卡返回 null） */
export function getMemberCard(accountId: number = DEFAULT_ACCOUNT_ID): Promise<IMemberCard | null> {
  return http.get<IMemberCard | null>(`/api/v1/app/member-card?account_id=${accountId}`)
}

/** 办卡 */
export function openMemberCard(accountId: number = DEFAULT_ACCOUNT_ID): Promise<UTSJSONObject> {
  return http.post<UTSJSONObject>('/api/v1/app/member-card/open', {
    account_id: accountId,
  } as UTSJSONObject)
}

// ============ 钱包（储值套餐，复用 shop 域） ============
export type IBalancePlan = {
  id: number
  account_id: number
  name: string
  amount: number
  bonus: number
  status: number
}

/** 余额充值套餐列表 */
export function listBalancePlans(accountId: number = DEFAULT_ACCOUNT_ID): Promise<IBalancePlan[]> {
  return http.get<IBalancePlan[]>(`/api/v1/shop/balance-plans?account_id=${accountId}`)
}

/** 充值（按套餐） */
export function rechargePlan(planId: number, openid: string, accountId: number = DEFAULT_ACCOUNT_ID): Promise<UTSJSONObject> {
  return http.post<UTSJSONObject>(`/api/v1/shop/balance-plans/${planId}/recharge`, {
    account_id: accountId,
    openid: openid,
  } as UTSJSONObject)
}
```

### 步骤 2：验证

`uniappx-syntax-checker` 校验 `src/api/marketing.uts`。注意：`IPaged` 从 `shop.uts` 复用（不重复定义），但本文件 import 了 `http`/`DEFAULT_ACCOUNT_ID`，若用到 `IPaged` 需 `import type { IPaged } from './shop'`。若类型提示缺失，补上该 import。

---

## 任务 2：积分商城页

**文件：**
- 创建：`src/sub/marketing/points-mall/points-mall.uvue`
- 修改：`pages.json`

页面内容：
- 顶部展示我的积分（调 `getFanProfile` 拿 `points`，或从 `fanStore.state.points` 读）。
- 商品列表：`listPointsProducts(1, 20)`，每个商品显示名、所需积分、库存，点击「兑换」调 `redeemPoints(productId)`，成功刷新积分与列表。
- 「我的兑换订单」入口：调 `listPointsOrders()` 展示兑换记录。

`pages.json` `subPackages[0].pages` 加入：
```json
{ "path": "marketing/points-mall/points-mall", "style": { "navigationStyle": "custom", "navigationBarTitleText": "积分商城" } }
```

---

## 任务 3：领券中心 + 我的券

**文件：**
- 创建：`src/sub/marketing/coupon-center/coupon-center.uvue`
- 修改：`pages.json`

页面内容：
- 券列表：`listCoupons(1, 20)`，每张券显示标题、面额（`fenToYuan(amount)`）、门槛（`fenToYuan(min_amount)`）、有效期（`formatTime`），「领取」按钮调 `claimCoupon(id)`，成功后刷新。
- 「我的券」Tab 或入口：`listMyCoupons(1, 20)` 展示已领券（code、status）。

`pages.json` 加入 `marketing/coupon-center/coupon-center`。

---

## 任务 4：大转盘页

**文件：**
- 创建：`src/sub/marketing/lucky-draw/lucky-draw.uvue`
- 修改：`pages.json`

页面内容：
- 转盘：`getDrawConfig()` 拿 `cost/daily_limit/prize_count`；奖品列表前端用占位奖品（后端 config 只返回 prize_count，不返回具体奖品名，P0 用「奖品1..N」占位），转盘扇区数量 = `prize_count`。
- 「抽奖」按钮：调 `draw()`，成功弹窗展示 `prize_name`/`points`，并刷新记录。
- 抽奖记录：`listDrawRecords(1, 20)` 列表展示 `prize_name`/`points`/`formatTime(created_at)`。

转盘动画用 CSS `transform: rotate`（uni-app X 支持 transform，参考 `.agents/rules/uniappx.md`）。若实现旋转动画复杂，P0 可退化为「点击抽奖 → 结果弹窗」的简化交互，不做真实旋转动画。

`pages.json` 加入 `marketing/lucky-draw/lucky-draw`。

---

## 任务 5：签到页

**文件：**
- 创建：`src/sub/marketing/checkin/checkin.uvue`
- 修改：`pages.json`

页面内容：
- 「立即签到」按钮：调 `checkin()`，返回 `{ points, fresh }`；`fresh == true` 提示「签到成功 +N 积分」，否则提示「今日已签到」。
- 签到记录：`listCheckinRecords(1, 20)` 列表展示日期（`formatTime` 或 `formatDate`）+ 获得积分。
- 我的积分展示。

`pages.json` 加入 `marketing/checkin/checkin`。

---

## 任务 6：会员卡页

**文件：**
- 创建：`src/sub/marketing/member-card/member-card.uvue`
- 修改：`pages.json`

页面内容：
- `getMemberCard()`：返回 null 显示「未办卡」+「立即办卡」按钮（调 `openMemberCard()`）；返回数据则展示会员卡：等级名 `level_name`、等级 `level`、折扣 `discount`、积分 `points`/`total_points`。
- 卡片样式：渐变背景卡片（等级越高颜色越深，P0 统一一种色）。

`pages.json` 加入 `marketing/member-card/member-card`。

---

## 任务 7：钱包页

**文件：**
- 创建：`src/sub/marketing/wallet/wallet.uvue`
- 修改：`pages.json`

页面内容：
- 顶部「我的余额」：**临时方案** —— 用 `fanStore.state.points`（积分）近似展示，文案标注「积分」。注释说明：真正的钱包余额 C 端接口后端缺失，待后端补 `/app/wallet` 后替换。
- 充值套餐列表：`listBalancePlans()`，每个套餐显示名、金额（`fenToYuan(amount)`）、赠送（`bonus`），「充值」按钮调 `rechargePlan(planId, openid)`，成功提示。

`pages.json` 加入 `marketing/wallet/wallet`。

---

## 任务 8：首页宫格入口接入 + 联调收尾

**文件：**
- 修改：`src/pages/index/index.uvue`

内容：
- 把 P0 首页「场景应用」8 个宫格中，属于 P1 的 6 个（签到/大转盘/优惠券/会员卡/积分商城 + 新增钱包入口）从 `showToast('敬请期待')` 改为真实跳转：
  - 签到 → `/src/sub/marketing/checkin/checkin`
  - 大转盘 → `/src/sub/marketing/lucky-draw/lucky-draw`
  - 优惠券 → `/src/sub/marketing/coupon-center/coupon-center`
  - 会员卡 → `/src/sub/marketing/member-card/member-card`
  - 积分商城 → `/src/sub/marketing/points-mall/points-mall`
  - 钱包（可选，可加一个宫格或放「我的」页）→ `/src/sub/marketing/wallet/wallet`
  - 投票/秒杀/分销 3 个宫格（P2）保持「敬请期待」。
- 「我的」页（`src/pages/me/me.uvue`）也加「我的券 / 钱包」等快捷入口（可选，P0 已有「我的订单」，可并列加「我的券」「钱包」）。

收尾：`uniappx-syntax-checker` 全量校验 + 工作区 commit。

---

## 自检记录

- **规格覆盖度**：P1 的 6 个营销场景（积分/券/大转盘/签到/会员卡/钱包）+ 首页入口全部覆盖于任务 1-8。钱包余额用临时方案（任务 7 明确标注）。
- **类型一致性**：营销类型统一定义在 `marketing.uts`，`IPaged` 复用 `shop.uts`；各页面 import 一致。
- **占位符**：无 TODO；钱包余额临时方案为显式决策（非占位符），已标注后端缺口与替换路径。
