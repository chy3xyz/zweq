//! Setting service — tenant-scoped key-value store. No HTTP/SQL leakage.

const std = @import("std");
const zigmodu = @import("zigmodu");
const persist = @import("persistence.zig");

pub const SettingRow = persist.SettingRow;
pub const SettingListResult = persist.SettingListResult;

pub const SettingError = error{
    InvalidKey,
    Unexpected,
};

pub const SettingService = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    store: *persist.SettingStore,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, store: *persist.SettingStore) SettingService {
        return .{ .allocator = allocator, .io = io, .store = store };
    }

    fn now(self: *SettingService) i64 {
        return zigmodu.time.wallClockSeconds(self.io);
    }

    pub fn get(self: *SettingService, tenant_id: i64, key: []const u8) SettingError!?SettingRow {
        return self.store.get(tenant_id, key) catch error.Unexpected;
    }

    pub fn set(self: *SettingService, tenant_id: i64, key: []const u8, value: []const u8) SettingError!i64 {
        if (std.mem.trim(u8, key, " \t").len == 0) return error.InvalidKey;
        return self.store.set(tenant_id, key, value, self.now()) catch error.Unexpected;
    }

    pub fn list(self: *SettingService, page: usize, page_size: usize, tenant_id: i64) SettingError!SettingListResult {
        return self.store.list(page, page_size, tenant_id) catch error.Unexpected;
    }

    pub fn delete(self: *SettingService, tenant_id: i64, key: []const u8) SettingError!void {
        self.store.delete(tenant_id, key) catch return error.Unexpected;
    }
};
