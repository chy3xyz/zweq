//! Persistence over the zent Client — roles, permissions, user-role bindings.

const std = @import("std");
const zent = @import("zent");
const crud = zent.crud_helpers;
const model = @import("model.zig");
const user_persist = @import("../user/persistence.zig");
const schema = @import("../../schema.zig");
const catalog = @import("catalog.zig");

const graph = zent.codegen.graph.buildGraph(&.{ model.Role, model.Permission, model.UserRole, model.RolePermission });
pub const infos = graph.types;
/// Shared, application-wide typed client (all schemas registered in schema.zig).
pub const Client = schema.Client;
pub const RoleInfo = infos[0];
pub const PermissionInfo = infos[1];
pub const UserRoleInfo = infos[2];
pub const RolePermissionInfo = infos[3];

pub const RoleRow = struct {
    id: i64,
    tenant_id: i64,
    name: []const u8,
    code: []const u8,
    description: []const u8,
    created_at: i64,
    updated_at: i64,

    pub fn free(self: RoleRow, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.code);
        allocator.free(self.description);
    }
};

pub const PermissionRow = struct {
    id: i64,
    tenant_id: i64,
    account_id: i64,
    module: []const u8,
    action: []const u8,
    created_at: i64,
    updated_at: i64,

    pub fn free(self: PermissionRow, allocator: std.mem.Allocator) void {
        allocator.free(self.module);
        allocator.free(self.action);
    }
};

pub const RoleListResult = struct {
    items: []RoleRow,
    total: i64,

    pub fn free(self: *RoleListResult, allocator: std.mem.Allocator) void {
        for (self.items) |r| r.free(allocator);
        allocator.free(self.items);
    }
};

pub const PermissionListResult = struct {
    items: []PermissionRow,
    total: i64,

    pub fn free(self: *PermissionListResult, allocator: std.mem.Allocator) void {
        for (self.items) |r| r.free(allocator);
        allocator.free(self.items);
    }
};

pub const UserRoleRow = struct {
    id: i64,
    user_id: i64,
    role_id: i64,
    tenant_id: i64,
    created_at: i64,
};

