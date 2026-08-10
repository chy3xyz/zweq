//! Module service — built-in module registry + per-account bindings.
//! No HTTP/SQL leakage.

const std = @import("std");
const zigmodu = @import("zigmodu");
const persist = @import("persistence.zig");

pub const AppModuleRow = persist.AppModuleRow;
pub const ModuleBindingRow = persist.ModuleBindingRow;
pub const ModuleListResult = persist.ModuleListResult;

pub const ModuleError = error{
    InvalidName,
    InvalidStatus,
    NotFound,
    Unexpected,
};

/// The built-in modules every site ships with (compile-time set).
pub const builtin_modules = [_][]const u8{
    "account",   "permission", "setting", "rule",
    "member",    "message",    "module",  "payment",
};

pub fn validStatus(status: []const u8) bool {
    return std.mem.eql(u8, status, "active") or std.mem.eql(u8, status, "disabled");
}

pub const ModuleService = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    store: *persist.ModuleStore,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, store: *persist.ModuleStore) ModuleService {
        return .{ .allocator = allocator, .io = io, .store = store };
    }

    fn now(self: *ModuleService) i64 {
        return zigmodu.time.wallClockSeconds(self.io);
    }

    /// Register (upsert) a module in the registry.
    pub fn register(self: *ModuleService, tenant_id: i64, name: []const u8, title: []const u8, version: []const u8) ModuleError!i64 {
        if (std.mem.trim(u8, name, " \t").len == 0) return error.InvalidName;
        return self.store.upsertModule(tenant_id, name, title, version, "active", self.now()) catch error.Unexpected;
    }

    /// Seed the compile-time built-in modules (idempotent).
    pub fn seedBuiltins(self: *ModuleService, tenant_id: i64) !void {
        for (builtin_modules) |m| {
            _ = self.store.upsertModule(tenant_id, m, m, "1.0.0", "active", self.now()) catch {};
        }
    }

    pub fn list(self: *ModuleService, page: usize, page_size: usize, tenant_id: i64) ModuleError!ModuleListResult {
        return self.store.listModules(page, page_size, tenant_id) catch error.Unexpected;
    }

    pub fn bind(self: *ModuleService, tenant_id: i64, account_id: i64, module: []const u8, status: []const u8) ModuleError!i64 {
        if (std.mem.trim(u8, module, " \t").len == 0) return error.InvalidName;
        if (!validStatus(status)) return error.InvalidStatus;
        return self.store.bind(tenant_id, account_id, module, status, self.now()) catch error.Unexpected;
    }

    pub fn unbind(self: *ModuleService, tenant_id: i64, account_id: i64, module: []const u8) ModuleError!void {
        self.store.unbind(tenant_id, account_id, module) catch return error.Unexpected;
    }

    pub fn accountModules(self: *ModuleService, tenant_id: i64, account_id: i64) ModuleError![]ModuleBindingRow {
        return self.store.listBindings(tenant_id, account_id) catch error.Unexpected;
    }
};
