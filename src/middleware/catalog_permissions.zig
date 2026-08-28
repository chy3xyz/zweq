//! Catalog-based RBAC permission loader.
//!
//! Bridges `role` / `user_role` / `role_permission` tables to zigmodu's
//! `jwtAuthFromCatalogWithPermissions` + `permissionGateWith(.rbac)`.
//! Effective codes: user.admin → "admin"; role codes; bound module:action.

const std = @import("std");
const zigmodu = @import("zigmodu");
const permission = @import("../modules/permission/root.zig");

var g_store: ?*permission.persistence.RoleStore = null;

/// Initialize the loader with the shared role store. Call once at startup
/// after the store is fully initialized.
pub fn init(store: *permission.persistence.RoleStore) void {
    g_store = store;
}

fn storeRef() ?*permission.persistence.RoleStore {
    return g_store;
}

/// Split a CSV permission string into an owned slice of code strings.
pub fn splitCodes(allocator: std.mem.Allocator, csv: []const u8) ![][]const u8 {
    if (csv.len == 0) return try allocator.alloc([]const u8, 0);
    var parts = std.ArrayList([]const u8).empty;
    defer parts.deinit(allocator);
    var it = std.mem.splitScalar(u8, csv, ',');
    while (it.next()) |part| {
        const trimmed = std.mem.trim(u8, part, " \t");
        if (trimmed.len == 0) continue;
        try parts.append(allocator, try allocator.dupe(u8, trimmed));
    }
    return try parts.toOwnedSlice(allocator);
}

/// Effective permission codes for a user id (owned slice of owned strings).
pub fn listCodes(allocator: std.mem.Allocator, user_id: i64) ![][]const u8 {
    const store = storeRef() orelse return error.CatalogPermissionsNotInitialized;
    const csv = try store.collectPermissionCodes(allocator, user_id);
    defer allocator.free(csv);
    return try splitCodes(allocator, csv);
}

/// ZigModu `CatalogPermissionLoader` signature.
pub fn load(allocator: std.mem.Allocator, input: zigmodu.http.CatalogPermLoadInput) anyerror![]u8 {
    const store = storeRef() orelse return error.CatalogPermissionsNotInitialized;
    const user_id = std.fmt.parseInt(i64, input.sub, 10) catch {
        return try allocator.dupe(u8, "");
    };
    return try store.collectPermissionCodes(allocator, user_id);
}
