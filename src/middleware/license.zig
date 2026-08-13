//! License guard — fail-closed feature lock when the site's cloud license
//! is missing/expired/invalid (远端 zweq-cloud 模式).
//!
//! - `licenseGuard`: 无条件锁（挂到特定 route group）。
//! - `licenseGate`: 按路径前缀锁（挂 server-level），只锁资金/触达/安装等
//!   消费能力，管理/查询接口不受影响（避免授权失效后管理员无法操作）。
//! 本地模式（无 `ZWEQ_CLOUD_REMOTE_URL`）`isLicensed()` 恒 true，不锁。

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;

pub fn licenseGuard(cloud_svc: anytype) http.Middleware {
    const S = struct {
        var stored_svc: @TypeOf(cloud_svc) = undefined;
    };
    S.stored_svc = cloud_svc;
    return .{ .func = struct {
        fn mw(ctx: *http.Context, next: http.HandlerFn, _: ?*anyopaque) anyerror!void {
            if (!S.stored_svc.isLicensed()) {
                try ctx.sendErrorResponse(402, 402, "站点授权已失效或未配置（cloud_license_key）");
                return;
            }
            try next(ctx);
        }
    }.mw };
}

/// Server-level gate：仅锁「消费能力」路径前缀。
pub fn licenseGate(cloud_svc: anytype) http.Middleware {
    const S = struct {
        var stored_svc: @TypeOf(cloud_svc) = undefined;
    };
    S.stored_svc = cloud_svc;
    return .{ .func = struct {
        fn mw(ctx: *http.Context, next: http.HandlerFn, _: ?*anyopaque) anyerror!void {
            if (!S.stored_svc.isLicensed() and isProtectedPath(ctx.path)) {
                try ctx.sendErrorResponse(402, 402, "站点授权已失效或未配置（cloud_license_key）");
                return;
            }
            try next(ctx);
        }
    }.mw };
}

/// 需要授权的「消费能力」路径：资金（支付）、主动触达（客服/模板/群发）、
/// 市场安装。
fn isProtectedPath(path: []const u8) bool {
    if (std.mem.startsWith(u8, path, "/api/v1/payments")) return true;
    if (std.mem.startsWith(u8, path, "/api/v1/messages")) return true;
    if (std.mem.startsWith(u8, path, "/api/v1/cloud/market") and std.mem.endsWith(u8, path, "/install")) return true;
    return false;
}
