# unix 小程序 C 端商城设计文档

## 1. 概述

unix（unibestX 模板，`zweq/unix`）作为 zweq 多商户微信运营平台的 **C 端微信小程序前端**，对接后端已就绪的粉丝 API（`shop` 商城 + `app_bff` 营销场景），实现「完整电商 + 营销」闭环。

目标用户是**微信公众号/小程序的粉丝（消费者）**，而非运营者（运营者在 `web` 管理后台操作）。

## 2. 目标

- 粉丝身份登录：`uni.login()` → code → openid → fan token。
- 商城核心闭环：首页/分类/商品详情 → 购物车 → 结算 → 下单 → 微信支付 → 订单列表/详情。
- 营销场景：积分商城、优惠券、大转盘、签到、会员卡、钱包/充值。
- 进阶场景：秒杀、投票、分销、拼团、评论、收藏、退款。

## 3. 非目标

- 不改造后端数据库表结构与既有 API 语义（仅消费既有接口，见 §8 协作项）。
- 不实现运营者管理功能（`web` 端职责）。
- 不做多语言全量适配（首期仅中文）。
- 不更换技术栈（保持 uni-app X + UTS + Vue3 + uview-ultra + lime-request + x-pinia-s）。

## 4. 鉴权与身份体系（核心重构）

现有 `src/store/token.uts`（单/双 token）与 `src/store/user.uts`（email 用户）是**运营者模型**，C 端不使用。新增**粉丝身份模型**：

```
新增 src/store/fan.uts（FanStore，继承 PiniaStoreBase）
  state: fanToken / openid / nickname / avatar / points / accountId
  actions: setFanToken / setProfile / clear
  持久化 key: 'fan'
```

登录链路（后端已就绪，无需补接口）：

```
1. uni.login()  → code
2. POST /api/v1/miniprogram/login  { account_id, code }  → { openid }
3. POST /api/v1/shop/auth/login    { account_id, openid } → { token }
4. token 存 FanStore，后续请求头 Authorization: Bearer <token>
```

鉴权头与 401 处理：复用现有 `request.uts` 拦截器，但把「未登录跳转」目标从运营者登录页改为粉丝登录页。

## 5. API 层组织

删除 mock 文件 `src/api/foo.uts`，按后端模块一一对应建 API 客户端（复用 `http.get<T>/post<T>`，`T` 为解包后的 `data` 类型）：

```
src/api/
  auth.uts          # miniprogram/login + shop/auth/login + fan profile
  shop.uts          # 分类/商品/购物车/地址/订单/支付/退款/收藏/评论/拼团/余额套餐/文章
  points.uts        # 积分商品列表/兑换/兑换订单
  coupon.uts        # 券列表/领券/我的券
  lucky_draw.uts    # 抽奖配置/抽奖/记录
  checkin.uts       # 签到/签到记录
  vote.uts          # 投票列表/详情/投票
  seckill.uts       # 秒杀活动/抢购/我的秒杀订单
  member_card.uts   # 会员卡视图/办卡
  distribution.uts  # 分销视图/加盟/提现
```

统一类型约定：

- 响应信封 `{ code, msg, data }`，`code === 0` 成功（`request.uts` 已解包）。
- 金额一律「分」，展示用 `fenToYuan` / `formatMoney`。
- 时间一律「秒级时间戳」，展示用 `formatTime` / `relativeTime`。
- 分页：请求 `page/page_size`，响应 `{ list, total }`（后端 `sendPaged` 已是 `.ruoyi` 结构）。

## 6. 页面结构

### 6.1 TabBar（4 项）

| Tab | 路径 | 内容 |
|---|---|---|
| 首页 | `src/pages/index/index` | Banner + 商品推荐 + 场景应用宫格（签到/抽奖/券/投票/秒杀/会员卡/分销/积分商城） |
| 分类 | `src/pages/category/category`（新） | 商品分类树 + 商品列表 |
| 购物车 | `src/pages/cart/cart`（新） | 购物车列表、勾选、结算 |
| 我的 | `src/pages/me/me` | 粉丝资料、订单入口、我的券、会员卡、分销、钱包/充值、设置 |

### 6.2 分包（`src/sub`）

```
src/sub/
  shop/       # 商品详情、结算、订单列表、订单详情、支付结果、地址管理、退款、评价、拼团
  marketing/  # 积分商城、领券中心、大转盘、签到、投票、秒杀、分销
```

页面注册遵循 `tools/gen-page.mjs`（`--sub` 生成分包页），`navigationStyle: custom` + `NavBar`。

## 7. 数据流与状态

- 粉丝状态集中在 `FanStore`；购物车、订单等页面级状态用局部 `ref/reactive`，不落全局。
- 列表页统一用 `z-paging-x`（下拉刷新 + 上拉分页）。
- 登录态守卫：复用 `router/interceptor.uts`，把「需要登录」页面（购物车、结算、我的订单、营销场景）纳入登录白名单策略。
- 支付：`shop/orders/{id}/pay-params` 取 JSAPI 参数 → `uni.requestPayment` 拉起微信支付 → `pay-complete` 确认。

## 8. 后端协作项

- **`account_id` 自动识别**（已确认方案 b）：前端不显式传 `account_id`。理想实现为后端根据小程序 `appid`（`uni.getAccountInfoSync().miniProgram.appId`）反查 `account` 行，自动注入租户/账号上下文；登录接口 `miniprogram/login` 据此不再要求前端传 `account_id`。
  - 过渡期兜底：前端在 `src/utils/env.uts` 或配置文件写死单个 `account_id`，待后端自动识别就绪后移除。
- 其余 C 端接口均已在后端实现，无需新增。

## 9. 分阶段里程碑

- **P0（商城核心闭环）**：粉丝登录 → 首页/分类/商品详情 → 购物车 → 结算 → 下单 → 微信支付 → 订单列表/详情。可独立上线验证。
- **P1（营销）**：积分商城、领券中心、大转盘、签到、会员卡、钱包/充值。
- **P2（进阶）**：秒杀、投票、分销、拼团、评论、收藏、退款。

## 10. 验证计划

每个阶段完成后：

1. `uniappx-syntax-checker` 对改动 `.uts/.uvue` 语法校验通过。
2. HBuilderX 编译 `mp-weixin` 通过（Android 端语法最严，优先以 Android 编译为基准）。
3. 微信开发者工具真机/模拟器验证：登录、下单、支付回调、营销场景点击链路。
4. 后端联调：`zig build run` 启动，确认 `{ code, msg, data }` 解包、鉴权头、分页字段正确。

## 11. 风险与回滚

- **风险**：微信支付 JSAPI 需真实商户号配置（后端站点设置 `mchid/appid/serial_no/private_key`），未配置时走 mock。联调支付前需后端配置就绪。
- **风险**：`account_id` 自动识别依赖后端改造，可能阻塞 P0 登录链路。
  - 缓解：前端先以「配置写死 account_id」兜底并行开发，后端改造后切换。
- **风险**：现有 `token.uts`/`user.uts` 与新的 `FanStore` 并存，鉴权混淆。
  - 缓解：明确 C 端仅用 `FanStore`，运营者模型保留给未来可能的轻量管理入口。
- **回滚**：按阶段/文件回滚，不影响已上线功能。

## 12. 排期

- P0：登录 + 商城核心闭环（1 轮）
- P1：营销场景（1 轮）
- P2：进阶场景（1 轮）
- 后端协作项（account_id 自动识别）与 P0 并行推进。
