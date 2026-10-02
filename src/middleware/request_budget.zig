//! 请求预算闸门：把 connFiber 按 request_timeout_ms 武装在 ctx.deadline_ms
//! 上的请求预算变成可执行的失败——预算耗尽即 408，不再进 handler/存储
//!（审计 P1：客户端断开后慢查询仍占池连接跑完的防线之一）。
//!
//! 闸门是全局兜底；精确报错的入口在存储层：
//!   - shop/payment 的事务入口 Budget 变体把 zent 的 PoolWaitTimeout /
//!     QueryTimeout 映射成 error.RequestTimeout（预算耗尽前置检查）；
//!   - 列表/报表查询用 db.applyDeadline 把 deadline 盖进 zent builder。
//! 存储层抹错（catch → error.Unexpected）后预算恰好耗尽的其他错误，也由
//! 本闸门按「预算已耗尽」改判 408——客户端此时早已放弃连接，回 500 无意义。

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;

/// 启动期由 main 单线程写入一次，之后只读（addMiddleware 早于 listen）。
var gate_enabled: bool = true;

pub fn budgetGate(enabled: bool) http.Middleware {
    gate_enabled = enabled;
    return .{ .func = budgetGateFn };
}

fn budgetGateFn(ctx: *http.Context, next: http.HandlerFn, user_data: ?*anyopaque) anyerror!void {
    _ = user_data;
    if (!gate_enabled) return next(ctx);
    // 入口快失败：预算耗尽（常见于排队等连接后）→ 408，不再往存储层压查询。
    if (spent(ctx)) return reject(ctx);
    next(ctx) catch |err| {
        if (ctx.responded) return err;
        // error.RequestTimeout = 存储层显式上报的预算耗尽；其余错误但预算
        // 同样耗尽的，如实回 408 而不是误导性的 500。
        if (err == error.RequestTimeout or spent(ctx)) return reject(ctx);
        return err;
    };
}

fn spent(ctx: *http.Context) bool {
    const left = ctx.remainingMs() orelse return false;
    return left <= 0;
}

fn reject(ctx: *http.Context) !void {
    std.log.warn("[request_budget] 请求预算耗尽，提前终止 {s} {s}", .{ ctx.method.toString(), ctx.raw_path });
    try ctx.sendErrorResponse(408, 408, "请求超时，请稍后重试");
}
