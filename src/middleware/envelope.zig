//! Response envelope dialect — pins every request to the RuoYi shape.
//!
//! Without this, `ctx.ok` / `ctx.okValue` / `ctx.paginated` fall back to the
//! ZigModu default envelope, which disagrees with the paged responses that
//! already pass `.ruoyi` explicitly. Setting the dialect globally unifies
//! success, paged, fail and unauth responses so the SolidJS SPA can read a
//! single envelope shape.

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;

pub fn ruoyiEnvelope() http.Middleware {
    return .{
        .func = struct {
            fn handle(ctx: *http.Context, next: http.HandlerFn, _: ?*anyopaque) anyerror!void {
                ctx.setEnvelope(http.EnvelopeDialect.ruoyi);
                try next(ctx);
            }
        }.handle,
    };
}

/// 传输层错误的 ruoyi 信封渲染器（`http.setTransportErrorRenderer` 挂载）。
/// 路由之前由框架直接写回的错误（400/408/413/431/503 等）默认是
/// `{"error":...}`，与全站 ruoyi 信封不一致；这里统一成
/// `{"code":<status>,"msg":<原文>,"data":null}`。框架传入的 message 均为
/// 固定常量（无引号/反斜杠），可直接拼接；无分配——accept 线程上可能
/// 并发调用，只能写调用方给的 scratch buf。
pub fn ruoyiTransportError(status: u16, message: []const u8, buf: []u8) http.TransportErrorBody {
    const body = std.fmt.bufPrint(buf, "{{\"code\":{d},\"msg\":\"{s}\",\"data\":null}}", .{ status, message }) catch
        return .{ .body = "{\"code\":500,\"msg\":\"Request Failed\",\"data\":null}" };
    return .{ .body = body };
}
