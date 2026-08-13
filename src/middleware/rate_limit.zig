//! Per-IP rate limiting with configurable token-bucket parameters.
//!
//! zigmodu's `rateLimitPerClient` hardcodes 100 tokens / 10 per sec, which is
//! too loose for auth brute-force protection, so we expose our own wrapper.
//! The key is the real client IP (via `RequestUtil.getRealIp`, which reads the
//! attribute set by `middleware/real_ip.zig`).

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;

const Ctx = struct {
    registry: *zigmodu.RateLimiterRegistry,
    max_tokens: u32,
    refill_rate: u32,
};

pub fn perIpRateLimit(
    registry: *zigmodu.RateLimiterRegistry,
    max_tokens: u32,
    refill_rate: u32,
) http.Middleware {
    // Process-lifetime state (server runs until exit; page_allocator mirrors
    // zigmodu's own rateLimitPerClient convention).
    const c = std.heap.page_allocator.create(Ctx) catch unreachable;
    c.* = .{ .registry = registry, .max_tokens = max_tokens, .refill_rate = refill_rate };
    return .{
        .func = struct {
            fn handle(ctx: *http.Context, next: http.HandlerFn, user_data: ?*anyopaque) anyerror!void {
                const rc: *Ctx = @ptrCast(@alignCast(user_data orelse return error.UnexpectedError));
                const ip = zigmodu.http.RequestUtil.getRealIp(ctx);
                const lim = rc.registry.getOrCreateForClient(ip, rc.max_tokens, rc.refill_rate) catch {
                    // Fail-open on registry OOM — don't take the route down.
                    try next(ctx);
                    return;
                };
                if (!lim.tryAcquire()) {
                    try ctx.sendErrorResponse(429, 429, "Too Many Requests");
                    return;
                }
                try next(ctx);
            }
        }.handle,
        .user_data = c,
    };
}
