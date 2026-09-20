//! Per-IP / per-openid rate limiting with configurable backend.
//!
//! Supports two backends:
//! - In-process token-bucket (`zigmodu.RateLimiterRegistry`) for dev / single-node.
//! - Redis fixed-window (`zigmodu.data.redis_rate_limit.RateLimiter`) for production
//!   multi-instance deployments. Redis is shared across nodes and keys expire
//!   automatically, solving the unbounded per-client memory growth of the in-process
//!   registry.
//!
//! Two limiting dimensions:
//! - `perIpRateLimit` (`PerIpLimiter`): key is the real client IP (via
//!   `RequestUtil.getRealIp`, which reads the attribute set by
//!   `middleware/real_ip.zig`). Suitable for admin / management traffic.
//! - `perOpenidRateLimit` (`PerOpenidLimiter`): key is the WeChat openid carried
//!   by the fan JWT (`sub`). C 端(fan)经济接口必须从 per-IP 换成这个维度——
//!   微信小程序请求经微信出口转发，IP 高度集中，per-IP 会把所有用户
//!   混在一个桶里（误伤）或完全挡不住单个用户刷量（失效）。

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;

pub const Backend = union(enum) {
    registry: *zigmodu.RateLimiterRegistry,
    redis: *zigmodu.data.redis.Redis,
};

/// 限流后端内部错误（registry OOM / Redis 不可达）时的统一策略。
/// 两种后端走同一条错误路径，行为一致，不再出现"registry OOM 放行、
/// Redis 错误即 429"的分叉；具体取向由每个 limiter / 每条规则配置。
pub const FailPolicy = enum {
    /// fail-open：放行并 `log.warn`。用于 C 端经济接口——限流器故障不应
    /// 阻断业务（资损面已由后端事务/库存约束兜住），但必须在日志里暴露，
    /// 避免后端故障被静默吞掉。
    open,
    /// fail-closed：拒绝 429 并 `log.err`。用于管理端/认证入口——宁可
    /// 短暂不可用，也不能在无法计数时放行。
    closed,
};

/// registry 后端的键上限（zigmodu v0.15.46 起 `RateLimiterRegistry` 支持
/// `max_keys` + LRU 淘汰，默认 `0` = 无上限）。
///
/// 必须有上限：registry 的键来自攻击者可轮换的输入（`X-Real-IP` 头或 openid），
/// 无上限就是"换一个 key 涨一份内存"的放大器——本文件头把这条列为改用 Redis 的
/// 理由，而单节点/开发环境用的正是 registry。`max_keys` 把内存钉死；周期回收
/// （`reapIdle`）让正常流量下几乎碰不到上界，只有真被刷 key 时才淘汰（被淘汰者
/// 的桶额度重置，这是上游文档写明的淘汰期取舍）。
pub const registry_max_keys: usize = 8192;

/// 空闲超过这个秒数的桶由 `reapIdle` 删除（900s = 15 分钟无请求即回收）。
pub const registry_idle_reap_seconds: i64 = 900;

/// 进程级限流拒绝计数（HTTP 429）：per-IP 超限、per-openid 超限/无身份
/// 拒绝、后端故障 fail-closed 三条路径共用。选进程级原子变量而非按规则
/// 分维度或落 Redis：它只服务 /metrics 的总量告警，单机原子递增无锁、
/// 无网络开销；多实例部署时各进程各计各的，聚合由 Prometheus `sum()`
/// 完成，与 HTTP 请求计数器的口径一致。计数器归本文件所有，由
/// metrics.zig 只读导出，本文件不反向依赖 metrics。
/// `var` 是必须的：`fetchAdd` 要可变指针，`const` 原子取地址编不过。
pub var rejections_total = std.atomic.Value(u64).init(0);

