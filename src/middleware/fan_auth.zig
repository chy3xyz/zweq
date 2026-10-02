//! C 端粉丝身份读取（薄壳）。
//!
//! 验签已迁到框架声明式鉴权：路由 meta 标 `.auth = .jwt`（需身份/经济接口）
//! 或 `.auth = .optional`（公开列表但可个性化），由
//! `jwtAuthFromCatalogWithPermissions` 在中间件层验签并把身份写入 ctx
//! 属性（`user_id` = fan token 的 `sub` = openid，`roles` = 角色 CSV）。
//! 本文件不再做任何 Bearer 截取 / HMAC 本地验签（原实现与 rate_limit.zig
//! 的退化验签一并移除），只读取框架注入的属性并校验 fan 角色。

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;

pub const FanAuthError = error{Unauthorized};

/// 从框架注入的 ctx 属性读粉丝 openid（`.jwt` 路由用）。
/// 身份存在性已由路由 meta `.auth = .jwt` 保证（中间件对无/无效 token
/// 直接 401）；这里再校验 roles 含 `fan` —— 管理端 token 与粉丝 token
/// 同一 AppSecurity 签发，薄壳保留旧行为：管理端 token 打 C 端接口一律 401。
/// 返回的 openid 借用 ctx 属性（生命周期随请求 arena），调用方不得 free。
pub fn requireFanOpenid(ctx: *http.Context) FanAuthError![]const u8 {
    const openid = ctx.userId() orelse return error.Unauthorized;
    if (!isFan(ctx)) return error.Unauthorized;
    return openid;
}

/// `.optional` 路由（公开列表但可个性化）用：带合法粉丝 token 时返回
/// openid，未带 token 或 token 非粉丝身份时返回 null（按匿名公开处理，
/// 永不 401——与 `.optional` 语义一致）。返回的 openid 借用 ctx 属性，
/// 调用方不得 free。
pub fn optionalFanOpenid(ctx: *http.Context) ?[]const u8 {
    const openid = ctx.userId() orelse return null;
    if (!isFan(ctx)) return null;
    return openid;
}

fn isFan(ctx: *http.Context) bool {
    const csv = ctx.rolesCsv() orelse return false;
    var it = std.mem.splitScalar(u8, csv, ',');
    while (it.next()) |r| {
        if (std.mem.eql(u8, std.mem.trim(u8, r, " \t"), "fan")) return true;
    }
    return false;
}
