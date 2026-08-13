//! Request ID + structured access log (one JSON line per request).
//!
//! Replaces zigmodu's `tracingMiddleware`: propagates an upstream
//! `X-Request-Id` (or mints one), exposes it as the `request_id` context
//! attribute for downstream logging, returns it in the response header, and
//! emits a structured log line on completion carrying the client IP and
//! tenant/user ids (populated by the JWT middleware).

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;

var rid_counter = std.atomic.Value(u64).init(0);

pub fn requestLog() http.Middleware {
    return .{
        .func = struct {
            fn handle(ctx: *http.Context, next: http.HandlerFn, _: ?*anyopaque) anyerror!void {
                var owned: ?[]u8 = null;
                defer if (owned) |o| ctx.allocator.free(o);
                const rid = ctx.header("X-Request-Id") orelse blk: {
                    const r = try mint(ctx.allocator);
                    owned = r;
                    break :blk r;
                };
                try ctx.setAttr("request_id", rid);
                try ctx.setHeader("X-Request-Id", rid);

                const start_ns = zigmodu.time.monotonicNow();
                const method = ctx.method.toString();
                const path = ctx.raw_path;

                try next(ctx);

                const elapsed_us = @divTrunc(zigmodu.time.monotonicNow() - start_ns, std.time.ns_per_us);
                const ip = zigmodu.http.RequestUtil.getRealIp(ctx);
                const tenant_id = ctx.getAttr("tenant_id") orelse "";
                const user_id = ctx.getAttr("user_id") orelse "";
                const ts = if (ctx.io) |io| zigmodu.time.wallClockSeconds(io) else zigmodu.time.monotonicNowSeconds();
                // Structured one-liner: log collectors parse `level: {...}`.
                std.log.info("{{\"ts\":{d},\"request_id\":\"{s}\",\"method\":\"{s}\",\"path\":\"{s}\",\"status\":{d},\"elapsed_us\":{d},\"ip\":\"{s}\",\"tenant_id\":\"{s}\",\"user_id\":\"{s}\"}}", .{
                    ts,
                    rid,
                    method,
                    path,
                    ctx.status_code,
                    elapsed_us,
                    ip,
                    tenant_id,
                    user_id,
                });
            }
        }.handle,
    };
}

fn mint(allocator: std.mem.Allocator) ![]u8 {
    const counter = rid_counter.fetchAdd(1, .monotonic);
    const now = zigmodu.time.monotonicNow();
    return std.fmt.allocPrint(allocator, "{x:0>16}-{x:0>16}", .{ @as(u64, @bitCast(now)), counter });
}