/// 周期回收一组 registry 的空闲桶。`retain` 内部持锁，可在主循环里安全调用。
pub fn reapIdle(registries: []const *zigmodu.RateLimiterRegistry) void {
    for (registries) |r| _ = r.retain(registry_idle_reap_seconds);
}

/// 统一处理限流后端内部错误：按配置策略放行（fail-open）或 429（fail-closed）。
fn onInternalError(
    ctx: *http.Context,
    next: http.HandlerFn,
    policy: FailPolicy,
    what: []const u8,
    rule_name: []const u8,
) anyerror!void {
    if (policy == .open) {
        std.log.warn("[rate_limit] {s}，按 fail-open 策略放行: rule={s}", .{ what, rule_name });
        try next(ctx);
    } else {
        std.log.err("[rate_limit] {s}，按 fail-closed 策略拒绝: rule={s}", .{ what, rule_name });
        _ = rejections_total.fetchAdd(1, .monotonic);
        try ctx.sendErrorResponse(429, 429, "Too Many Requests");
    }
}

pub const PerIpLimiter = struct {
    backend: Backend,
    /// Max requests allowed within the window (Redis) or burst (registry).
    max: u32,
    /// Window size in seconds (Redis backend).
    window_seconds: u32 = 60,
    /// Token refill rate per second (registry backend).
    refill_rate: u32 = 1,
    /// 后端内部错误策略（见 FailPolicy）。默认 `.closed`（安全优先，与原
    /// Redis 分支行为一致）；C 端经济接口请显式配 `.open`。
    on_internal_error: FailPolicy = .closed,
};

pub fn perIpRateLimit(limiter: *PerIpLimiter) http.Middleware {
    // Process-lifetime state (server runs until exit; page_allocator mirrors
    // zigmodu's own rateLimitPerClient convention).
    // ReleaseFast 下 `unreachable` 是 UB；OOM 用带上下文的 panic 报告（zigmodu
    // 0.15.41 把自己同类的 8 处也这么改了）。
    const c = std.heap.page_allocator.create(PerIpLimiter) catch @panic("perIpRateLimit: page_allocator out of memory");
    c.* = limiter.*;
    return .{
        .func = struct {
            fn handle(ctx: *http.Context, next: http.HandlerFn, user_data: ?*anyopaque) anyerror!void {
                const self: *PerIpLimiter = @ptrCast(@alignCast(user_data orelse return error.UnexpectedError));
                const ip = zigmodu.http.RequestUtil.getRealIp(ctx);
                const allowed = switch (self.backend) {
                    .registry => |r| blk: {
                        const lim = r.getOrCreateForClient(ip, self.max, self.refill_rate) catch {
                            // 内部错误：统一按配置策略处理（不再硬编码放行）。
                            return onInternalError(ctx, next, self.on_internal_error, "registry OOM", "per-ip");
                        };
                        break :blk lim.tryAcquire();
                    },
                    .redis => |redis| blk: {
                        var rl = zigmodu.data.redis_rate_limit.RateLimiter.init(redis);
                        break :blk rl.allow(ip, self.max, self.window_seconds) catch {
                            // 内部错误：统一按配置策略处理（不再硬编码 429）。
                            return onInternalError(ctx, next, self.on_internal_error, "redis 错误", "per-ip");
                        };
                    },
                };
                if (!allowed) {
                    _ = rejections_total.fetchAdd(1, .monotonic);
                    try ctx.sendErrorResponse(429, 429, "Too Many Requests");
                    return;
                }
                try next(ctx);
            }
        }.handle,
        .user_data = c,
    };
}

/// 取不到 openid 时的降级策略（per-openid 限流专用）。
pub const NoIdentityPolicy = enum {
    /// 降级按 per-IP 计数（key 加 `:ip:` 前缀，与 openid 维度互不串桶）。
    fallback_ip,
    /// 直接 429 拒绝。注意会把"未登录/凭证无效"和"被限流"混为同一响应码。
    reject,
};

