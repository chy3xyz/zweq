//! Real client IP middleware — exposes the reverse proxy's `X-Real-IP` (or
//! the first entry of `X-Forwarded-For`) as a context attribute, so
//! `RequestUtil.getRealIp` works for rate limiting, audit logs and the
//! `/metrics` allow-list. Mount early (before any IP-reading middleware).

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;

pub fn realIp() http.Middleware {
    return .{
        .func = struct {
            fn handle(ctx: *http.Context, next: http.HandlerFn, _: ?*anyopaque) anyerror!void {
                if (ctx.header("X-Real-IP")) |ip| {
                    try ctx.setAttr("X-Real-IP", ip);
                } else if (ctx.header("X-Forwarded-For")) |fwd| {
                    // X-Forwarded-For is a comma-separated chain; the first is
                    // the client as seen by the trusted proxy.
                    const first = if (std.mem.indexOfScalar(u8, fwd, ',')) |pos|
                        std.mem.trim(u8, fwd[0..pos], &std.ascii.whitespace)
                    else
                        fwd;
                    try ctx.setAttr("X-Real-IP", first);
                }
                try next(ctx);
            }
        }.handle,
    };
}
