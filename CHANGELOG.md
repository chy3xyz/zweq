# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- **钱的正确性（并发竞态/事务）**：支付回调 `markOrderPaid` 改条件更新（`WHERE status='pending'`），重复回调幂等不再重复入账；`completeRecharge` 两写包进同一事务；积分兑换 `decrementStock` 改原子 increment+`RawArgs` 守卫防超卖，`redeem` 三写改补偿流（失败按相反顺序回补）；店铺 `markPaid`/`cancelOrder`/`auditRefund` 幂等+事务化（条件更新 affected 语义：已终态幂等、归属不符 NotFound），消除重复分佣/双回滚库存/重复审核；秒杀 `rush` 落单失败回补库存；`setDefaultAddress` 两写改单语句 CASE 翻转消除双默认。
- **越领/超发**：任务 `claimNext` 检查 affected（多 worker 不再重复执行）；`member_card.adjustPoints` 两次 increment 合并单条+`points >= ?` 下限守卫；拼团 `joinGroupon` 下单前满员拦截。
- **越权（IDOR）**：购物车/地址写操作 WHERE 加 openid 归属；`pickupOrder` 加 tenant；C 端 6 处 store 查询补 tenant 过滤（秒杀活动/积分商品/投票/地址快照/拼团/下单商品归属）。
- **静默失败**：邮件任务 SMTP 失败走既有重试链路（不再记成功丢信）；分销台账/清理 job/cleanup 全部补 `log.err`；27 个 api.zig 约 100 处 `@errorName` 内部错误名不再泄漏给用户。
- **前端**：业务错误（400/404/500）的中文 msg 现在真正展示给用户（client.ts 非 2xx envelope 解包，此前只显示 axios 英文兜底）；Points 页三 modal 共享提交状态串错（拆为独立 signal）；envelope 泛型 helper 上移到 `client.ts`（约 30 个模块 -463 行样板）。

### Added
- **安全**：fan 经济接口（领券/抽奖/兑换/秒杀/提现/开卡/签到/投票）per-openid 限流（10/5/3 次每分档）+ fail-open/closed 统一策略；`shop_invite_record` 加 `UNIQUE(tenant_id, invitee_openid)`，`bindInvite` 改 `SaveIgnore` 幂等；checkin/member_account/distributor/vote_record 补唯一索引（并发撞键映射为已签/已开卡/已加盟/已投票）；`draw_record` 加 `draw_day` 列（不落唯一索引——daily_limit 可配 >1）。
- **可观测性**：`/metrics` 新增 `zweq_tasks_processed_total`/`zweq_tasks_failed_total`；Dispatcher tick/scheduled/单任务耗时日志。
- **OpenAPI**：fan 公共 API + payment 共 34 路由补参数注解（45 个参数进 openapi.json），模块顶部 doc comment 承载中文契约（summary/body 结构受 zigmodu `RouteMeta` 字段限制，待库扩展）。
- CI 前端 job（`npm run typecheck` + `vitest`）。

### Changed
- 依赖升级（零 breaking，代码零改动即适配）：zent **v0.34.0 → v0.37.0**（主站 + `zweq-cloud`；`zig build` / `zig build test` 93/93 全绿，真实库启动迁移通过）。新能力可用：连接池 `max_wait_ms` 真正阻塞等待（默认 0 = 旧语义）、嵌套预加载每层一次查询（消 N+1）、`StorageKey` 字段↔列名映射、`BulkInsert` 按参数上限分片、`In/NotIn/IsNull/HasPrefix/ContainsFold` 等类型化谓词、边写入（`AddEdgeIDs`/`SetEdgeIDs`/`ClearEdge`）、outbox 认领式派发、迁移默认加锁 + checksum 校验。本项目未用 outbox/BulkInsert/预加载，`UPGRADING` §10 的 outbox 迁移与 `createAllTables` 签名变更均不适用。
- 依赖升级（零 breaking，代码零改动即适配）：zigmodu **v0.15.35 → v0.15.37**（`zweq-cloud` 同步从 v0.15.24 直升）。
- RBAC 闭环：`RolePermission` 关联表 + `collectPermissionCodes`（user.admin / 角色 code / module:action）；`GET /auth/me` 返回 `permissions`；角色权限 API `GET|POST|DELETE /roles/{id}/permissions`；前端菜单按 `canAccessAdmin` 隐藏。
- 小程序商城 C 端登录：`wx.login` → `miniprogram/login`（公开）→ `shop/auth/login` fan JWT；`shopSession` store 替换 `DEMO_OPENID`。
- CI 增加 `zig build lint-size` 门禁。
- 权限目录种子（`permission_catalog` + `permission_seed`）：启动时写入全部 `module:action` 权限码，founder/admin 全绑，operator 默认只读。
- 管理后台「角色权限」页（`/roles`）：角色 CRUD、权限码管理、角色授权勾选、用户绑角色。
- 侧栏菜单细粒度映射（`navItems.ts` + `PermissionGate`）；后端路由 `admin` 改为 `{module}:read|write`。

