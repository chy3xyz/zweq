//! Admin sidebar nav builder — filters compile-time catalog by RBAC + account bindings.

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const catalog = @import("catalog.zig");
const catalog_permissions = @import("../middleware/catalog_permissions.zig");
const mw = @import("../middleware/auth.zig");
const module_svc = @import("../modules/module/service.zig");
const user_svc = @import("../modules/user/service.zig");

const NavItemDto = struct {
    module: []const u8,
    group: []const u8,
    subgroup: []const u8,
    href: []const u8,
    label: []const u8,
    permission: []const u8,
    order: u16,
};

fn hasCode(codes: []const []const u8, want: []const u8) bool {
    for (codes) |c| {
        if (std.mem.eql(u8, c, want) or std.mem.eql(u8, c, "admin")) return true;
    }
    return false;
}

fn moduleActive(
    module_name: []const u8,
    bindings: []const module_svc.ModuleBindingRow,
    has_bindings: bool,
) bool {
    if (!has_bindings) return true;
    for (bindings) |b| {
        if (std.mem.eql(u8, b.module, module_name) and std.mem.eql(u8, b.status, "active")) return true;
    }
    return false;
}

pub fn buildAdminNav(
    allocator: std.mem.Allocator,
    user_id: i64,
    is_admin: bool,
    tenant_id: i64,
    account_id: ?i64,
    mod_svc: *module_svc.ModuleService,
) ![]NavItemDto {
    const perms = try catalog_permissions.listCodes(allocator, user_id);
    defer {
        for (perms) |p| allocator.free(p);
        allocator.free(perms);
    }

    var bindings: []module_svc.ModuleBindingRow = &.{};
    var owns_bindings = false;
    defer {
        if (owns_bindings) {
            for (bindings) |b| b.free(mod_svc.allocator);
            mod_svc.allocator.free(bindings);
        }
    }
    var has_bindings = false;
    if (account_id) |aid| {
        bindings = mod_svc.accountModules(tenant_id, aid) catch &.{};
        owns_bindings = bindings.len > 0;
        has_bindings = bindings.len > 0;
    }

    var out = std.ArrayList(NavItemDto).empty;
    errdefer out.deinit(allocator);

    for (catalog.items) |item| {
        if (!is_admin and !hasCode(perms, item.permission)) continue;
        if (item.account_scoped and account_id != null) {
            if (!moduleActive(item.module, bindings, has_bindings)) continue;
        }
        try out.append(allocator, .{
            .module = item.module,
            .group = item.group,
            .subgroup = item.subgroup,
            .href = item.href,
            .label = item.label,
            .permission = item.permission,
            .order = item.order,
        });
    }

    return try out.toOwnedSlice(allocator);
}

pub fn handleAdminNav(
    ctx: *http.Context,
    mod_svc: *module_svc.ModuleService,
    default_tenant_id: i64,
    users: *user_svc.UserService,
) !void {
    const uid = ctx.userIdInt(i64) orelse {
        try ctx.sendErrorResponse(401, 401, "未登录");
        return;
    };
    const tid = mw.authTenantId(ctx) orelse default_tenant_id;

    const row_opt = users.getUserById(uid) catch {
        try ctx.sendErrorResponse(500, 500, "用户查询失败");
        return;
    };
    const row = row_opt orelse {
        try ctx.sendErrorResponse(401, 401, "用户不存在");
        return;
    };
    defer row.free(users.store.allocator);

    const account_id: ?i64 = if (ctx.queryParam("account_id")) |raw|
        std.fmt.parseInt(i64, raw, 10) catch null
    else
        null;

    const items = try buildAdminNav(ctx.allocator, uid, row.admin, tid, account_id, mod_svc);
    try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = .{ .items = items } });
}
