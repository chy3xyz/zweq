//! Permission service — role CRUD, permission grants, user-role binding.
//! No HTTP/SQL leakage.

const std = @import("std");
const zigmodu = @import("zigmodu");
const persist = @import("persistence.zig");

pub const RoleRow = persist.RoleRow;
pub const PermissionRow = persist.PermissionRow;
pub const RoleListResult = persist.RoleListResult;
pub const PermissionListResult = persist.PermissionListResult;

pub const PermissionError = error{
    InvalidName,
    InvalidCode,
    NotFound,
    Unexpected,
};

/// WeEngine role codes.
pub fn validCode(code: []const u8) bool {
    return std.mem.eql(u8, code, "founder") or
        std.mem.eql(u8, code, "admin") or
        std.mem.eql(u8, code, "operator");
}

pub const RoleService = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    store: *persist.RoleStore,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, store: *persist.RoleStore) RoleService {
        return .{ .allocator = allocator, .io = io, .store = store };
    }

    fn now(self: *RoleService) i64 {
        return zigmodu.time.wallClockSeconds(self.io);
    }

    pub fn create(self: *RoleService, tenant_id: i64, name: []const u8, code: []const u8, description: []const u8) PermissionError!i64 {
        if (std.mem.trim(u8, name, " \t").len == 0) return error.InvalidName;
        if (!validCode(code)) return error.InvalidCode;
        return self.store.createRole(tenant_id, name, code, description, self.now()) catch error.Unexpected;
    }

    pub fn get(self: *RoleService, id: i64) PermissionError!?RoleRow {
        return self.store.getRoleById(id) catch error.Unexpected;
    }

    pub fn list(self: *RoleService, page: usize, page_size: usize, tenant_id: ?i64) PermissionError!RoleListResult {
        return self.store.listRoles(page, page_size, tenant_id) catch error.Unexpected;
    }

    pub fn update(self: *RoleService, id: i64, name: []const u8, code: []const u8, description: []const u8) PermissionError!bool {
        if (std.mem.trim(u8, name, " \t").len == 0) return error.InvalidName;
        if (!validCode(code)) return error.InvalidCode;
        return self.store.updateRole(id, name, code, description, self.now()) catch error.Unexpected;
    }

    pub fn delete(self: *RoleService, id: i64) PermissionError!void {
        self.store.deleteRole(id) catch return error.Unexpected;
    }

    pub fn grant(self: *RoleService, tenant_id: i64, account_id: i64, module: []const u8, action: []const u8) PermissionError!i64 {
        if (std.mem.trim(u8, module, " \t").len == 0 or std.mem.trim(u8, action, " \t").len == 0) return error.InvalidName;
        return self.store.createPermission(tenant_id, account_id, module, action, self.now()) catch error.Unexpected;
    }

    pub fn listPermissions(self: *RoleService, page: usize, page_size: usize, tenant_id: ?i64, account_id: ?i64) PermissionError!PermissionListResult {
        return self.store.listPermissions(page, page_size, tenant_id, account_id) catch error.Unexpected;
    }

    pub fn revoke(self: *RoleService, id: i64) PermissionError!void {
        self.store.deletePermission(id) catch return error.Unexpected;
    }

    pub fn assignRole(self: *RoleService, tenant_id: i64, user_id: i64, role_id: i64) PermissionError!i64 {
        return self.store.assignRole(tenant_id, user_id, role_id, self.now()) catch error.Unexpected;
    }

    pub fn listRolesForUser(self: *RoleService, user_id: i64) PermissionError![]persist.UserRoleRow {
        return self.store.listRolesForUser(user_id) catch error.Unexpected;
    }
};
