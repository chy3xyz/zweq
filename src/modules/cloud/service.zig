//! Cloud service — site licenses (授权码) + marketplace (应用市场).
//! No HTTP/SQL leakage. `installPackage` feeds the module registry + binding.

const std = @import("std");
const zigmodu = @import("zigmodu");
const persist = @import("persistence.zig");
const module_svc_mod = @import("../module/service.zig");

pub const LicenseRow = persist.LicenseRow;
pub const LicenseListResult = persist.LicenseListResult;
pub const MarketPackageRow = persist.MarketPackageRow;
pub const MarketListResult = persist.MarketListResult;

pub const CloudError = error{
    InvalidName,
    InvalidDays,
    InvalidLicense,
    LicenseExpired,
    NotFound,
    Unexpected,
};

pub const CloudService = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    store: *persist.CloudStore,
    module_svc: *module_svc_mod.ModuleService,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, store: *persist.CloudStore, module_svc: *module_svc_mod.ModuleService) CloudService {
        return .{ .allocator = allocator, .io = io, .store = store, .module_svc = module_svc };
    }

    fn now(self: *CloudService) i64 {
        return zigmodu.time.wallClockSeconds(self.io);
    }

    /// Generate a license key `WEQ-XXXXXXXX-XXXXXXXX-XXXXXXXX`.
    fn genLicenseKey(self: *CloudService, allocator: std.mem.Allocator) ![]const u8 {
        var r: [12]u8 = undefined;
        {
            var file = try std.Io.Dir.cwd().openFile(self.io, "/dev/urandom", .{});
            errdefer file.close(self.io);
            const read = try file.readPositionalAll(self.io, &r, 0);
            if (read != r.len) return error.Unexpected;
        }
        return std.fmt.allocPrint(allocator, "WEQ-{x:0>8}-{x:0>8}-{x:0>8}", .{
            std.mem.readInt(u32, r[0..4], .little),
            std.mem.readInt(u32, r[4..8], .little),
            std.mem.readInt(u32, r[8..12], .little),
        });
    }

    /// Issue a new license valid for `days`. Returns the row (caller frees).
    pub fn generateLicense(self: *CloudService, allocator: std.mem.Allocator, tenant_id: i64, days: i64) CloudError!LicenseRow {
        if (days <= 0) return error.InvalidDays;
        const key = self.genLicenseKey(allocator) catch return error.Unexpected;
        defer allocator.free(key);
        const expires_at = self.now() + days * 86400;
        _ = self.store.createLicense(tenant_id, key, expires_at, self.now()) catch return error.Unexpected;
        const row_opt = self.store.getLicenseByKey(tenant_id, key) catch return error.Unexpected;
        return row_opt orelse error.NotFound;
    }

    /// Verify a license is active and unexpired.
    pub fn verifyLicense(self: *CloudService, tenant_id: i64, license_key: []const u8) CloudError!bool {
        const row_opt = self.store.getLicenseByKey(tenant_id, license_key) catch return error.Unexpected;
        const row = row_opt orelse return error.InvalidLicense;
        defer row.free(self.allocator);
        if (std.mem.eql(u8, row.status, "revoked")) return error.InvalidLicense;
        if (row.expires_at > 0 and self.now() > row.expires_at) {
            self.store.setLicenseStatus(row.id, "expired", self.now()) catch {};
            return error.LicenseExpired;
        }
        if (!std.mem.eql(u8, row.status, "active")) return error.InvalidLicense;
        return true;
    }

    pub fn listLicenses(self: *CloudService, page: usize, page_size: usize, tenant_id: i64) CloudError!LicenseListResult {
        return self.store.listLicenses(page, page_size, tenant_id) catch error.Unexpected;
    }

    pub fn revokeLicense(self: *CloudService, id: i64) CloudError!void {
        self.store.setLicenseStatus(id, "revoked", self.now()) catch return error.Unexpected;
    }

    pub fn listMarket(self: *CloudService, page: usize, page_size: usize, tenant_id: i64) CloudError!MarketListResult {
        return self.store.listMarket(page, page_size, tenant_id) catch error.Unexpected;
    }

    pub fn publishPackage(self: *CloudService, tenant_id: i64, name: []const u8, title: []const u8, version: []const u8, description: []const u8, download_url: []const u8) CloudError!i64 {
        if (std.mem.trim(u8, name, " \t").len == 0) return error.InvalidName;
        return self.store.upsertPackage(tenant_id, name, title, version, description, download_url, self.now()) catch error.Unexpected;
    }

    /// "Install" a marketplace package: register it in the module registry and
    /// optionally bind it to an account. Returns the module registry id.
    pub fn installPackage(self: *CloudService, tenant_id: i64, name: []const u8, account_id: i64) CloudError!i64 {
        if (std.mem.trim(u8, name, " \t").len == 0) return error.InvalidName;
        const pkg_opt = self.store.getPackageByName(tenant_id, name) catch return error.Unexpected;
        const pkg = pkg_opt orelse return error.NotFound;
        defer pkg.free(self.allocator);
        const module_id = self.module_svc.register(tenant_id, pkg.name, pkg.title, pkg.version) catch return error.Unexpected;
        if (account_id > 0) {
            _ = self.module_svc.bind(tenant_id, account_id, pkg.name, "active") catch return error.Unexpected;
        }
        return module_id;
    }
};
