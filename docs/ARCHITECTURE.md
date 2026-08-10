# Architecture

> Status: living document — update as the codebase evolves.
> "微擎" in the codebase history refers to a WeEngine-style multi-merchant WeChat
> platform; zweq is an independent Zig implementation of that business domain.

## Overview

zweq is a **single-binary, multi-tenant WeChat operations platform**. The Zig backend
serves the JSON API, the compiled SolidJS SPA, the WeChat callback endpoints, the
task dispatcher and the WeChat Pay v3 gateway on one HTTP port.

```
Browser (SolidJS SPA, served by the same binary)
        │  /api/v1 (JSON envelope: { code, msg, data })
        ▼
Zig HTTP server (zigmodu)
        │  global middleware: security headers → access log → CORS → JWT (tenant) → metrics
        ▼
Module APIs ──► Services ──► Persistence (zent client) ──► SQLite / PostgreSQL
        │
        ├── /wx/{token}   callback engine (zwechat: signature + AES)
        ├── Task dispatcher (durable queue, retries, housekeeping)
        └── WeChat Pay v3 gateway (signer → JSAPI prepay, verified notify → credit)
```

## Module layout

Every domain follows the same five-file shape, imported at compile time:

```
modules/<domain>/
├── model.zig        # zent schema (table + columns + edges)
├── persistence.zig  # type-safe queries on the shared client
├── service.zig      # business logic, no HTTP/SQL leakage
├── api.zig          # HTTP handlers (JWT tenant context, requireAdmin)
└── module.zig       # lifecycle metadata & dependency wiring
```

All schemas are aggregated in `src/schema.zig` into small graphs (to stay under
zent's comptime branch quota), then merged into one `Client` — a single type-safe
query client shared by every store. `src/db.zig` owns the driver (SQLite /
Postgres) and runs automatic migrations at startup.

## Multi-tenancy

- **Tenant = site**, identified by a physical `app_id` column on every tenant-scoped
  table (aligned with `zigmodu.setTenantColumn("app_id")`).
- The tenant id travels in the JWT `aud` claim — no per-request DB lookup.
- Tenant-scoped queries always filter by `app_id`; cross-tenant queries (platform
  admins) filter with `?tenant_id=`.
- The WeChat callback route (`/wx/{token}`) is public and resolves the account by
  token / appid — no JWT involved.

## Domain map

| Domain | Module | Notes |
| --- | --- | --- |
| Accounts | `account` | Official Account / Mini Program CRUD + `account_wechat` config |
| Modules | `module` | Registry + per-account bindings (compile-time modules, data-driven enable) |
| RBAC | `permission` | role / permission / user_role |
| Fans | `member` | fan with openid / unionid |
| Replies | `rule` | keyword rules + multi-type replies |
| Materials | `material` | rich-text news + image/voice/video media |
| Messages | `message` | callback engine + passive replies (plain / AES safe mode) |
| Payments | `payment` | recharge / wallet / withdraw, Pay v3 plug-in point |
| Settings | `setting` | site KV store |
| Cloud | `cloud` | license codes + app marketplace |
| H5 BFF | `app_bff` | thin mobile API layer |

Reused platform backbone: `tenant`, `user`, `auth`, `task`, `file`, `notify`,
`audit`, `mail_template`, `ai`.

## WeChat callback pipeline

1. `GET/POST /wx/{token}` — resolve account by token; verify signature (zwechat).
2. `echostr` handshake for server-configuration validation.
3. Parse body — plain XML, or AES-256-CBC decrypted XML in safe mode.
4. Fan sync on follow / unfollow events.
5. Keyword matching → passive text / news reply (encrypted in safe mode).
6. Every callback / outbound message is recorded in `message_log`.

## Payments (WeChat Pay v3)

- **prepay**: `createV3RechargeOrder` builds the real JSAPI unified-order request with
  the `zwechat.pay.v3.signer` authorization header. Configured via site settings
  (`mchid` / `appid` / `serial_no` / `private_key` / `notify_url`); missing config
  fails closed, unconfigured → mock.
- **notify**: `POST /api/v1/pay/v3/notify` — verify the platform-certificate
  RSA-SHA256 signature (`Wechatpay-Signature/Timestamp/Nonce`), decrypt the
  AES-256-GCM resource, then `completeRecharge` credits the wallet idempotently.
  The api_v3_key is read from `wechat_pay_apiv3_key` site setting.

## Background jobs

Durable rows in the `Task` table, claimed and executed on one dispatcher thread
(zent's SQLite driver is single-connection):

1. **Claim** — oldest due `pending` task → `claimed`
2. **Run** — registered handler (e.g. `mail.send`)
3. **Finalize** — `done`, or retry with backoff until `max_attempts` → `failed`

Stale claims from crashed workers are requeued. The same thread runs interval
housekeeping: expired token cleanup, notification pruning, audit retention.

## AI assistant

- Providers are OpenAI-compatible; keys encrypted at rest (AES-256-GCM, master key
  `ZWEQ_AI_KEY_SECRET`).
- The agent (zigmodu.ai) runs skills (read-only platform tools) and write skills
  (e.g. `notify.send`) that require human approval.
- Keyword-miss auto-reply (`wechat_ai_auto_reply=1`) delegates to `AiService.chat`
  with user_id=0; failures fall back to the default reply.

## Frontend

SolidJS + TypeScript + Rsbuild + Tailwind 4 + DaisyUI. API clients are generated
per domain under `web/src/api/<domain>/{path,query,types,index}.ts` with a barrel
export. Routing lives in `web/src/index.tsx`, nav in `layouts/MainLayout.tsx`,
path constants in `constants/routePath.ts`. In production the Zig binary serves
`web/dist`.

## Key decisions

1. **Compile-time modules instead of runtime plugins** — Zig cannot load code at
   runtime; "installing" a module = enabling / binding it for an account (data-driven).
2. **zent as the primary ORM** (schema-as-code for a large schema); complex hot-path
   SQL may mix in zigmodu sqlx.
3. **`{ code, msg, data }` envelope**; JWT HS256 + Argon2id password hashing.
4. **Path deps → git tag pins** (see `build.zig.zon`) so builds are reproducible
   across machines; local development can temporarily swap to `../../zig_ws/...`.
