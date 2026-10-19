# unix → unimp（基于 unibest）迁移说明

> 目标：把 `unix/`（uni-app X）的 C 端业务功能，按 `zweq` 后端能力完整迁移到 `unimp/`（基于 unibest：uni-app Vue3 + TypeScript + Vite + UnoCSS）。
> UI/UX 不追求与 unix 像素级一致，按 unibest 的设计语言重写；功能与后端契约保持一致。

## 1. 迁移口径

- **迁移的是功能**：页面、交互流程、API 调用、登录态、支付/订单/营销能力。
- **UI/UX 重写**：统一使用 unibest 的自定义 tabbar、卡片、留白、渐变主按钮、UnoCSS 原子类。
- **不迁移**：unix 自带的 unibestX 模板演示页（`basic` / `function` / `uview-ultra` / `uiTest` / `test` / `paging`）。这些是 uni-app X 框架示例，不属于 zweq 业务能力。

## 2. 技术栈映射

| unix（uni-app X） | unimp（unibest / uni-app Vue3） |
|---|---|
| `.uvue` / `.uts` | `.vue` / `.ts` |
| `x-pinia-s` | `pinia` + `pinia-plugin-persistedstate`（持久化 key 保持 `pinia:fan` / `pinia:app`） |
| `lime-request` | `src/http/http.ts`（`uni.request` + 统一 envelope 解包） |
| `uview-ultra` | 未引入；业务页原本未使用 `up-*`，统一用原生组件 + UnoCSS |
| 手写 `pages.json` | `pages.config.ts` + 页面内 `definePage` 宏 |
| 手写 `manifest.json` | `manifest.config.ts` |
| `App.ku.uvue` 全局骨架 | `src/App.ku.vue`（`@uni-ku/root`） |
| 自定义 tabbar（uvue） | `src/tabbar/`（unocss 图标 + 自定义 tabbar） |
| `@/uni_modules/e-chart` 等 | 未使用（业务页不依赖图表） |
| `src/sub/**` 分包 | `src/pages-sub/**`（`root: pages-sub`） |
| `/src/pages/**` 路由 | `/pages/**` |
| `/src/sub/**` 路由 | `/pages-sub/**` |

## 3. 功能与页面映射

### 3.1 主包（tabbar）

| 功能 | 页面 | API |
|---|---|---|
| 首页（Banner / 金刚区 / 场景应用 / 猜你喜欢） | `src/pages/index/index.vue` | `listProducts` |
| 分类（左侧分类 + 商品） | `src/pages/category/category.vue` | `listCategories` / `listProducts` |
| 搜索 | `src/pages/search/search.vue` | `listProducts(keyword)` |
| 购物车（选中 / 数量 / 结算） | `src/pages/cart/cart.vue` | `listCart` / `updateCart` / `deleteCart` / `getProductDetail` |
| 我的（资产 / 订单角标 / 常用功能 / 营销入口 / 语言 / 退出） | `src/pages/me/me.vue` | `getFanProfile` / `getWalletBalance` / `listMyCoupons` / `getMemberCard` / `listOrders` |
| AI 智能助手（本地模拟对话） | `src/pages/ai/ai.vue` | 无（与原 unix 一致，保留 mock） |

### 3.2 分包：auth / shop

| 功能 | 页面 | API |
|---|---|---|
| 登录（微信 / H5 开发 openid） | `src/pages-sub/auth/login.vue` | `miniLogin` / `cLogin` / `getFanProfile` |
| 注册（模拟） | `src/pages-sub/auth/register.vue` | 无 |
| 商品详情（轮播 / 价格 / 规格 / 拼团 / 评论 / 收藏 / 分享） | `src/pages-sub/shop/product-detail.vue` | `getProductDetail` / `listGroupons` / `openGroupon` / `listComments` / `createComment` / `listFavorites` / `addFavorite` / `deleteFavorite` / `addCart` |
| 确认订单（地址 / 商品 / 优惠券 / 备注 / 提交） | `src/pages-sub/shop/checkout.vue` | `listCart` / `getProductDetail` / `listMyCoupons` / `createOrder` |
| 订单列表（状态筛选 / 分页 / 摘要） | `src/pages-sub/shop/order-list.vue` | `listOrders` / `orderSummaries` |
| 订单详情（支付 / 取消 / 确认收货 / 退款） | `src/pages-sub/shop/order-detail.vue` | `getOrderDetail` / `getOrderPayParams` / `payComplete` / `cancelOrder` / `confirmOrder` / `applyRefund` / `listRefunds` |
| 收货地址列表 / 新增 | `src/pages-sub/shop/address-list.vue` / `address-edit.vue` | `listAddresses` / `createAddress` |
| 我的收藏 | `src/pages-sub/shop/favorite-list.vue` | `listFavorites` / `getProductDetail` |
| 个人信息（会员 / 积分 / openid 复制） | `src/pages-sub/shop/profile.vue` | `getMemberCard` |

