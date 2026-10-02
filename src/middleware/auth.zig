//! Auth helpers for zweq HTTP handlers.
//!
//! JWT verification uses zigmodu's built-in `jwtAuthWithSecurity` middleware
//! (mounted per route group in the module `api.zig` files). The helpers here
//! read the context attributes that middleware sets: `user_id` (JWT `sub`)
//! and `tenant_id` (JWT `aud`).

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const user_persist = @import("../modules/user/persistence.zig");

/// Context attribute names set by zigmodu's built-in JWT middleware
/// (`verifyJwtLoadPermsAndNext` in `api/Middleware.zig`).
pub const user_id_attr = "user_id";
pub const tenant_id_attr = "tenant_id";

/// 无状态 kid 派生：密钥的 kid = 其 SHA-256 的前 12 个 hex 字符。同一密钥
/// 在任意一次启动都派生出同一 kid，轮换无需持久化元数据、不加表；kid 只
/// 进 JWT header，单向哈希不泄露密钥本身。
pub fn kidForSecret(secret: []const u8) [12]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(secret, &digest, .{});
    var kid: [12]u8 = undefined;
    const hex = "0123456789abcdef";
    for (digest[0..6], 0..) |b, i| {
        kid[i * 2] = hex[b >> 4];
        kid[i * 2 + 1] = hex[b & 0x0f];
    }
    return kid;
}

/// 按 env 配置装配 JWT 密钥环（zigmodu JwksKeyRing）：`current` 为主签发键
/// （新 token 的 header 带它的 kid，签名用它），`previous_csv` 逗号分隔的
/// 每一只为只验不签的轮换窗口密钥（ZWEQ_JWT_SECRET_PREVIOUS）。无 kid 的
/// 旧 token 由 SecurityModule 回退 `jwt_secret` 验证，不经过本环。返回的环
/// 归调用方所有（传入的分配器），须在 SecurityModule 停用之后 deinit。
pub fn buildJwtKeyring(
    allocator: std.mem.Allocator,
    current: []const u8,
    previous_csv: []const u8,
) !zigmodu.security.JwksKeyRing {
    var ring = zigmodu.security.JwksKeyRing.init(allocator);
    errdefer ring.deinit();

    const cur_kid = kidForSecret(current);
    try ring.addKey(&cur_kid, current, true);

    var it = std.mem.splitScalar(u8, previous_csv, ',');
    while (it.next()) |raw| {
        const prev = std.mem.trim(u8, raw, " \t");
        if (prev.len == 0) continue;
        if (std.mem.eql(u8, prev, current)) continue;
        const kid = kidForSecret(prev);
        try ring.addKey(&kid, prev, false);
    }
    return ring;
}

/// The authenticated user's tenant id (from the JWT `aud` claim), or null
/// when the token predates tenant support.
pub fn authTenantId(ctx: *http.Context) ?i64 {
    const id_str = ctx.getAttr(tenant_id_attr) orelse return null;
    return std.fmt.parseInt(i64, id_str, 10) catch null;
}

/// `authTenantId` 的兜底版:JWT attr 缺失/非法时回落 `default_tenant_id`。
/// 行为与 `authTenantId(ctx) orelse default_tenant_id` 完全一致,唯二区别
/// 是兜底发生时打 warn 留痕(带路由上下文)。app_bff 的 C 端单租户路径
/// 有意保持静默,不要用本函数。
pub fn authTenantIdOrDefault(ctx: *http.Context, default_tenant_id: i64) i64 {
    return authTenantId(ctx) orelse {
        std.log.warn("[tenant] {s}: attr 缺失,回落默认租户 {d}", .{ ctx.route_template orelse ctx.path, default_tenant_id });
        return default_tenant_id;
    };
}

/// 挂载在 `jwtAuthWithSecurity` 之后:比对 JWT 的 `ver` claim 与数据库中的
/// 用户凭证版本;改密/踢下线(版本递增)后旧 token 立即失效(401)。
pub fn tokenVersionGuard(sec: *zigmodu.security.AppSecurity, user_store: *user_persist.UserStore) http.Middleware {
    const S = struct {
        var stored_sec: *zigmodu.security.AppSecurity = undefined;
        var stored_store: *user_persist.UserStore = undefined;
    };
    S.stored_sec = sec;
    S.stored_store = user_store;
    return .{
        .func = struct {
            fn mw(ctx: *http.Context, next: http.HandlerFn, _: ?*anyopaque) anyerror!void {
                // Catalog-aware: public routes have no user_id; skip the version check.
                const uid = ctx.userIdInt(i64) orelse {
                    try next(ctx);
                    return;
                };
                const hdr = ctx.header("authorization") orelse ctx.header("X-Token") orelse {
                    try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                    return;
                };
                const token = zigmodu.security.SecurityModule.extractBearerToken(hdr) orelse hdr;
                const payload = S.stored_sec.module.verifyToken(token) catch {
                    try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                    return;
                };
                defer S.stored_sec.module.freePayload(payload);
                const row_opt = S.stored_store.getUserById(uid) catch {
                    try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                    return;
                };
                const row = row_opt orelse {
                    try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                    return;
                };
                defer row.free(S.stored_store.allocator);
                if (payload.ver != row.token_version) {
                    try ctx.sendErrorResponse(401, 401, "登录已失效,请重新登录");
                    return;
                }
                try next(ctx);
            }
        }.mw,
    };
}

/// 挂载在 `jwtAuthWithSecurity` 之后:要求当前用户具有 `admin` 角色。
/// 用于保持 `registerRoutes` 兼容层与 ComptimeRouter 的 `.permission = "admin"` 行为一致。
pub fn adminGuard(user_store: *user_persist.UserStore) http.Middleware {
    const S = struct {
        var stored_store: *user_persist.UserStore = undefined;
    };
    S.stored_store = user_store;
    return .{
        .func = struct {
            fn mw(ctx: *http.Context, next: http.HandlerFn, _: ?*anyopaque) anyerror!void {
                const uid = ctx.userIdInt(i64) orelse {
                    // 公开路由没有 user_id,跳过管理员校验。
                    try next(ctx);
                    return;
                };
                const row_opt = S.stored_store.getUserById(uid) catch {
                    try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                    return;
                };
                const row = row_opt orelse {
                    try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                    return;
                };
                defer row.free(S.stored_store.allocator);
                if (!row.admin) {
                    try ctx.sendErrorResponse(403, 403, "需要管理员权限");
                    return;
                }
                try next(ctx);
            }
        }.mw,
    };
}
