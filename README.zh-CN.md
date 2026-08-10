<div align="center">

# zweq

**多商户微信业务平台 —— 一个二进制，零 PHP。**
公众号 / 小程序、粉丝、关键词回复、图文素材、充值支付与 AI 客服的一体化运营后台。

[![Zig](https://img.shields.io/badge/Zig-0.17-orange?logo=zig&logoColor=white)](https://ziglang.org)
[![SolidJS](https://img.shields.io/badge/Frontend-SolidJS-2c4f7c?logo=solid&logoColor=white)](https://www.solidjs.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

[**English**](README.md) | **简体中文**

</div>

---

zweq 是一个用 Zig 编写的**多商户微信运营平台**。后端、管理后台与 H5 前端以**单个静态
二进制**交付，开箱即覆盖微信运营者的日常闭环：

- **账号管理** —— 绑定公众号 / 小程序，管理凭据与认证状态
- **粉丝管理** —— 回调事件自动同步粉丝
- **关键词回复** —— 规则引擎即时应答，支持文本 / 图文与 AES 加密（安全模式）回包
- **素材库** —— 图文、图片、语音、视频素材，对接微信 `media_id`
- **充值支付** —— 真实**微信支付 v3** JSAPI 统一下单 + 平台证书验签回调，钱包与提现
- **AI 助手** —— 任意 OpenAI 兼容 Provider 自动回复、带人工审批的智能体对话、24h 滚动配额
- **云市场** —— 授权码与模块注册表，按租户启用 / 绑定功能

每个租户即一个微信生意：行级数据按物理列 `app_id` 隔离，租户随 JWT 的 `aud` claim
传递，平台管理员拥有跨租户运维能力。

## 为什么选择 zweq

- **一个二进制，全栈交付。** Zig 服务端直接托管编译好的 SolidJS SPA —— 只部署一个
  产物，无需 Node 运行时、无需 PHP、无需另配 Web 服务器。
- **微信原生。** 回调验签、AES 消息加解密、微信支付 v3 签名 / 解密全部由
  [zwechat](https://github.com/chy3xyz/zwechat)（纯 Zig 微信 SDK）承担。
- **Schema-as-code。** 全库 35+ 张表全部用 Zig 声明，启动时自动迁移——开发用 SQLite，
  生产切 PostgreSQL，只改一个环境变量。
- **天生多租户。** 物理 `app_id` 列 + 租户感知 JWT + 按模块绑定，从第一天就为 SaaS 而设计。
- **AI 优先的运营。** 关键词未命中 → LLM 自动回复；Provider 密钥 AES-256-GCM 加密落库；
  写类技能走人工审批。
- **安全默认。** JWT 凭据版本化（改密吊销旧会话）、审计日志保留期、`/metrics` IP 白名单、
  脱敏访问日志、生产 fail-closed。

## ✨ 功能特性

### 微信运营
- **账号管理** —— 公众号 / 小程序 CRUD，secret 脱敏返回，按账号配置微信参数
  （`appid` / `token` / `encoding_aes_key`）与认证状态
- **回调引擎** —— `GET/POST /wx/{token}` 签名校验、`echostr` 握手、明文 / AES 解析，
  关注 / 取关粉丝同步 → 关键词匹配 → 文本 / 图文被动回复（支持安全模式 AES 加密回包）
- **关键词规则** —— 关键词 → 回复规则，按账号绑定
- **粉丝管理** —— 回调同步的粉丝列表，带账号上下文
- **素材库** —— 图文素材 + 图片 / 语音 / 视频素材，对接 `media_id`
- **消息日志** —— 每条回调 / 出站消息留痕，按账号筛选

### 电商与支付
- **钱包** —— 每用户余额，账本化增减
- **充值** —— 微信支付 **v3** JSAPI 统一下单（真实 `signer` 签名头），验签回调幂等入账
- **提现** —— 申请 / 审核流程，预留微信支付 v3 转账
- 站点设置配置 `mchid` / `appid` / `serial_no` / `private_key` / `notify_url`；
  缺配置 fail-closed，开发环境提供 mock

### 多租户与管理
- 物理 `app_id` 行级隔离；租户感知 JWT；管理员跨租户筛选
- **RBAC** —— 角色 / 权限 / 用户-角色绑定
- **站点设置** —— KV 存储，写入仅限管理员
- **模块注册表** —— 按账号启用与绑定模块
- **云市场** —— 授权码校验 + 应用包分发

### 平台底座（复用并加固）
- 认证：注册 / 登录 / 邮箱验证 / 忘记-重置，Argon2id 密码哈希，登录限流
- 后台任务队列：持久化 + 重试退避
- 文件上传：按用户隔离访问
- 通知收件箱、可配置邮件模板、带保留期的审计日志
- 概览面板、健康检查、Prometheus `/metrics`、`x-trace-id` 追踪
- 优雅停机（SIGINT/SIGTERM）

### AI 助手
- OpenAI 兼容 Provider，API 密钥加密存储
- 智能体对话 + 消息历史，写技能走人工审批队列
- 关键词未命中自动回退 LLM 回复（`wechat_ai_auto_reply=1`）
- 运行审计 + Prometheus agent 指标，每用户 24h 滚动配额

## 🧱 技术栈

| 层 | 技术 |
| --- | --- |
| 后端 | [Zig](https://ziglang.org) 0.17 · [zigmodu](https://github.com/chy3xyz/zigmodu)（HTTP、安全、任务队列）· [zent](https://github.com/chy3xyz/zent)（ORM、Schema-as-code、迁移） |
| 微信 SDK | [zwechat](https://github.com/chy3xyz/zwechat)（回调、AES、支付 v2/v3、基于 [zhttp](https://github.com/chy3xyz/zhttp) 的 mTLS） |
| 前端 | [SolidJS](https://www.solidjs.com) · TypeScript · [Rsbuild](https://rsbuild.dev) · Tailwind CSS 4 · DaisyUI |
| 数据库 | SQLite（默认）↔ PostgreSQL（一个环境变量切换） |

## 🏗️ 架构

```
浏览器（SolidJS SPA，由同一个二进制托管）
        │  /api/v1（JSON 信封：{ code, msg, data }）
        ▼
Zig HTTP 服务（zigmodu）
        │  中间件：安全头 → 访问日志 → CORS → JWT（租户）→ 指标
        ▼
模块 API ──► 服务 ──► 持久化（zent client）──► SQLite / PostgreSQL
        │
        ├── /wx/{token}  回调引擎（zwechat：签名 + AES）
        ├── 任务调度器（持久化队列、重试、定期清理）
        └── 微信支付 v3 网关（signer → JSAPI 下单，验签回调 → 入账）
```

每个领域模块遵循同一结构 ——
`model`（schema）→ `persistence`（查询）→ `service`（业务逻辑）→
`api`（HTTP handler）→ `module`（生命周期与依赖）。深度剖析见
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 🚀 快速开始

### 环境要求

- [Zig](https://ziglang.org/download/) **0.17**（建议用 [zigup](https://github.com/tristanisham/zigup) 管理）
- [Node.js](https://nodejs.org) **20+** + npm（仅前端）
- SQLite 已静态链接，开发无需安装数据库

### 1. 构建并启动后端

```bash
zig build run
```

服务启动于 `http://localhost:8000`，使用本地 `zweq.db`（SQLite）。

### 2. 创建首个管理员

```bash
zig build
zig-out/bin/zweq-admin create-admin --email admin@example.com --password 'YourPass123' --name Boss
```

### 3. 运行管理后台（开发）

```bash
cd web
npm install
npm run dev
```

打开 <http://localhost:3001> 登录 —— 开发服务器将 `/api` 代理到 Zig 后端。生产环境
由 Zig 二进制直接托管编译好的 SPA（`web/dist`），单产物跑全部。

## ⚙️ 配置

所有配置均为 `ZWEQ_` 前缀环境变量（默认值见 [`src/config.zig`](src/config.zig)）。

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `ZWEQ_HTTP_PORT` | `8000` | HTTP 监听端口 |
| `ZWEQ_DB_DRIVER` | `sqlite` | `sqlite` 或 `postgres` |
| `ZWEQ_SQLITE_PATH` | `zweq.db` | SQLite 文件路径 |
| `ZWEQ_PG_CONNINFO` | localhost:5432 | PostgreSQL 连接串 |
| `ZWEQ_JWT_SECRET` | 开发默认值 | JWT HMAC 密钥（生产必须覆盖） |
| `ZWEQ_STATIC_DIR` | `web/dist` | 二进制托管的 SPA 静态目录 |
| `ZWEQ_CORS_ORIGINS` | `*` | 逗号分隔白名单（`*` 仅限开发） |
| `ZWEQ_SMTP_*` | （空） | 验证 / 重置邮件 SMTP（开发用控制台兜底） |
| `ZWEQ_UPLOAD_DIR` | `uploads` | 本地上传目录 |
| `ZWEQ_AI_KEY_SECRET` | （空） | 加密 AI Provider 密钥的主密钥 |
| `ZWEQ_AI_DAILY_RUN_LIMIT` | `100` | 每用户 24h 滚动运行上限 |
| `ZWEQ_AUDIT_RETENTION_DAYS` | `90` | 审计日志保留天数 |
| `ZWEQ_METRICS_ALLOW_IPS` | （空） | `/metrics` IP 白名单（空 = 全部） |

微信支付 v3 与 AI Provider 在后台「站点设置」中配置（非环境变量），密钥分别加密或
脱敏存储。

## 🛡️ 安全

- Argon2id 密码哈希；JWT HS256 + **凭据版本化**（改密吊销旧令牌）
- 回调端点校验微信签名，支持 AES 安全模式
- 支付 v3 回调按微信平台证书验签（RSA-SHA256），AES-256-GCM 解密，入账幂等
- AI Provider 密钥加密落库（AES-256-GCM）
- 管理路由服务端强制角色（`requireAdmin` 查库而非仅信 JWT）
- 认证限流、脱敏访问日志、安全响应头、CORS 白名单
- 生产 fail-closed：关键路径强制显式 `ZWEQ_JWT_SECRET` 与 `ZWEQ_AI_KEY_SECRET`

发现漏洞请按 [SECURITY.md](SECURITY.md) 上报。

## 📡 API 一览

所有端点返回 `{ code, msg, data }`；`code === 0` 即成功。

| 领域 | 示例端点 |
| --- | --- |
| 认证 | `POST /api/v1/auth/register` · `/login` · `/forgot-password` · `GET /me` |
| 账号 | `GET/POST /api/v1/accounts` · `PUT/DELETE /api/v1/accounts/{id}` · `GET/PUT /accounts/{id}/wechat` |
| 规则 | `GET/POST /api/v1/rules` · `PUT/DELETE /api/v1/rules/{id}` |
| 粉丝 | `GET /api/v1/fans?account_id=` |
| 素材 | `GET/POST/PUT/DELETE /api/v1/materials/{news,files}` |
| 支付 | `POST /api/v1/payments/recharge` · `GET /api/v1/wallet` · `POST /api/v1/withdraws` |
| 消息 | `GET /api/v1/message-logs?account_id=` · `GET/POST /wx/{token}`（公开回调） |
| 模块 / 云 | `GET/POST /api/v1/modules` · `/api/v1/cloud/licenses` · `/market` |
| RBAC | `GET/POST/PUT/DELETE /api/v1/roles` · `/permissions` · `/users/{id}/roles` |
| 设置 | `GET /api/v1/settings` · `PUT/DELETE /api/v1/settings/{key}` |
| 平台 | `GET /api/v1/system/dashboard` · `/audit-logs` · `/tasks` · `/files` · `/notifications` · `/email-templates` |
| AI | `POST /api/v1/ai/sessions/{id}/chat` · `GET /ai/providers` · `/ai/approvals` · `/ai/runs` |
| 运维 | `GET /health/live` · `/api/v1/health/ready` · `/metrics` |

## 🧪 测试

```bash
# 后端：单元 + 集成测试（内存 SQLite，无网络）
# 覆盖存储、服务、JWT/多租户、微信回调往返、支付 v3 签名与验签（含篡改拒绝）、
# 审计、RBAC、HTTP 流程
zig build test

# 前端：类型检查与生产构建
cd web && npm run typecheck && npm run build
```

## 🚢 部署

- **单产物**：先构建 SPA（`cd web && npm run build`），再部署 Zig 二进制 —— 它在一个
  端口上同时提供 UI、API 与回调。TLS 在反向代理（Nginx / Caddy / LB）终止。
- **PostgreSQL**：设置 `ZWEQ_DB_DRIVER=postgres` + `ZWEQ_PG_CONNINFO`，启动自动迁移
  （仓库内附 Dockerfile 与含 Postgres 的 `docker-compose.yml`）。
- **密钥**：生产始终覆盖 `ZWEQ_JWT_SECRET`；存 AI Provider 前先设 `ZWEQ_AI_KEY_SECRET`。
- **微信支付**：在站点设置填入 v3 凭据（mchid / appid / serial_no / private_key /
  notify_url）—— `prepay` 即走真实 JSAPI，`POST /api/v1/pay/v3/notify` 处理验签回调。

## 🗺️ 路线图

- 提现实走微信支付 v3 转账
- 小程序原生会话与二维码流程
- 更多 AI Provider 接入 + 粉丝级对话记忆
- 对象存储后端与水平扩展

## 🤝 参与贡献

欢迎提交 Issue 与 Pull Request！约定、模块结构、测试运行方式见
[CONTRIBUTING.md](CONTRIBUTING.md)，请先阅读[行为准则](CODE_OF_CONDUCT.md)。

## 📄 开源许可

[MIT](LICENSE) © zweq contributors