pub const RoleStore = struct {
    allocator: std.mem.Allocator,
    client: Client,

    pub fn init(allocator: std.mem.Allocator, client: Client) RoleStore {
        return .{ .allocator = allocator, .client = client };
    }

    fn dupRole(self: *RoleStore, e: anytype) !RoleRow {
        const name = try self.allocator.dupe(u8, e.name);
        errdefer self.allocator.free(name);
        const code = try self.allocator.dupe(u8, e.code);
        errdefer self.allocator.free(code);
        const description = try self.allocator.dupe(u8, e.description);
        errdefer self.allocator.free(description);
        return .{
            .id = e.id,
            .tenant_id = e.tenant_id,
            .name = name,
            .code = code,
            .description = description,
            .created_at = e.created_at orelse 0,
            .updated_at = e.updated_at orelse 0,
        };
    }

    fn dupPermission(self: *RoleStore, e: anytype) !PermissionRow {
        const module = try self.allocator.dupe(u8, e.module);
        errdefer self.allocator.free(module);
        const action = try self.allocator.dupe(u8, e.action);
        errdefer self.allocator.free(action);
        return .{
            .id = e.id,
            .tenant_id = e.tenant_id,
            .account_id = e.account_id,
            .module = module,
            .action = action,
            .created_at = e.created_at orelse 0,
            .updated_at = e.updated_at orelse 0,
        };
    }

    pub fn createRole(self: *RoleStore, tenant_id: i64, name: []const u8, code: []const u8, description: []const u8, now: i64) !i64 {
        var row = try crud.create(self.client.role, .{
            .tenant_id = tenant_id,
            .name = name,
            .code = code,
            .description = description,
            .created_at = now,
            .updated_at = now,
        });
        defer self.client.role.deinitRow(&row);
        return row.id;
    }

    pub fn getRoleById(self: *RoleStore, id: i64) !?RoleRow {
        const preds = self.client.role.predicates;
        var entity = (try crud.first(self.client.role, .{preds.idEQ(.{ .int = id })})) orelse return null;
        defer self.client.role.deinitRow(&entity);
        return try self.dupRole(entity);
    }

    pub fn listRoles(self: *RoleStore, page: usize, page_size: usize, tenant_id: ?i64) !RoleListResult {
        var q = self.client.role.Query();
        defer q.deinit();
        const preds = self.client.role.predicates;
        if (tenant_id) |tid| _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tid })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderAsc("id")});

        var paged = try q.paged(page, page_size);
        defer paged.deinit();

        var out = try self.allocator.alloc(RoleRow, paged.items.items.len);
        var n: usize = 0;
        errdefer {
            for (out[0..n]) |r| r.free(self.allocator);
            self.allocator.free(out);
        }
        for (paged.items.items) |e| {
            out[n] = try self.dupRole(e);
            n += 1;
        }
        return .{ .items = out, .total = paged.total };
    }

    pub fn updateRole(self: *RoleStore, id: i64, name: []const u8, code: []const u8, description: []const u8, now: i64) !bool {
        const preds = self.client.role.predicates;
        const affected = try crud.update(self.client.role, .{
            .name = name,
            .code = code,
            .description = description,
            .updated_at = now,
        }, .{preds.idEQ(.{ .int = id })});
        return affected > 0;
    }

    pub fn deleteRole(self: *RoleStore, id: i64) !void {
        const preds = self.client.role.predicates;
        _ = try crud.delete(self.client.role, .{preds.idEQ(.{ .int = id })});
    }

    // ── Permission ────────────────────────────────────────────────

    pub fn createPermission(self: *RoleStore, tenant_id: i64, account_id: i64, module: []const u8, action: []const u8, now: i64) !i64 {
        var row = try crud.create(self.client.permission, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .module = module,
            .action = action,
            .created_at = now,
            .updated_at = now,
        });
        defer self.client.permission.deinitRow(&row);
        return row.id;
    }

    pub fn listPermissions(self: *RoleStore, page: usize, page_size: usize, tenant_id: ?i64, account_id: ?i64) !PermissionListResult {
        var q = self.client.permission.Query();
        defer q.deinit();
        const preds = self.client.permission.predicates;
        if (tenant_id) |tid| _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tid })});
        if (account_id) |aid| _ = try q.Where(.{preds.account_idEQ(.{ .int = aid })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderAsc("id")});

        var paged = try q.paged(page, page_size);
        defer paged.deinit();

        var out = try self.allocator.alloc(PermissionRow, paged.items.items.len);
        var n: usize = 0;
        errdefer {
            for (out[0..n]) |r| r.free(self.allocator);
            self.allocator.free(out);
        }
        for (paged.items.items) |e| {
            out[n] = try self.dupPermission(e);
            n += 1;
        }
        return .{ .items = out, .total = paged.total };
    }

    pub fn deletePermission(self: *RoleStore, id: i64) !void {
        const preds = self.client.permission.predicates;
        _ = try crud.delete(self.client.permission, .{preds.idEQ(.{ .int = id })});
    }

    // ── UserRole ──────────────────────────────────────────────────

    pub fn assignRole(self: *RoleStore, tenant_id: i64, user_id: i64, role_id: i64, now: i64) !i64 {
        // Idempotent: drop an existing binding first so reassign is an upsert.
        try self.removeRole(user_id, role_id);
        var row = try crud.create(self.client.user_role, .{
            .tenant_id = tenant_id,
            .user_id = user_id,
            .role_id = role_id,
            .created_at = now,
        });
        defer self.client.user_role.deinitRow(&row);
        return row.id;
    }

    pub fn removeRole(self: *RoleStore, user_id: i64, role_id: i64) !void {
        const preds = self.client.user_role.predicates;
        _ = try crud.delete(self.client.user_role, .{ preds.user_idEQ(.{ .int = user_id }), preds.role_idEQ(.{ .int = role_id }) });
    }

    pub fn listRolesForUser(self: *RoleStore, user_id: i64) ![]UserRoleRow {
        var q = self.client.user_role.Query();
        defer q.deinit();
        const preds = self.client.user_role.predicates;
        _ = try q.Where(.{preds.user_idEQ(.{ .int = user_id })});
        var rows = try q.All();
        defer self.client.user_role.deinitRows(&rows);

        var out = try self.allocator.alloc(UserRoleRow, rows.items.len);
        errdefer self.allocator.free(out);
        for (rows.items, 0..) |e, i| {
            out[i] = .{
                .id = e.id,
                .user_id = e.user_id,
                .role_id = e.role_id,
                .tenant_id = e.tenant_id,
                .created_at = e.created_at orelse 0,
            };
        }
        return out;
    }

    pub fn removeAllRolesForUser(self: *RoleStore, user_id: i64) !void {
        const preds = self.client.user_role.predicates;
        var d = self.client.user_role.Delete();
        defer d.deinit();
        _ = try d.Where(.{preds.user_idEQ(.{ .int = user_id })});
        _ = try d.Exec();
    }

    /// Total roles count (dashboard stats).
    pub fn countAll(self: *RoleStore) !i64 {
        var q = self.client.role.Query();
        defer q.deinit();
        return @intCast(try q.Count());
    }

    // ── RolePermission ────────────────────────────────────────────

    pub fn bindPermission(self: *RoleStore, tenant_id: i64, role_id: i64, permission_id: i64, now: i64) !i64 {
        try self.unbindPermission(role_id, permission_id);
        var row = try crud.create(self.client.role_permission, .{
            .tenant_id = tenant_id,
            .role_id = role_id,
            .permission_id = permission_id,
            .created_at = now,
            .updated_at = now,
        });
        defer self.client.role_permission.deinitRow(&row);
        return row.id;
    }

    pub fn unbindPermission(self: *RoleStore, role_id: i64, permission_id: i64) !void {
        const preds = self.client.role_permission.predicates;
        _ = try crud.delete(self.client.role_permission, .{ preds.role_idEQ(.{ .int = role_id }), preds.permission_idEQ(.{ .int = permission_id }) });
    }

    pub fn listPermissionsForRole(self: *RoleStore, role_id: i64) ![]PermissionRow {
        var rp_q = self.client.role_permission.Query();
        defer rp_q.deinit();
        const rp_preds = self.client.role_permission.predicates;
        _ = try rp_q.Where(.{rp_preds.role_idEQ(.{ .int = role_id })});
        var rp_rows = try rp_q.All();
        defer self.client.role_permission.deinitRows(&rp_rows);

        var out = try self.allocator.alloc(PermissionRow, 0);
        errdefer self.allocator.free(out);
        for (rp_rows.items) |rp| {
            const perm_opt = try self.getPermissionById(rp.permission_id) orelse continue;
            const new_len = out.len + 1;
            out = try self.allocator.realloc(out, new_len);
            out[new_len - 1] = perm_opt;
        }
        return out;
    }

    pub fn getPermissionById(self: *RoleStore, id: i64) !?PermissionRow {
        const preds = self.client.permission.predicates;
        var entity = (try crud.first(self.client.permission, .{preds.idEQ(.{ .int = id })})) orelse return null;
        defer self.client.permission.deinitRow(&entity);
        return try self.dupPermission(entity);
    }

    fn appendUniqueCode(codes: *std.ArrayList([]const u8), allocator: std.mem.Allocator, code: []const u8) !void {
        for (codes.items) |c| {
            if (std.mem.eql(u8, c, code)) return;
        }
        try codes.append(allocator, try allocator.dupe(u8, code));
    }

    /// Effective permission codes for RBAC gate / frontend menu (CSV-ready).
    /// Includes: user.admin → "admin"; role codes; role-bound module:action.
    pub fn collectPermissionCodes(self: *RoleStore, allocator: std.mem.Allocator, user_id: i64) ![]u8 {
        var codes = std.ArrayList([]const u8).empty;
        defer {
            for (codes.items) |c| allocator.free(c);
            codes.deinit(allocator);
        }

        const user_preds = self.client.user.predicates;
        var superuser = false;
        if ((try crud.first(self.client.user, .{user_preds.idEQ(.{ .int = user_id })}))) |found| {
            var entity = found;
            defer self.client.user.deinitRow(&entity);
            if (entity.admin) {
                try appendUniqueCode(&codes, allocator, "admin");
                superuser = true;
            }
        }

        const user_roles = try self.listRolesForUser(user_id);
        defer self.allocator.free(user_roles);

        for (user_roles) |ur| {
            const role = try self.getRoleById(ur.role_id) orelse continue;
            defer role.free(self.allocator);
            try appendUniqueCode(&codes, allocator, role.code);
            if (std.mem.eql(u8, role.code, "founder") or std.mem.eql(u8, role.code, "admin")) {
                superuser = true;
            }

            const role_perms = try self.listPermissionsForRole(ur.role_id);
            defer {
                for (role_perms) |p| p.free(self.allocator);
                self.allocator.free(role_perms);
            }
            for (role_perms) |perm| {
                var buf: [128]u8 = undefined;
                const ma = try std.fmt.bufPrint(&buf, "{s}:{s}", .{ perm.module, perm.action });
                try appendUniqueCode(&codes, allocator, ma);
                if (std.mem.eql(u8, perm.action, "write")) {
                    var rb: [128]u8 = undefined;
                    const read_code = try std.fmt.bufPrint(&rb, "{s}:read", .{perm.module});
                    try appendUniqueCode(&codes, allocator, read_code);
                }
            }
        }

        if (superuser) {
            for (catalog.entries) |entry| {
                var buf: [128]u8 = undefined;
                const ma = try std.fmt.bufPrint(&buf, "{s}:{s}", .{ entry.module, entry.action });
                try appendUniqueCode(&codes, allocator, ma);
            }
        }

        if (codes.items.len == 0) {
            return try allocator.dupe(u8, "");
        }

        var total_len: usize = 0;
        for (codes.items) |c| total_len += c.len;
        total_len += codes.items.len - 1;

        var out = try allocator.alloc(u8, total_len);
        var off: usize = 0;
        for (codes.items, 0..) |code, i| {
            if (i > 0) {
                out[off] = ',';
                off += 1;
            }
            @memcpy(out[off..][0..code.len], code);
            off += code.len;
        }
        return out;
    }
};
