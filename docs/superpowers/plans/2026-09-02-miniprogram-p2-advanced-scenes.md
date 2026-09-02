# unix 小程序 P2 进阶场景 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 落地 7 个进阶场景（投票、秒杀、分销、拼团、评论、收藏、退款），补齐 P0/P1 后剩余的商城闭环能力。

**架构：** 新增 `src/api/scene.uts`（投票/秒杀/分销，对应 `app_bff/fan_scene_api`）；拼团/评论/收藏/退款 4 个 shop 域函数追加到 `src/api/shop.uts`；投票/秒杀/分销为独立分包页，拼团/评论/收藏/退款为**增强现有页面**（商品详情页、订单详情页）。

**技术栈：** 继承 P0/P1（uni-app X + UTS + Vue3 + uview-ultra + lime-request + x-pinia-s）。

---

## 全局约定（继承 P0/P1）

- 根路径 `/api/v1`；信封 `{ code, msg, data }`；分页 `IPaged<T>`（`shop.uts` 导出）。
- 金额「分」（`fenToYuan`）；时间「秒级」（`formatTime`/`formatDate`）。
- `account_id` 取 `DEFAULT_ACCOUNT_ID`；C 端请求带 fan token + 显式 openid。
- 页面 `onShow` 先 `fanStore.hasLogin()` 判断，未登录跳 `/src/sub/auth/login`。

---

## 任务 1：P2 API 客户端

**文件：**
- 创建：`src/api/scene.uts`（投票/秒杀/分销）
- 修改：`src/api/shop.uts`（追加拼团/评论/收藏/退款）

### 1a. 创建 `src/api/scene.uts`

```uts
import { http } from '../http/request'
import { DEFAULT_ACCOUNT_ID } from '../utils/env'
import type { IPaged } from './shop'

// ============ 投票 ============
export type IVote = {
  id: number
  account_id: number
  title: string
  options_json: string
  end_at: number
  created_at: number
}

export type IVoteDetail = {
  id: number
  title: string
  options_json: string
  end_at: number
  tally: number[]
}

// ============ 秒杀 ============
export type ISeckill = {
  id: number
  account_id: number
  title: string
  price: number
  original_price: number
  stock: number
  sold: number
  per_user: number
  start_at: number
  end_at: number
  status: number
  created_at: number
}

export type ISeckillOrder = {
  id: number
  account_id: number
  openid: string
  activity_id: number
  quantity: number
  created_at: number
}

// ============ 分销 ============
export type IDistribution = {
  openid: string
  parent_openid: string
  commission_balance: number
  total_commission: number
}

export function listVotes(page: number, pageSize: number, accountId: number = DEFAULT_ACCOUNT_ID): Promise<IPaged<IVote>> {
  return http.get<IPaged<IVote>>(`/api/v1/app/votes?account_id=${accountId}&page=${page}&page_size=${pageSize}`)
}

export function getVoteDetail(id: number): Promise<IVoteDetail> {
  return http.get<IVoteDetail>(`/api/v1/app/votes/${id}`)
}

export function voteBallot(id: number, optionIndex: number, accountId: number = DEFAULT_ACCOUNT_ID): Promise<UTSJSONObject> {
  return http.post<UTSJSONObject>(`/api/v1/app/votes/${id}/ballot`, {
    account_id: accountId,
    option_index: optionIndex,
  } as UTSJSONObject)
}

export function listSeckill(page: number, pageSize: number, accountId: number = DEFAULT_ACCOUNT_ID): Promise<IPaged<ISeckill>> {
  return http.get<IPaged<ISeckill>>(`/api/v1/app/seckill/activities?account_id=${accountId}&page=${page}&page_size=${pageSize}`)
}

export function listSeckillOrders(page: number, pageSize: number, accountId: number = DEFAULT_ACCOUNT_ID): Promise<IPaged<ISeckillOrder>> {
  return http.get<IPaged<ISeckillOrder>>(`/api/v1/app/seckill/orders?account_id=${accountId}&page=${page}&page_size=${pageSize}`)
}

export function seckillRush(id: number, quantity: number, accountId: number = DEFAULT_ACCOUNT_ID): Promise<{ order_id: number }> {
  return http.post<{ order_id: number }>(`/api/v1/app/seckill/activities/${id}/rush`, {
    account_id: accountId,
    quantity: quantity,
  } as UTSJSONObject)
}

export function getDistribution(accountId: number = DEFAULT_ACCOUNT_ID): Promise<IDistribution | null> {
  return http.get<IDistribution | null>(`/api/v1/app/distribution?account_id=${accountId}`)
}

export function joinDistribution(parentOpenid: string, accountId: number = DEFAULT_ACCOUNT_ID): Promise<UTSJSONObject> {
  return http.post<UTSJSONObject>('/api/v1/app/distribution/join', {
    account_id: accountId,
    parent_openid: parentOpenid,
  } as UTSJSONObject)
}

export function withdrawDistribution(amount: number, accountId: number = DEFAULT_ACCOUNT_ID): Promise<UTSJSONObject> {
  return http.post<UTSJSONObject>('/api/v1/app/distribution/withdraw', {
    account_id: accountId,
    amount: amount,
  } as UTSJSONObject)
}
```

