//! License service — 授权码发行/校验/撤销。No HTTP/SQL leakage。

const std = @import("std");
const zigmodu = @import("zigmodu");
const persist = @import("persistence.zig");

pub const LicenseRow = persist.LicenseRow;
pub const LicenseListResult = persist.LicenseListResult;

pub const LicenseError = error{
    InvalidDays,
    InvalidLicense,
    LicenseExpired,
    NotFound,
    Unexpected,
};

pub const LicenseService = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    store: *persist.LicenseStore,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, store: *persist.LicenseStore) LicenseService {
        return .{ .allocator = allocator, .io = io, .store = store };
    }

    fn now(self: *LicenseService) i64 {
        return zigmodu.time.wallClockSeconds(self.io);
    }

    /// 生成 `WEQ-XXXXXXXX-XXXXXXXX-XXXXXXXX` 授权码（caller free key）。
    fn genKey(self: *LicenseService, allocator: std.mem.Allocator) LicenseError![]const u8 {
        var r: [12]u8 = undefined;
        {
            var file = std.Io.Dir.cwd().openFile(self.io, "/dev/urandom", .{}) catch return error.Unexpected;
            defer file.close(self.io);
            const read = file.readPositionalAll(self.io, &r, 0) catch return error.Unexpected;
            if (read != r.len) return error.Unexpected;
        }
        return std.fmt.allocPrint(allocator, "WEQ-{x:0>8}-{x:0>8}-{x:0>8}", .{
            std.mem.readInt(u32, r[0..4], .little),
            std.mem.readInt(u32, r[4..8], .little),
            std.mem.readInt(u32, r[8..12], .little),
        }) catch error.Unexpected;
    }

    /// 发行授权码（days 有效天数）。返回 caller-owned 行。
    pub fn generate(self: *LicenseService, allocator: std.mem.Allocator, days: i64) LicenseError!LicenseRow {
        if (days <= 0) return error.InvalidDays;
        const key = try self.genKey(allocator);
        defer allocator.free(key);
        const expires_at = self.now() + days * 86400;
        _ = self.store.create(key, expires_at, self.now()) catch return error.Unexpected;
        const row_opt = self.store.getByKey(key) catch return error.Unexpected;
        return row_opt orelse error.NotFound;
    }

    /// 校验授权码（站点端调用）。valid + 状态。
    pub fn verify(self: *LicenseService, license_key: []const u8) LicenseError!bool {
        const row_opt = self.store.getByKey(license_key) catch return error.Unexpected;
        const row = row_opt orelse return error.InvalidLicense;
        defer row.free(self.allocator);
        if (std.mem.eql(u8, row.status, "revoked")) return error.InvalidLicense;
        if (row.expires_at > 0 and self.now() > row.expires_at) {
            self.store.setStatus(row.id, "expired", self.now()) catch {};
            return error.LicenseExpired;
        }
        if (!std.mem.eql(u8, row.status, "active")) return error.InvalidLicense;
        return true;
    }

    pub fn revoke(self: *LicenseService, id: i64) LicenseError!void {
        self.store.setStatus(id, "revoked", self.now()) catch return error.Unexpected;
    }

    pub fn list(self: *LicenseService, page: usize, page_size: usize) LicenseError!LicenseListResult {
        return self.store.list(page, page_size) catch error.Unexpected;
    }
};
