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

## Module dependencies & boundaries (模块依赖与边界)

**Dependency declarations are real and enforced.** Each `module.zig`'s
`.dependencies` must equal the static cross-module `@import` graph, in both
directions — importing a sibling module without declaring it, or declaring one
without any import backing it, fails `zig build lint-deps`
(`scripts/check_module_deps.py`, mirrored in CI's lint job). This matters
because zigmodu's startup validation (missing-dependency / cycle detection)
only sees the declared graph: while 28 of 31 modules declared `&.{}` the
validator was toothless and a real dependency cycle would have booted fine.

**Real graph** (2026-09, 31 modules / 107 edges, source of truth = the lint
script):

```
audit        → (leaf, everyone else imports it for the admin trail)
user         → audit
message      → account ai audit member module rule setting user   # callback engine hub
scene apps   → message module user audit                          # checkin / coupon / vote /
                                                                  # seckill / member_card /
                                                                  # lucky_draw / distribution
material / member / menu → account user audit
payment      → setting user audit
points       → member user audit
ai           → task tenant notify user audit
auth         → task notify mail_template user audit
cloud        → module user audit
system       → task file notify tenant user
shop         → coupon distribution member member_card payment setting task user audit
app_bff      → account checkin coupon distribution lucky_draw member member_card
               module payment points seckill user vote            # BFF fan-out, no own tables
```

`user` + `audit` are the cross-cutting pair injected into nearly every API
layer (permission checks + audit trail); the interesting edges are at the
service layer.

**Boundary rule: 不互扒 persistence.** A business module must not read or
write a sibling module's persistence directly — go through the sibling's
`service.zig` public methods. The only exception is **transaction
consistency**: when a write must commit/rollback with the caller's
transaction, it goes through a narrow service method that accepts the
caller's tx client and performs the store calls inside the sibling module
(exemplar: `CouponService.redeemOnOrder`, used by shop's `createOrder` — the
coupon's `used` mark must die with the order if the order tx rolls back).
Even then the caller holds a *service* handle, never the sibling's bare
Store type.

Known legacy exceptions (kept, documented, not to be extended):

- `shop` service holds `member.persistence.FanStore` (openid → fan_id before
  balance pay / balance recharge). The assembly contract in `main.zig`
  injects the store pointer, not `MemberService`, and the two lookups are
  read-only single queries — converting them requires touching `main.zig`,
  so they stay direct with the dependency declared.
- `shop` API layer (`api.zig` / `handlers/`) takes `FanStore` /
  `SettingStore` in its constructor signature — **still kept** (re-verified
  2026-09-28): the `main.zig` assembly injects the raw store pointers
  (`&fan_store` / `&setting_store`), not `MemberService` / `SettingService`,
  and converging means changing that assembly signature (`main.zig` out of
  scope for the cleanup round). Actual direct reads are only three sites:
  `handlers/content.zig` `cLogin` (`fan_store.getByOpenid` + login-time
  `upsert`) and `handlers/trade.zig` `orderPayParams` (`settings.get` for
  the wechat-pay config keys). Not to be extended in the meantime.

New cross-module reads/writes must go through the sibling service API (or a
tx-client narrow method on it); new bare-store injections are not allowed.

**Decision record: 执行平面维持自研 (task queue / scheduler stay
self-hosted, not zigmodu's runtime mailbox).** Background execution uses the
durable `Task`-table queue (`src/modules/task` + `src/scheduled.zig`), not
zigmodu's in-process mailbox/actor delivery:

1. **Delivery semantics are opposite.** Our workload is a DB-persisted
   at-least-once queue with backoff retries and claim fencing
   (`claim_owner` / `claimed_until`, `requeueStale` only recovers expired
   leases) — built for crash recovery and multi-replica safety. zigmodu's
   mailbox is in-memory at-most-once delivery; adopting it would trade
   durability for latency we don't need at this layer.
2. **SQLite is single-connection.** zent's SQLite driver serializes on one
   connection, so all background DB work must stay on ONE thread — the task
   dispatcher's loop, which is where `ScheduledRunner` lives (this rationale
   was born as the header comment of `src/scheduled.zig` and is promoted to
   this document). A zigmodu-runtime execution plane would scatter DB work
   across worker pools by design. CPU-only housekeeping may use
   `zigmodu.cron.Scheduler`; anything touching the DB may not.

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