### Changed
- 依赖升级（零 breaking，代码零改动即适配）：zent **v0.33.0 → v0.34.0**（主站 + `zweq-cloud`；清 `.zig-cache` 后 `zig build` / `zig build test` 全绿）。新能力可用：`sql.RawArgs`、聚合助手（`SumOrZero`/`Aggregate*`）、`SaveOrUpdateOnWith`、`ForUpdateWith`、`sql_scan.queryAll`/`queryOne`。
- 依赖升级（零 breaking，代码零改动即适配）：zigmodu **v0.15.34 → v0.15.35**、zent **v0.32.2 → v0.33.0**（`zig build` + `zig build test` 全绿）。
- 巨型文件按子域拆分（正文逐字搬运，语义零变更；全部源文件 ≤ 1200 行，新增 `zig build lint-size` 门禁）：
  - `src/tests.zig`（3962 行）→ `src/tests/` 共 10 个按域测试文件 + `common.zig` 夹具，原文件保留为聚合入口。
  - `shop/persistence.zig`（1839 行）→ 门面（91 行，`persist.XxxRow` / `ShopStore.init` 引用面不变；方法调用迁移为 `store.<catalog|trade|marketing|content>.xxx`）+ `rows.zig` + 4 个子域 store。
  - `shop/api.zig`（1922 行）→ 门面（~360 行：路由表/注册函数/init）+ `handlers/{catalog,trade,marketing,content}.zig` 混入式处理器 + `api_dto.zig` 统一 DTO 与映射器。适配本版 Zig 已移除的 `usingnamespace`：跨片段宿主成员经 `ApiT.` 前缀调用。
- **修正**：上一条依赖升级在本机 `.zig-cache` 陈旧解析图下验证过一次，实际编译的仍是旧版。已清除缓存重验：构建与全量测试均在 **zent v0.32.1 + zigmodu v0.15.32** 真实通过（92/92），升级结论不变、代码无需改动。
- 依赖升级（纯新增/修复版本，零 breaking）：zigmodu **v0.15.22 → v0.15.32**、zent **v0.29.4 → v0.32.1**。获得：zent Interceptor 运行时查询拦截、`field.Decimal` 精确金额列、`SaveOrUpdateOn`/`SaveIgnore` upsert、PreparedCache 字节级 key 防碰撞；zigmodu 读写分离（`Client.withReplica`）、HTTP header 上限（431 DoS 防护）、OTLP/Vault HTTPS。
- 依赖切换到 git tag 引用并升级：zigmodu **v0.15.22**、zent **v0.29.4**、zwechat **v0.2.0**（内部 httpz → zhttp v0.6.0）。
- 适配 zent v0.29.4 破坏性变更：`Query.Sum` 返回类型 `i64 → f64`（AI 配额聚合改用 `@intFromFloat`）。
- 适配 zigmodu v0.15.22 线程安全修复：`/metrics` 渲染改用 `HttpMetricsCollector.snapshot()`（原先裸读共享字段存在数据竞争）。

## [0.1.0] - 2026-08-06

### Added — 微信运营全链路
- **账号管理** `account`：公众号 / 小程序 CRUD + `account_wechat` 微信配置（secret 脱敏返回）。
- **模块注册表** `module`：模块 CRUD + 账号↔模块绑定。
- **RBAC** `permission`：role / permission / user_role。
- **粉丝** `member`：fan（openid / unionid）同步与管理。
- **关键词回复** `rule`：rule / rule_keyword / rule_reply。
- **素材** `material`：图文 news + 图片 / 语音 / 视频素材。
- **消息引擎** `message`：`GET/POST /wx/{token}` 签名校验、echostr 握手、明文 / AES 解析、关键词匹配、文本 / 图文被动回复（安全模式 AES 加密回包）。
- **支付** `payment`：充值订单 / 钱包 / 提现，channel=mock。
- **站点设置** `setting`：KV 存储，管理员写入。
- **云服务** `cloud`：授权码 + 应用市场。
- **H5 BFF** `app_bff`：移动端薄层。
- 管理后台（SolidJS）页面：账号、自动回复、粉丝、充值支付、模块、云服务、消息日志、素材库。

### Added — 平台底座（复用 zenaipa 并加固）
- 认证：注册 / 登录 / 邮箱验证 / 忘记重置，JWT + Argon2id，登录限流与防枚举。
- 后台任务队列（持久化 + 重试退避）、文件上传、通知收件箱、可配置邮件模板。
- 审计日志（actor / action / keyword 筛选）、概览面板、健康检查、Prometheus `/metrics`、`x-trace-id`。
- 多租户：物理 `app_id` 行隔离，租户随 JWT `aud` claim，跨租户管理筛选。

### Added — 生产化
- **微信支付 v3**：`prepay` 真实 JSAPI 统一下单（`zwechat.pay.v3.signer`），`POST /api/v1/pay/v3/notify` 平台证书验签 + AES-256-GCM 解密 + 幂等入账。
- **AI Provider**：OpenAI 兼容端点，密钥 AES-GCM 加密落库（`ZWEQ_AI_KEY_SECRET`）。
- **静态托管**：单二进制服务 SolidJS SPA（`ZWEQ_STATIC_DIR`）。
- **Docker**：Dockerfile + docker-compose（postgres + zweq）。
- **Postgres 模式**：`ZWEQ_DB_DRIVER=postgres` + `ZWEQ_PG_CONNINFO`，启动自动迁移。

### Security
- JWT 凭据版本化：改密吊销旧令牌。
- 生产 fail-closed：显式 `ZWEQ_JWT_SECRET` / `ZWEQ_AI_KEY_SECRET` 必需。
- 审计日志保留期清理（`ZWEQ_AUDIT_RETENTION_DAYS`）。
- `/metrics` IP 白名单（`ZWEQ_METRICS_ALLOW_IPS`）。
- 优雅停机（SIGINT / SIGTERM）。

[0.1.0]: https://github.com/chy3xyz/zweq/releases/tag/v0.1.0