注意：`seckillRush` 返回 `{ order_id }` 用匿名类型，UTS 不支持，改命名 type `export type IRushRes = { order_id: number }`，返回 `Promise<IRushRes>`。

### 1b. 修改 `src/api/shop.uts` 追加

```uts
// ============ 拼团 ============
export type IGroupon = {
  id: number
  account_id: number
  product_id: number
  group_price: number
  group_size: number
  status: number
}

// ============ 评论 ============
export type IComment = {
  id: number
  product_id: number
  openid: string
  star: number
  content: string
  created_at: number
}

// ============ 收藏 ============
export type IFavorite = {
  id: number
  openid: string
  product_id: number
  created_at: number
}

// ============ 退款 ============
export type IRefund = {
  id: number
  account_id: number
  order_id: number
  openid: string
  reason: string
  amount: number
  status: number
  created_at: number
}

export function listGroupons(accountId: number = DEFAULT_ACCOUNT_ID): Promise<IGroupon[]> {
  return http.get<IGroupon[]>(`/api/v1/shop/groupons?account_id=${accountId}`)
}

export function openGroupon(grouponId: number, openid: string, addressId: number, skuId: number, accountId: number = DEFAULT_ACCOUNT_ID): Promise<{ team_id: number }> {
  return http.post<{ team_id: number }>(`/api/v1/shop/groupons/${grouponId}/open`, {
    account_id: accountId,
    openid: openid,
    address_id: addressId,
    sku_id: skuId,
  } as UTSJSONObject)
}

export function listComments(productId: number): Promise<IComment[]> {
  return http.get<IComment[]>(`/api/v1/shop/comments?product_id=${productId}`)
}

export function createComment(productId: number, openid: string, star: number, content: string, orderProductId: number = 0, accountId: number = DEFAULT_ACCOUNT_ID): Promise<UTSJSONObject> {
  return http.post<UTSJSONObject>('/api/v1/shop/comments', {
    account_id: accountId,
    order_product_id: orderProductId,
    product_id: productId,
    openid: openid,
    star: star,
    content: content,
  } as UTSJSONObject)
}

export function listFavorites(openid: string, accountId: number = DEFAULT_ACCOUNT_ID): Promise<IFavorite[]> {
  return http.get<IFavorite[]>(`/api/v1/shop/favorites?account_id=${accountId}&openid=${openid}`)
}

export function addFavorite(openid: string, productId: number, accountId: number = DEFAULT_ACCOUNT_ID): Promise<UTSJSONObject> {
  return http.post<UTSJSONObject>('/api/v1/shop/favorites', {
    account_id: accountId,
    openid: openid,
    product_id: productId,
  } as UTSJSONObject)
}

export function deleteFavorite(favoriteId: number): Promise<UTSJSONObject> {
  return http.delete<UTSJSONObject>(`/api/v1/shop/favorites/${favoriteId}`)
}

export function applyRefund(orderId: number, openid: string, reason: string, accountId: number = DEFAULT_ACCOUNT_ID): Promise<UTSJSONObject> {
  return http.post<UTSJSONObject>('/api/v1/shop/refunds', {
    account_id: accountId,
    order_id: orderId,
    openid: openid,
    reason: reason,
  } as UTSJSONObject)
}

export function listRefunds(orderId: number): Promise<IRefund[]> {
  return http.get<IRefund[]>(`/api/v1/shop/refunds?order_id=${orderId}`)
}
```

注意：`openGroupon` 返回 `{ team_id }` 也改命名 type `IGrouponOpenRes = { team_id: number }`。

---

## 任务 2：投票页

**文件：** 创建 `src/sub/marketing/vote/vote.uvue`，修改 `pages.json`

