//! Canonical RBAC permission codes (module:action) for zweq admin areas.
//! Seeded into `permission` table on startup; bound to roles via `role_permission`.

pub const Entry = struct {
    module: []const u8,
    action: []const u8,
};

pub const entries = [_]Entry{
    .{ .module = "system", .action = "read" },
    .{ .module = "user", .action = "read" },
    .{ .module = "user", .action = "write" },
    .{ .module = "permission", .action = "read" },
    .{ .module = "permission", .action = "write" },
    .{ .module = "account", .action = "read" },
    .{ .module = "account", .action = "write" },
    .{ .module = "rule", .action = "read" },
    .{ .module = "rule", .action = "write" },
    .{ .module = "member", .action = "read" },
    .{ .module = "member", .action = "write" },
    .{ .module = "payment", .action = "read" },
    .{ .module = "payment", .action = "write" },
    .{ .module = "module", .action = "read" },
    .{ .module = "module", .action = "write" },
    .{ .module = "cloud", .action = "read" },
    .{ .module = "cloud", .action = "write" },
    .{ .module = "message", .action = "read" },
    .{ .module = "message", .action = "write" },
    .{ .module = "material", .action = "read" },
    .{ .module = "material", .action = "write" },
    .{ .module = "points", .action = "read" },
    .{ .module = "points", .action = "write" },
    .{ .module = "menu", .action = "read" },
    .{ .module = "menu", .action = "write" },
    .{ .module = "checkin", .action = "read" },
    .{ .module = "lucky_draw", .action = "read" },
    .{ .module = "lucky_draw", .action = "write" },
    .{ .module = "coupon", .action = "read" },
    .{ .module = "coupon", .action = "write" },
    .{ .module = "vote", .action = "read" },
    .{ .module = "vote", .action = "write" },
    .{ .module = "seckill", .action = "read" },
    .{ .module = "seckill", .action = "write" },
    .{ .module = "member_card", .action = "read" },
    .{ .module = "member_card", .action = "write" },
    .{ .module = "shop", .action = "read" },
    .{ .module = "shop", .action = "write" },
    .{ .module = "distribution", .action = "read" },
    .{ .module = "distribution", .action = "write" },
    .{ .module = "ai", .action = "read" },
    .{ .module = "ai", .action = "write" },
    .{ .module = "audit", .action = "read" },
    .{ .module = "mail_template", .action = "read" },
    .{ .module = "mail_template", .action = "write" },
    .{ .module = "task", .action = "read" },
    .{ .module = "task", .action = "write" },
    .{ .module = "tenant", .action = "read" },
    .{ .module = "tenant", .action = "write" },
    .{ .module = "setting", .action = "read" },
    .{ .module = "setting", .action = "write" },
};

pub fn code(entry: Entry) struct { module: []const u8, action: []const u8 } {
    return .{ .module = entry.module, .action = entry.action };
}

pub fn codeStr(buf: []u8, entry: Entry) ![]const u8 {
    return std.fmt.bufPrint(buf, "{s}:{s}", .{ entry.module, entry.action });
}

const std = @import("std");
