//! Persistence over the zent Client — roles, permissions, user-role bindings.

const std = @import("std");
const zent = @import("zent");
const crud = zent.crud_helpers;
const model = @import("model.zig");
const schema = @import("../../schema.zig");

const graph = zent.codegen.graph.buildGraph(&.{ model.Role, model.Permission, model.UserRole });
pub const infos = graph.types;
/// Shared, application-wide typed client (all schemas registered in schema.zig).
pub const Client = schema.Client;
pub const RoleInfo = infos[0];
pub const PermissionInfo = infos[1];
pub const UserRoleInfo = infos[2];

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
        defer zent.codegen.deinitEntity(infos, RoleInfo, &row, self.allocator);
        return row.id;
    }

    pub fn getRoleById(self: *RoleStore, id: i64) !?RoleRow {
        const preds = self.client.role.predicates;
        var entity = (try crud.first(self.client.role, .{preds.idEQ(.{ .int = id })})) orelse return null;
        defer zent.codegen.deinitEntity(infos, RoleInfo, &entity, self.allocator);
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
        defer zent.codegen.deinitEntity(infos, PermissionInfo, &row, self.allocator);
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
        defer zent.codegen.deinitEntity(infos, UserRoleInfo, &row, self.allocator);
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
        defer {
            for (rows.items) |*e| zent.codegen.deinitEntity(infos, UserRoleInfo, e, self.allocator);
            rows.deinit();
        }

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
};