/// per-openid 限流的单端点规则：按 method + path 匹配请求，命中才计数。
/// 阈值表中每条端点一项，max / window / 降级与故障策略均可按端点调整。
pub const OpenidRule = struct {
    /// 短名，仅用于日志和限流 key 的命名空间：
    /// key = "rl:fan:{name}:{openid}"（降级时为 "rl:fan:{name}:ip:{ip}"）。
    name: []const u8,
    /// 匹配请求方法；当前 8 个经济端点均为 POST。
    method: http.Method = .POST,
    /// 匹配 `ctx.path` 去掉前导 `/` 后的段序列；`{` 开头的段通配任意非空段
    /// （如 "api/v1/app/coupons/{id}/claim" 匹配 /api/v1/app/coupons/123/claim）。
    path: []const u8,
    /// 窗口内允许的最大请求数。
    max: u32,
    /// 固定窗口秒数（Redis 后端语义：max 次 / window_seconds 秒，生产精确生效）。
    window_seconds: u32 = 60,
    /// 令牌桶每秒回充数（registry 后端语义：burst = max，之后每秒回充
    /// refill_rate 个）。u32 表达不了 <1/秒 的回充，registry 只能近似固定窗口
    /// （对 10 次/分的规则，稳态会松到 refill_rate 次/秒）；registry 仅作
    /// 开发/单节点兜底，生产应开 Redis 走固定窗口。
    refill_rate: u32 = 1,
    /// 取不到 openid 时的降级策略。取舍说明：这 8 个端点本身要求 fan 登录，
    /// 无效/过期 token 最终仍会被处理器 401，因此默认降级 per-IP——限流器
    /// 不越权用 429 冒充鉴权结果，同时保留 IP 维度兜住伪造 token 的刷量。
    no_identity: NoIdentityPolicy = .fallback_ip,
    /// 后端内部错误策略（见 FailPolicy）。C 端经济接口建议 `.open`
    /// （可用性优先 + 日志告警），可按端点覆盖。
    on_internal_error: FailPolicy = .open,
};

pub const PerOpenidLimiter = struct {
    backend: Backend,
    /// 与 fan_auth.zig 同一个验签模块（AppSecurity.module.verifyToken），
    /// 用于在中间件层把 Bearer token 解析为可信 openid（sub）。
    sec: *zigmodu.security.AppSecurity,
    /// 端点阈值表：按 method + path 匹配，命中才限流；表外路由原样放行，
    /// 不影响同模块下的其他 fan 端点。
    rules: []const OpenidRule,
};

