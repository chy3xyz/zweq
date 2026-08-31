//! C 端粉丝 JWT 解析（roles 含 fan，sub = openid）。

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const user_svc = @import("../modules/user/service.zig");

pub const FanAuthError = error{Unauthorized};

/// 从 `Authorization: Bearer` 解析粉丝 openid；返回 owned 字符串（调用方 free）。
pub fn requireFanOpenid(ctx: *http.Context, users: *user_svc.UserService) FanAuthError![]const u8 {
    const header = ctx.headers.get("authorization") orelse return error.Unauthorized;
    if (header.len < 7 or !std.mem.startsWith(u8, header, "Bearer ")) return error.Unauthorized;
    const token = header[7..];
    const payload = users.sec.module.verifyToken(token) catch return error.Unauthorized;
    defer {
        users.store.allocator.free(payload.sub);
        users.store.allocator.free(payload.iss);
        users.store.allocator.free(payload.aud);
        for (payload.roles) |r| users.store.allocator.free(r);
        users.store.allocator.free(payload.roles);
    }
    var is_fan = false;
    for (payload.roles) |r| {
        if (std.mem.eql(u8, r, "fan")) {
            is_fan = true;
            break;
        }
    }
    if (!is_fan) return error.Unauthorized;
    return ctx.allocator.dupe(u8, payload.sub) catch return error.Unauthorized;
}