### 3.3 分包：marketing / scene

| 功能 | 页面 | API |
|---|---|---|
| 签到 | `src/pages-sub/marketing/checkin.vue` | `checkin` / `listCheckinRecords` |
| 领券中心 | `src/pages-sub/marketing/coupon-center.vue` | `listCoupons` / `claimCoupon` / `listMyCoupons` |
| 积分商城 | `src/pages-sub/marketing/points-mall.vue` | `listPointsProducts` / `redeemPoints` / `listPointsOrders` |
| 会员卡 | `src/pages-sub/marketing/member-card.vue` | `getMemberCard` / `openMemberCard` |
| 大转盘 | `src/pages-sub/marketing/lucky-draw.vue` | `getDrawConfig` / `draw` / `listDrawRecords` |
| 投票 | `src/pages-sub/marketing/vote.vue` | `listVotes` / `getVoteDetail` / `voteBallot` |
| 秒杀 | `src/pages-sub/marketing/seckill.vue` | `listSeckill` / `seckillRush` / `listSeckillOrders` |
| 分销 | `src/pages-sub/marketing/distribution.vue` | `getDistribution` / `joinDistribution` / `withdrawDistribution` |
| 邀请有礼 | `src/pages-sub/marketing/invite.vue` | `inviteMy` / `listInviteGifts` / `inviteBind` |
| 钱包 | `src/pages-sub/marketing/wallet.vue` | `getWalletBalance` / `listBalancePlans` / `rechargePlan` |

### 3.4 路由路径（易错）

unimp 的分包页面是**扁平文件**：`src/pages-sub/marketing/checkin.vue` → `/pages-sub/marketing/checkin`。
原 unix 的 `/src/sub/marketing/checkin/checkin` 是双层目录，迁移时**不能照搬**；首页/我的里的营销入口已统一为扁平路径，26 条路由已用脚本与 `src/pages.json` 全量校验。

### 3.5 共享能力

- **登录态**：`src/store/fan.ts`（`fanToken/openid/nickname/avatar/points`），持久化 key `pinia:fan`。
- **主题 / 语言**：`src/store/app.ts` + `src/i18n`（vue-i18n，`app/mkt/tabbar` 文案）。
- **请求**：`src/http/http.ts` 统一解包 `{code,msg,data}`；401 清登录态并跳登录页；错误默认 toast。
- **鉴权头**：`src/http/interceptor.ts` 自动注入 `Authorization: Bearer <fanToken>`。
- **自定义 tabbar**：`src/tabbar/`，4 个 tab（首页 / 分类 / 购物车 / 我的），unocss 图标 + 主题色。
- **AI 浮动入口**：`src/App.ku.vue`，tab 页显示，购物车页隐藏（避免遮挡结算栏）。
- **组件**：16 个 `fg-*` easycom 组件（NavBar / Card / EmptyView / SectionTitle / AssetCard / AddressCard / BottomBar / CouponBar / TotalBar / GoodsList / SkuSelector / CommentSection / GrouponSection / InfoCard / CartItem / UserHeader）。

### 3.6 AI 助手（已接 zigmodu AI 引擎）

- 后端：`POST /api/v1/app/ai/chat`，body `{ content }`；匿名 `user_id=0`、`tenant=1` 调 `AiService.simpleChat`（与后台 Chat / 微信自动回复复用同一 Provider 解析、配额与并发舱壁）。
- C 端走**无工具、非流式**通道：不把后台管理技能当 tools 发给模型，也避开部分 Provider 的 HTTPS SSE 解析问题；不创建 `ai_session`/`ai_message`。
- 消息上限 2000 字；配额 / 并发舱壁沿用 `AiService`；失败错误直接显示在 AI 气泡里（不再额外 toast）。
- 配置：`ZWEQ_AI_KEY_SECRET`（保存 Provider 时的主密钥，重启必须一致）+「AI 管理」里配置 OpenAI 兼容 Provider。API Key 可填裸 `sk-...`，后端会自动补 `Bearer ` 前缀。
- 本地开发已配置 DeepSeek Provider；主密钥由启动命令的 `ZWEQ_AI_KEY_SECRET` 注入（重启后端时必须保持一致，否则 Provider 密钥无法解密）。