pub fn perOpenidRateLimit(limiter: *PerOpenidLimiter) http.Middleware {
    // 同 perIpRateLimit：OOM 用带上下文的 panic，不用 ReleaseFast 下是 UB 的 unreachable。
    const c = std.heap.page_allocator.create(PerOpenidLimiter) catch @panic("perOpenidRateLimit: page_allocator out of memory");
    c.* = limiter.*;
    return .{
        .func = struct {
            fn handle(ctx: *http.Context, next: http.HandlerFn, user_data: ?*anyopaque) anyerror!void {
                const self: *PerOpenidLimiter = @ptrCast(@alignCast(user_data orelse return error.UnexpectedError));

                // 1) 端点匹配：只有阈值表内的经济端点才被约束。
                const rule = matchRule(self.rules, ctx.method, ctx.path) orelse {
                    try next(ctx);
                    return;
                };

                // 2) 解析 openid 身份。
                // 先读上游写入 ctx 属性的 openid（若未来有中间件/处理器提前设置）。
                // 取舍说明：当前 fan_auth.zig 是在"处理器内部"校验 JWT 并返回
                // owned openid，并不写任何 ctx 属性；且中间件先于处理器执行，
                // 属性里通常没有 openid。这里退化为本地验签——与 fan_auth.zig
                // 同一条 verifyToken 路径，多一次 HMAC 验签的 CPU 开销，可接受。
                // 伪造/过期 token 一律视为"取不到身份"；只取 sub 做计数维度，
                // fan 角色校验仍归处理器，限流器不越权做鉴权。
                var openid: ?[]const u8 = null;
                defer if (openid) |s| ctx.allocator.free(s);
                if (ctx.getAttr("openid")) |attr_openid| {
                    openid = try ctx.allocator.dupe(u8, attr_openid);
                } else if (ctx.headers.get("authorization")) |header| {
                    if (header.len > 7 and std.mem.startsWith(u8, header, "Bearer ")) {
                        const token = header[7..];
                        if (self.sec.module.verifyToken(token)) |payload| {
                            defer self.sec.module.freePayload(payload);
                            openid = try ctx.allocator.dupe(u8, payload.sub);
                        } else |_| {}
                    }
                }

                // 3) 组装限流 key（按规则命名空间隔离端点与身份维度）；
                //    openid 缺失或 key 超长时按规则降级。
                var key_buf: [512]u8 = undefined;
                var key: []const u8 = "";
                if (openid) |s| {
                    key = std.fmt.bufPrint(&key_buf, "rl:fan:{s}:{s}", .{ rule.name, s }) catch "";
                }
                if (key.len == 0) {
                    switch (rule.no_identity) {
                        .fallback_ip => {
                            const ip = zigmodu.http.RequestUtil.getRealIp(ctx);
                            key = std.fmt.bufPrint(&key_buf, "rl:fan:{s}:ip:{s}", .{ rule.name, ip }) catch {
                                return onInternalError(ctx, next, rule.on_internal_error, "限流 key 生成失败", rule.name);
                            };
                        },
                        .reject => {
                            _ = rejections_total.fetchAdd(1, .monotonic);
                            try ctx.sendErrorResponse(429, 429, "Too Many Requests");
                            return;
                        },
                    }
                }

                // 4) 后端计数：registry 为令牌桶（burst+回充），redis 为固定窗口。
                const allowed = switch (self.backend) {
                    .registry => |r| blk: {
                        const lim = r.getOrCreateForClient(key, rule.max, rule.refill_rate) catch {
                            return onInternalError(ctx, next, rule.on_internal_error, "registry OOM", rule.name);
                        };
                        break :blk lim.tryAcquire();
                    },
                    .redis => |redis| blk: {
                        var rl = zigmodu.data.redis_rate_limit.RateLimiter.init(redis);
                        break :blk rl.allow(key, rule.max, rule.window_seconds) catch {
                            return onInternalError(ctx, next, rule.on_internal_error, "redis 错误", rule.name);
                        };
                    },
                };
                if (!allowed) {
                    _ = rejections_total.fetchAdd(1, .monotonic);
                    try ctx.sendErrorResponse(429, 429, "Too Many Requests");
                    return;
                }
                try next(ctx);
            }
        }.handle,
        .user_data = c,
    };
}

/// 段级匹配：规则 path 与请求 path 段数相同，`{` 开头的规则段为通配，
/// 其余段按字面相等比较。
fn pathMatches(rule_path: []const u8, req_path: []const u8) bool {
    var rit = std.mem.splitScalar(u8, rule_path, '/');
    var pit = std.mem.splitScalar(u8, req_path, '/');
    while (rit.next()) |rs| {
        const ps = pit.next() orelse return false;
        if (ps.len == 0) return false;
        if (rs.len > 0 and rs[0] == '{') continue;
        if (!std.mem.eql(u8, rs, ps)) return false;
    }
    return pit.next() == null;
}

fn matchRule(rules: []const OpenidRule, method: http.Method, path: []const u8) ?*const OpenidRule {
    const p = if (path.len > 0 and path[0] == '/') path[1..] else path;
    for (rules) |*rule| {
        if (rule.method != method) continue;
        if (pathMatches(rule.path, p)) return rule;
    }
    return null;
}
