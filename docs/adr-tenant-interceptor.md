# ADR — Tenant isolation: explicit WHERE vs zent UseInterceptor

Status: **Proposed (2026-09-04)**. Implementation deferred.

## Context

Zent 0.33 ships `UseInterceptor(infos, *Client(infos), Interceptor)` (see
`zig-pkg/zent-0.33.0-.../src/codegen/client.zig:379`) that lets a caller
register a chain of `Interceptor` callbacks executed on every Query /
Update / Delete / Create / BulkInsert operation. The `whereEq(field, value)`
helper appends a predicate — on Query/Update/Delete as a WHERE, on Create as
a set-if-missing column. The interceptor's `ctx` is `?*anyopaque`, so the
hook can carry any caller state.

The question: should we move zweq's tenant isolation from per-handler
`preds.tenant_idEQ(...)` (currently ~30 modules × ~5 stores each, all
hand-written) onto a single tenant interceptor?

## Forces

1. **Verbose**: every store read/write currently passes `tenant_id`
   explicitly, ~150+ call sites.
2. **Easy to forget**: a new query without `tenant_idEQ` is a cross-tenant
   leak — risk grows with module count.
3. **Fiber runtime**: zweq uses Zig 0.17 `std.Io` thread-pool fibers. Fibers
   migrate between OS threads, so thread-local tenant state is **not safe**.
4. **Singleton Client**: `store_env.client` in `src/main.zig:125` is one
   `Client(schema.infos)` shared across all requests — interceptor ctx is
   process-global per Client instance.

## Design options

### A. Explicit WHERE — current pattern

- Per-method `tenant_id` param.
- Pros: fiber-safe, no global mutable state, no extra allocation per
  request.
- Cons: verbose, easy to forget on new code.

### B. UseInterceptor with TLS for ctx

- `threadlocal var current_tenant: ?i64 = null`.
- Interceptor reads global, calls `whereEq("tenant_id", ...)`.
- Pros: removes 150+ explicit predicates; one place to enforce.
- Cons: **broken under fiber migration** — `std.Io` thread-pool moves
  fibers between OS threads, TLS doesn't follow.

### C. UseInterceptor with per-request Client wrap

- Each HTTP request allocates an arena + a derived `Client` wrapping the
  root with one extra interceptor whose ctx is the request's tenant_id.
- Pros: fiber-safe, scoped, leverages zent 0.33 fully.
- Cons: store signatures must accept `anytype` (Client or TxClient or
  WrappedClient) — touches every persistence module (~30 files).
  Per-request allocator + Client is a non-trivial per-request cost.

### D. UseInterceptor with std.Io fiber-local extension

- Requires framework support for fiber-local storage, which zigmodu +
  zent don't currently expose.
- Out of scope today.

## Decision

**Keep option A.** Reasons:

- Fiber safety is non-negotiable — option B is unsafe under `std.Io`.
- Option C requires a sweeping API change across all 30 persistence
  modules, just to deduplicate ~150 predicates that already work and are
  compile-checked. The risk/value ratio is poor for the current
  single-process architecture.
- Future: when we either (a) shard the database per tenant or (b) move to
  a connection-per-tenant pool, option C becomes attractive — every store
  starts on the per-tenant Client and the interceptor stops needing the
  ctx switch.

## Mitigations

While keeping option A, two cheap guards:

1. **`grep` for `preds.idEQ` without `tenant_idEQ` in the same query** —
   add a quick lint script under `tools/` that flags read patterns
   missing tenant filtering. Not enforced in CI yet, but discoverable.
2. **One-table POC for option C** — when an actual use case appears (e.g.
   a high-throughput read path where the predicate overhead matters),
   prototype option C on the smallest module first (`audit`) to validate
   the per-request Client cost in our runtime.

## References

- zent intercept module: `zig-pkg/zent-0.33.0-.../src/runtime/intercept.zig`
- zent UseInterceptor: `zig-pkg/zent-0.33.0-.../src/codegen/client.zig:379`
- Store factory: `src/main.zig:125` (`store_env.client` singleton)
- Current pattern example: `src/modules/coupon/persistence.zig:163-178`
