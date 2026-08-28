//! Per-IP rate limiting with configurable backend.
//!
//! Supports two backends:
//! - In-process token-bucket (`zigmodu.RateLimiterRegistry`) for dev / single-node.
//! - Redis fixed-window (`zigmodu.data.redis_rate_limit.RateLimiter`) for production
//!   multi-instance deployments. Redis is shared across nodes and keys expire
//!   automatically, solving the unbounded per-IP memory growth of the in-process
//!   registry.
//!
//! The key is the real client IP (via `RequestUtil.getRealIp`, which reads the
//! attribute set by `middleware/real_ip.zig`).

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;

pub const Backend = union(enum) {
    registry: *zigmodu.RateLimiterRegistry,
    redis: *zigmodu.data.redis.Redis,
};

pub const PerIpLimiter = struct {
    backend: Backend,
    /// Max requests allowed within the window (Redis) or burst (registry).
    max: u32,
    /// Window size in seconds (Redis backend).
    window_seconds: u32 = 60,
    /// Token refill rate per second (registry backend).
    refill_rate: u32 = 1,
};

pub fn perIpRateLimit(limiter: *PerIpLimiter) http.Middleware {
    // Process-lifetime state (server runs until exit; page_allocator mirrors
    // zigmodu's own rateLimitPerClient convention).
    const c = std.heap.page_allocator.create(PerIpLimiter) catch unreachable;
    c.* = limiter.*;
    return .{
        .func = struct {
            fn handle(ctx: *http.Context, next: http.HandlerFn, user_data: ?*anyopaque) anyerror!void {
                const self: *PerIpLimiter = @ptrCast(@alignCast(user_data orelse return error.UnexpectedError));
                const ip = zigmodu.http.RequestUtil.getRealIp(ctx);
                const allowed = switch (self.backend) {
                    .registry => |r| blk: {
                        const lim = r.getOrCreateForClient(ip, self.max, self.refill_rate) catch {
                            // Fail-open on registry OOM — don't take the route down.
                            try next(ctx);
                            return;
                        };
                        break :blk lim.tryAcquire();
                    },
                    .redis => |redis| blk: {
                        var rl = zigmodu.data.redis_rate_limit.RateLimiter.init(redis);
                        break :blk rl.allow(ip, self.max, self.window_seconds) catch {
                            // Fail-closed: Redis error means we cannot verify the
                            // counter, so reject rather than silently allow.
                            try ctx.sendErrorResponse(429, 429, "Too Many Requests");
                            return;
                        };
                    },
                };
                if (!allowed) {
                    try ctx.sendErrorResponse(429, 429, "Too Many Requests");
                    return;
                }
                try next(ctx);
            }
        }.handle,
        .user_data = c,
    };
}
