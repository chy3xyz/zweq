<div align="center">

# zweq

**A multi-tenant WeChat business platform — one binary, zero PHP.**
管理公众号 / 小程序、粉丝、关键词回复、图文素材、充值支付与 AI 客服的一体化运营后台。

[![Zig](https://img.shields.io/badge/Zig-0.17-orange?logo=zig&logoColor=white)](https://ziglang.org)
[![SolidJS](https://img.shields.io/badge/Frontend-SolidJS-2c4f7c?logo=solid&logoColor=white)](https://www.solidjs.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

**English** | [**简体中文**](README.zh-CN.md)

</div>

---

zweq is a production-grade **multi-tenant WeChat operations platform** written in Zig.
It runs the entire stack — backend, admin console and H5 front-end — as a **single
static binary** and ships out of the box with the workflows every WeChat operator needs:

- **Accounts** — bind Official Accounts / Mini Programs, manage their credentials and
  verification state
- **Fans** — automatic fan synchronization on callback events
- **Keyword replies** — a rule engine that answers messages instantly, with text / news
  and AES-encrypted (safe-mode) replies
- **Materials** — rich-text news, images, voice and video with WeChat `media_id`
- **Recharge & wallet** — real WeChat Pay **v3 JSAPI** prepay + platform-certificate
  verified notify webhook, wallets and withdrawals
- **AI assistant** — plug in any OpenAI-compatible provider for auto-replies, an
  agentic chat with human approval for write actions, and a rolling daily quota
- **Cloud marketplace** — license codes and a module registry so you can enable /
  bind features per tenant

Every tenant is a WeChat business: rows are isolated by a physical `app_id` column,
tenants ride in the JWT `aud` claim, and platform admins get cross-tenant tooling.

## Why zweq?

- **One binary, full stack.** The Zig server serves the compiled SolidJS SPA — deploy
  one artifact, no Node runtime, no PHP, no web server configuration.
- **WeChat-native.** Callback verification, AES message (de)serialization and WeChat
  Pay v3 signing / decryption are handled by [zwechat](https://github.com/chy3xyz/zwechat),
  a battle-tested WeChat SDK in pure Zig.
- **Schema-as-code.** The whole database (35+ tables) is declared in Zig and migrates
  automatically at startup — SQLite for development, PostgreSQL for production, one
  environment variable to switch.
- **Multi-tenant by design.** Physical `app_id` column, tenant-aware JWT, per-module
  bindings — built for SaaS from day one.
- **AI-first operations.** Keyword miss → LLM auto-reply, with provider keys encrypted
  at rest (AES-256-GCM) and human-in-the-loop approvals for write skills.
- **Safe by default.** JWT credential versioning revokes old sessions on password
  change, audit log retention, IP-allowlisted `/metrics`, redacted access logs, and
  fail-closed production secrets.

## ✨ Features

### WeChat operations
- **Account management** — Official Account / Mini Program CRUD with masked secrets,
  per-account WeChat config (`appid` / `token` / `encoding_aes_key`) and verification
  state
- **Callback engine** — `GET/POST /wx/{token}` signature verification, `echostr`
  handshake, plain / AES message parsing, fan sync on follow/unfollow, then keyword
  matching → passive text / news reply (supports AES-safe-mode responses)
- **Keyword rules** — keyword → reply rules with per-account binding
- **Fan management** — synced fans with account context
- **Materials** — rich-text news plus image / voice / video media, WeChat `media_id`
  ready
- **Message logs** — every callback / outbound message audited, filterable by account

### Commerce & payments
- **Wallets** — per-user balances with ledger-backed mutations
- **Recharge** — WeChat Pay **v3** JSAPI unified order via the real `signer` header,
  idempotent credit on verified notify
- **Withdrawals** — request / review flow, ready for WeChat Pay v3 transfer
- Configures via site settings (`mchid` / `appid` / `serial_no` / `private_key` /
  `notify_url`); missing config fails closed, mock mode for development

### Multi-tenancy & admin
- Physical `app_id` row isolation; tenant-aware JWT; cross-tenant filtering for admins
- **RBAC** — roles / permissions / user-role binding
- **Site settings** — key-value store with admin-gated writes
- **Module registry** — enable & bind modules per account
- **Cloud marketplace** — license-code validation + package distribution

### Platform backbone (reused & hardened)
- Auth: register / login / email verification / forgot-reset, Argon2id password
  hashing, login rate limiting
- Background task queue with retry/backoff, durable rows
- File uploads with per-user access control
- Notifications inbox, configurable email templates, audit log with retention policy
- Dashboard, health probes, Prometheus `/metrics`, `x-trace-id` tracing
- Graceful shutdown (SIGINT/SIGTERM)

### AI assistant
- OpenAI-compatible providers, API keys encrypted at rest
- Agent chat with message history, human-approval queue for write skills
- Auto-reply fallback to the LLM when keyword rules miss (`wechat_ai_auto_reply=1`)
- Run audit + Prometheus agent metrics, rolling 24h quota per user

## 🧱 Tech Stack

| Layer | Technology |
| --- | --- |
| Backend | [Zig](https://ziglang.org) 0.17 · [zigmodu](https://github.com/chy3xyz/zigmodu) (HTTP, security, task queue) · [zent](https://github.com/chy3xyz/zent) (ORM, schema-as-code, migrations) |
| WeChat SDK | [zwechat](https://github.com/chy3xyz/zwechat) (callback, AES, Pay v2/v3, mTLS over [zhttp](https://github.com/chy3xyz/zhttp)) |
| Frontend | [SolidJS](https://www.solidjs.com) · TypeScript · [Rsbuild](https://rsbuild.dev) · Tailwind CSS 4 · DaisyUI |
| Database | SQLite (default) ↔ PostgreSQL (one env var) |

## 🏗️ Architecture

```
Browser (SolidJS SPA, served by the same binary)
        │  /api/v1 (JSON envelope: { code, msg, data })
        ▼
Zig HTTP server (zigmodu)
        │  middleware: security headers → access log → CORS → JWT (tenant) → metrics
        ▼
Module APIs ──► Services ──► Persistence (zent client) ──► SQLite / PostgreSQL
        │
        ├── /wx/{token}   callback engine (zwechat: signature + AES)
        ├── Task dispatcher (durable queue, retries, housekeeping)
        └── WeChat Pay v3 gateway (signer → JSAPI prepay, notify verify → credit)
```

Every domain follows the same layout —
`model` (schema) → `persistence` (queries) → `service` (business logic) →
`api` (HTTP handlers) → `module` (lifecycle & dependencies). See
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the deep dive.

## 🚀 Quick Start

### Requirements

- [Zig](https://ziglang.org/download/) **0.17** (managed via [zigup](https://github.com/tristanisham/zigup))
- [Node.js](https://nodejs.org) **20+** + npm (frontend only)
- SQLite is linked in — no database install needed for development

### 1. Build & run the backend

```bash
zig build run
```

The server starts on `http://localhost:8000` with a local `zweq.db` (SQLite).

### 2. Create the first administrator

```bash
zig build
zig-out/bin/zweq-admin create-admin --email admin@example.com --password 'YourPass123' --name Boss
```

### 3. Run the admin console (development)

```bash
cd web
npm install
npm run dev
```

Open <http://localhost:3001> and sign in — the dev server proxies `/api` to the Zig
backend. In production the compiled SPA is served by the Zig binary itself
(`web/dist`), so one artifact runs everything.

## ⚙️ Configuration

All settings are environment variables with the `ZWEQ_` prefix
(defaults live in [`src/config.zig`](src/config.zig)).

| Variable | Default | Description |
| --- | --- | --- |
| `ZWEQ_HTTP_PORT` | `8000` | HTTP listen port |
| `ZWEQ_DB_DRIVER` | `sqlite` | `sqlite` or `postgres` |
| `ZWEQ_SQLITE_PATH` | `zweq.db` | SQLite file path |
| `ZWEQ_PG_CONNINFO` | localhost:5432 | PostgreSQL connection string |
| `ZWEQ_JWT_SECRET` | dev default | HMAC key for JWT (must override in production) |
| `ZWEQ_STATIC_DIR` | `web/dist` | SPA static directory served by the binary |
| `ZWEQ_CORS_ORIGINS` | `*` | Comma-separated allow-list (`*` dev only) |
| `ZWEQ_SMTP_*` | _(empty)_ | SMTP for verification / reset mail (console sink in dev) |
| `ZWEQ_UPLOAD_DIR` | `uploads` | Local uploads directory |
| `ZWEQ_AI_KEY_SECRET` | _(empty)_ | Master key encrypting stored AI provider keys |
| `ZWEQ_AI_DAILY_RUN_LIMIT` | `100` | Rolling 24h agent runs per user |
| `ZWEQ_AUDIT_RETENTION_DAYS` | `90` | Audit-log retention window |
| `ZWEQ_METRICS_ALLOW_IPS` | _(empty)_ | IP allow-list for `/metrics` (empty = all) |

WeChat Pay v3 and AI providers are configured in the admin UI (site settings), not env
vars — keys are stored encrypted or masked respectively.

## 🛡️ Security

- Argon2id password hashing; JWT HS256 with **credential versioning** (password change
  revokes old tokens)
- Callback endpoints verify the WeChat signature and support AES safe mode
- Pay v3 notify is verified against the WeChat platform certificate (RSA-SHA256) and
  decrypted with AES-256-GCM; credit is idempotent
- AI provider keys encrypted at rest (AES-256-GCM)
- Admin routes enforce roles server-side (`requireAdmin` against the DB, not the JWT)
- Rate-limited auth, redacted access logs, security headers, CORS allow-list
- Production fails closed: explicit `ZWEQ_JWT_SECRET` and `ZWEQ_AI_KEY_SECRET` required
  for critical paths

Report a vulnerability via [SECURITY.md](SECURITY.md).

## 📡 API Overview

Every endpoint returns `{ code, msg, data }`; `code === 0` means success.

| Area | Sample endpoints |
| --- | --- |
| Auth | `POST /api/v1/auth/register` · `/login` · `/forgot-password` · `GET /me` |
| Accounts | `GET/POST /api/v1/accounts` · `PUT/DELETE /api/v1/accounts/{id}` · `GET/PUT /accounts/{id}/wechat` |
| Rules | `GET/POST /api/v1/rules` · `PUT/DELETE /api/v1/rules/{id}` |
| Fans | `GET /api/v1/fans?account_id=` |
| Materials | `GET/POST/PUT/DELETE /api/v1/materials/{news,files}` |
| Payments | `POST /api/v1/payments/recharge` · `GET /api/v1/wallet` · `POST /api/v1/withdraws` |
| Messages | `GET /api/v1/message-logs?account_id=` · `GET/POST /wx/{token}` (public callback) |
| Modules / Cloud | `GET/POST /api/v1/modules` · `/api/v1/cloud/licenses` · `/market` |
| RBAC | `GET/POST/PUT/DELETE /api/v1/roles` · `/permissions` · `/users/{id}/roles` |
| Settings | `GET /api/v1/settings` · `PUT/DELETE /api/v1/settings/{key}` |
| Platform | `GET /api/v1/system/dashboard` · `/audit-logs` · `/tasks` · `/files` · `/notifications` · `/email-templates` |
| AI | `POST /api/v1/ai/sessions/{id}/chat` · `GET /ai/providers` · `/ai/approvals` · `/ai/runs` |
| Ops | `GET /health/live` · `/api/v1/health/ready` · `/metrics` |

## 🧪 Testing

```bash
# Backend: unit + integration tests (in-memory SQLite, no network)
# stores, services, JWT/multi-tenancy, WeChat callback round-trips,
# Pay v3 signer + notify verification (tamper-rejected), audit, RBAC, HTTP flow
zig build test

# Frontend: type check and production build
cd web && npm run typecheck && npm run build
```

## 🚢 Deployment

- **Single artifact**: build the SPA (`cd web && npm run build`) then ship the Zig
  binary — it serves the UI, API and callbacks on one port. TLS terminates at a
  reverse proxy (Nginx / Caddy / LB).
- **PostgreSQL**: set `ZWEQ_DB_DRIVER=postgres` + `ZWEQ_PG_CONNINFO`; the schema
  migrates on startup (a Dockerfile and `docker-compose.yml` with Postgres are included).
- **Secrets**: always override `ZWEQ_JWT_SECRET`; set `ZWEQ_AI_KEY_SECRET` before
  storing AI providers.
- **WeChat Pay**: fill the v3 credentials (mchid / appid / serial_no / private_key /
  notify_url) in site settings — `prepay` becomes real JSAPI and `POST /api/v1/pay/v3/notify`
  handles verified callbacks.

## 🗺️ Roadmap

- Real WeChat Pay v3 transfers for withdrawals
- Native Mini Program session / QR-code flows
- More AI provider integrations + per-fan conversation memory
- Object storage backend for files, horizontal scaling

## 🤝 Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for conventions,
the module layout and how to run the test suite. Please read the
[Code of Conduct](CODE_OF_CONDUCT.md) first.

## 📄 License

[MIT](LICENSE) © zweq contributors
