# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
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