- 投票列表：`listVotes(1, 20)` 展示 `title`/`end_at`；点击进详情。
- 投票详情：`getVoteDetail(id)` 得到 `{ title, options_json, end_at, tally }`；`JSON.parse<string[]>(options_json)` 解析选项，`tally` 展示各选项票数；点击选项调 `voteBallot(id, optionIndex)`，成功后刷新。
- 详情可做在列表页内嵌（点击展开）或独立详情页（P2 先内嵌：列表项点击展开选项并投票）。

`pages.json` 加入 `marketing/vote/vote`。

---

## 任务 3：秒杀页

**文件：** 创建 `src/sub/marketing/seckill/seckill.uvue`，修改 `pages.json`

- 秒杀活动列表：`listSeckill(1, 20)` 展示 `title`/`price`（`fenToYuan`）/`original_price`/`stock`/`sold`/倒计时（`end_at`）；「抢购」按钮调 `seckillRush(id, 1)`，成功提示「抢购成功」。
- 「我的秒杀订单」：`listSeckillOrders(1, 20)` 展示 `activity_id`/`quantity`/`created_at`。

`pages.json` 加入 `marketing/seckill/seckill`。

---

## 任务 4：分销页

**文件：** 创建 `src/sub/marketing/distribution/distribution.uvue`，修改 `pages.json`

- `getDistribution()`：null → 显示「成为分销员」+ 加盟按钮（`joinDistribution('')`，parent_openid 空则无上级）；有数据 → 展示分销面板：`commission_balance`（可提现佣金，`fenToYuan`）、`total_commission`（累计佣金）、「提现」按钮（调 `withdrawDistribution(amount)`，amount 用输入框或固定全额）。
- 提现金额输入框 + 提交。

`pages.json` 加入 `marketing/distribution/distribution`。

---

## 任务 5：拼团（增强商品详情页）

**文件：** 修改 `src/sub/shop/product-detail/product-detail.uvue`

- 商品详情页加载时若存在拼团，展示「拼团」入口：`listGroupons()` 筛出 `product_id == 当前商品` 的拼团，显示拼团价 `group_price`、`group_size` 人团。
- 「开团」按钮：调 `openGroupon(grouponId, openid, addressId, skuId)`，P0 简化：地址默认取 `listAddresses` 第一个，或跳结算页选择。成功提示「开团成功」。

（拼团需收货地址，若地址未选则提示先选地址。P2 简化：开团前 `listAddresses` 取第一个默认地址，无地址则提示去添加。）

---

## 任务 6：评论 + 收藏（增强商品详情页）

**文件：** 修改 `src/sub/shop/product-detail/product-detail.uvue`

- 评论区：`listComments(productId)` 展示评论列表（`star`/`content`/`created_at`）；「写评论」入口（`createComment(productId, openid, star, content)`，P0 简化为固定 5 星 + 输入框内容）。
- 收藏：详情页加「收藏」按钮，`addFavorite(openid, productId)`；已收藏可取消（`listFavorites` 判断 + `deleteFavorite`）。

---

## 任务 7：退款（增强订单详情页）

**文件：** 修改 `src/sub/shop/order-detail/order-detail.uvue`

- 订单详情页加「申请退款」按钮（`status` 为已支付/待发货时显示）：调 `applyRefund(orderId, openid, reason)`，reason 用输入框或固定文案。
- 退款记录：`listRefunds(orderId)` 展示退款状态。

---

## 任务 8：首页宫格接入 + 收尾

**文件：** 修改 `src/pages/index/index.uvue`

- 把 P2 的 3 个宫格（投票/秒杀/分销）从「敬请期待」改为真实跳转：
  - 投票 → `/src/sub/marketing/vote/vote`
  - 秒杀 → `/src/sub/marketing/seckill/seckill`
  - 分销 → `/src/sub/marketing/distribution/distribution`
- 收尾：`uniappx-syntax-checker` 全量校验 + commit。

---

## 自检记录

- **规格覆盖度**：P2 的 7 个功能全部覆盖（投票/秒杀/分销=独立页，拼团/评论/收藏=商品详情增强，退款=订单详情增强）。
- **类型一致性**：投票/秒杀/分销类型在 `scene.uts`，拼团/评论/收藏/退款在 `shop.uts`；匿名返回类型均改命名 type。
- **占位符**：无 TODO；拼团/评论的 P0 简化交互为显式决策。