### 3.7 PC 端手机预览

- H5 宽度 ≥ 640px 时，应用内容居中为 **430px** 手机列，两侧显示浅色背景；移动端（<640px）保持全宽。
- 固定底栏（tabbar / 购物车结算栏 / 商品底部栏 / AI 输入栏）统一加 `.app-fixed-bar`，桌面端用 `left: calc(50% - 215px); width: 430px` 对齐手机列。
- H5 原生导航（`uni-page-head .uni-page-head`）同样限制为 430px；AI 浮动入口用 `.app-fixed-float` 跟随右边界。

## 4. 迁移中发现并修正的后端契约问题

| 问题 | 原 unix 行为 | 修正 |
|---|---|---|
| 购物车改数量 | `PUT /shop/cart/{id}` 把 `quantity` 放 body，后端从 **query** 读取，导致数量永远变回 1 | `updateCart` 改为 query 传 `quantity` |
| 邀请信息 | `GET /shop/invites/my` 未带 `openid`，后端 400「缺少 openid」 | `inviteMy(openid)` 补 query 参数，邀请码正常展示 |
| 空列表契约 | 退款/地址/收藏等无数据时后端返回 `data: null`，前端按数组读 `.length` 触发渲染异常（订单详情白屏） | API 客户端统一 `?? []`；订单明细用 computed 兜底，并显示「暂无商品明细」 |

> 其余接口的请求体/查询参数已逐页与后端 handler 对齐（商品、订单、支付、地址、收藏、优惠券、积分、会员卡、分销等）。

## 5. 验证

### 5.1 静态门禁

```bash
cd unimp
pnpm type-check   # vue-tsc --noEmit，0 error
pnpm lint         # eslint src，0 error
pnpm test:run     # 24 tests passed
pnpm build:h5     # DONE Build complete
SKIP_OPEN_DEVTOOLS=true pnpm build:mp   # DONE Build complete
```

产物：
- H5：`dist/build/h5`（约 936 KB）
- 微信小程序：`dist/build/mp-weixin`（约 1.3 MB；6 个主包页 + 20 个分包页）

### 5.2 本地真后端 E2E（已验证）

启动 zweq（SQLite）：

```bash
ZWEQ_HTTP_PORT=8000 ZWEQ_JWT_SECRET=dev-secret-for-e2e-123456 ./zig-out/bin/zweq
cd unimp && pnpm dev:h5   # env/.env.development 指向 http://127.0.0.1:8000
```

H5 登录页输入测试 openid（如 `dev_test_user_001`），已跑通：

- 登录 → `pinia:fan` 持久化，刷新后仍登录
- 我的：积分 1280 / 银卡-金卡会员 / 2 张券 / 钱包 ¥266.80 / 订单角标
- 首页商品、商品详情（¥299）、加入购物车
- 购物车数量 3 → 点「+」→ 4（验证 query 修复）
- 结算：地址、商品清单、优惠券、备注 → 提交订单
- 订单详情自动 mock 支付 → 待发货；订单列表出现新订单
- 地址新增 / 选择；收藏；个人信息
- 营销页：签到、领券、积分商城、会员卡、分销、钱包、大转盘、投票、秒杀、邀请
- 根路由 `/` 正常渲染首页与自定义 tabbar

## 6. 运行

```bash
cd unimp

# H5（开发）
pnpm dev:h5

# 微信小程序（开发）
pnpm dev:mp

# 生产构建
pnpm build:h5
pnpm build:mp
```

环境变量在 `env/`：

- `VITE_SERVER_BASEURL`：默认生产地址；`env/.env.development` 覆盖为 `http://127.0.0.1:8000`
- `VITE_UNI_APPID` / `VITE_WX_APPID`：已填 unix 的 `__UNI__5198058` / `wx6d379a8c0aff3ea3`
- `VITE_AUTH_MODE=single`（C 端 fan token）

## 7. 已知限制

- **AI 助手**保留 unix 的本地模拟对话；后端目前没有 C 端聊天接口（管理端 AI provider 是另一条链路）。
- **微信支付**：`wxpay_v3` 分支保留，真机需配置 `wechat_pay_*` 站点设置；本地开发走后端 mock 支付。
- **测试数据**：种子券/秒杀/投票可能为空或过期；页面会显示对应空态，不是前端缺陷。
- **H5 测试登录**仅在 `development` 显示；生产 H5 请走微信 OAuth/小程序登录链路。
- unix 的框架演示页（basic/function/uview-ultra 等）未迁移。
