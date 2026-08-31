//! Idempotent seed: default roles + catalog permissions + admin role bindings.

const std = @import("std");
const catalog = @import("permission_catalog.zig");
const permission = @import("modules/permission/root.zig");

pub fn seedDefaults(allocator: std.mem.Allocator, io: std.Io, store: *permission.persistence.RoleStore, tenant_id: i64) !void {
    const now = @import("zigmodu").time.wallClockSeconds(io);
    var svc = permission.service.RoleService.init(allocator, io, store);

    // ── Permissions (module:action) ───────────────────────────────
    var perm_ids = std.ArrayList(i64).empty;
    defer perm_ids.deinit(allocator);
    for (catalog.entries) |entry| {
        const existing = try findPermission(store, tenant_id, entry.module, entry.action);
        if (existing) |id| {
            try perm_ids.append(allocator, id);
        } else {
            const id = try svc.grant(tenant_id, 0, entry.module, entry.action);
            try perm_ids.append(allocator, id);
        }
    }

    // ── Built-in roles ────────────────────────────────────────────
    const founder_id = try ensureRole(&svc, allocator, tenant_id, "创始人", "founder", "站点创始人，拥有全部权限");
    const admin_id = try ensureRole(&svc, allocator, tenant_id, "管理员", "admin", "管理员，拥有全部权限");
    const operator_id = try ensureRole(&svc, allocator, tenant_id, "操作员", "operator", "日常运营，按绑定权限访问");

    // founder/admin → all catalog permissions
    for (perm_ids.items) |pid| {
        _ = try store.bindPermission(tenant_id, founder_id, pid, now);
        _ = try store.bindPermission(tenant_id, admin_id, pid, now);
    }

    // operator → read-only defaults (write 需手动绑定)
    for (catalog.entries) |entry| {
        if (!std.mem.eql(u8, entry.action, "read")) continue;
        if (try findPermission(store, tenant_id, entry.module, entry.action)) |pid| {
            _ = try store.bindPermission(tenant_id, operator_id, pid, now);
        }
    }

    std.log.info("[permission] catalog seeded ({d} permissions, roles founder/admin/operator)", .{perm_ids.items.len});
}

fn findPermission(store: *permission.persistence.RoleStore, tenant_id: i64, module: []const u8, action: []const u8) !?i64 {
    var list = try store.listPermissions(1, 500, tenant_id, null);
    defer list.free(store.allocator);
    for (list.items) |p| {
        if (std.mem.eql(u8, p.module, module) and std.mem.eql(u8, p.action, action)) {
            return p.id;
        }
    }
    return null;
}

fn ensureRole(
    svc: *permission.service.RoleService,
    allocator: std.mem.Allocator,
    tenant_id: i64,
    name: []const u8,
    code: []const u8,
    description: []const u8,
) !i64 {
    var list = try svc.list(1, 100, tenant_id);
    defer list.free(allocator);
    for (list.items) |r| {
        if (std.mem.eql(u8, r.code, code)) return r.id;
    }
    return svc.create(tenant_id, name, code, description) catch |err| switch (err) {
        error.InvalidCode, error.InvalidName => {
            // Role may exist under different casing — lookup again.
            var again = try svc.list(1, 100, tenant_id);
            defer again.free(allocator);
            for (again.items) |r| {
                if (std.mem.eql(u8, r.code, code)) return r.id;
            }
            return error.Unexpected;
        },
        else => return err,
    };
}
