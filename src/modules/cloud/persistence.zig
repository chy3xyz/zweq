//! Persistence over the zent Client — licenses + marketplace packages.

const std = @import("std");
const zent = @import("zent");
const model = @import("model.zig");
const schema = @import("../../schema.zig");

const graph = zent.codegen.graph.buildGraph(&.{ model.License, model.MarketPackage });
pub const infos = graph.types;
/// Shared, application-wide typed client (all schemas registered in schema.zig).
pub const Client = schema.Client;
pub const LicenseInfo = infos[0];
pub const MarketPackageInfo = infos[1];

pub const LicenseRow = struct {
    id: i64,
    tenant_id: i64,
    license_key: []const u8,
    status: []const u8,
    expires_at: i64,
    created_at: i64,
    updated_at: i64,

    pub fn free(self: LicenseRow, allocator: std.mem.Allocator) void {
        allocator.free(self.license_key);
        allocator.free(self.status);
    }
};

pub const LicenseListResult = struct {
    items: []LicenseRow,
    total: i64,

    pub fn free(self: *LicenseListResult, allocator: std.mem.Allocator) void {
        for (self.items) |r| r.free(allocator);
        allocator.free(self.items);
    }
};

pub const MarketPackageRow = struct {
    id: i64,
    tenant_id: i64,
    name: []const u8,
    title: []const u8,
    version: []const u8,
    description: []const u8,
    download_url: []const u8,
    created_at: i64,
    updated_at: i64,

    pub fn free(self: MarketPackageRow, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.title);
        allocator.free(self.version);
        allocator.free(self.description);
        allocator.free(self.download_url);
    }
};

pub const MarketListResult = struct {
    items: []MarketPackageRow,
    total: i64,

    pub fn free(self: *MarketListResult, allocator: std.mem.Allocator) void {
        for (self.items) |r| r.free(allocator);
        allocator.free(self.items);
    }
};

pub const CloudStore = struct {
    allocator: std.mem.Allocator,
    client: Client,

    pub fn init(allocator: std.mem.Allocator, client: Client) CloudStore {
        return .{ .allocator = allocator, .client = client };
    }

    fn dupLicense(self: *CloudStore, e: anytype) !LicenseRow {
        const license_key = try self.allocator.dupe(u8, e.license_key);
        errdefer self.allocator.free(license_key);
        const status = try self.allocator.dupe(u8, e.status);
        errdefer self.allocator.free(status);
        return .{
            .id = e.id,
            .tenant_id = e.tenant_id,
            .license_key = license_key,
            .status = status,
            .expires_at = e.expires_at,
            .created_at = e.created_at orelse 0,
            .updated_at = e.updated_at orelse 0,
        };
    }

    fn dupPackage(self: *CloudStore, e: anytype) !MarketPackageRow {
        const name = try self.allocator.dupe(u8, e.name);
        errdefer self.allocator.free(name);
        const title = try self.allocator.dupe(u8, e.title);
        errdefer self.allocator.free(title);
        const version = try self.allocator.dupe(u8, e.version);
        errdefer self.allocator.free(version);
        const description = try self.allocator.dupe(u8, e.description);
        errdefer self.allocator.free(description);
        const download_url = try self.allocator.dupe(u8, e.download_url);
        errdefer self.allocator.free(download_url);
        return .{
            .id = e.id,
            .tenant_id = e.tenant_id,
            .name = name,
            .title = title,
            .version = version,
            .description = description,
            .download_url = download_url,
            .created_at = e.created_at orelse 0,
            .updated_at = e.updated_at orelse 0,
        };
    }

    // ── License ───────────────────────────────────────────────────

    pub fn createLicense(self: *CloudStore, tenant_id: i64, license_key: []const u8, expires_at: i64, now: i64) !i64 {
        var b = try self.client.license.Create();
        defer b.deinit();
        _ = try b.setFieldValue("tenant_id", tenant_id);
        _ = try b.setFieldValue("license_key", license_key);
        _ = try b.setFieldValue("status", "active");
        _ = try b.setFieldValue("expires_at", expires_at);
        _ = try b.setFieldValue("created_at", now);
        _ = try b.setFieldValue("updated_at", now);
        var row = try b.Save();
        defer zent.codegen.deinitEntity(infos, LicenseInfo, &row, self.allocator);
        return row.id;
    }

    pub fn getLicenseByKey(self: *CloudStore, tenant_id: i64, license_key: []const u8) !?LicenseRow {
        var q = self.client.license.Query();
        defer q.deinit();
        const preds = self.client.license.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.license_keyEQ(.{ .string = license_key })});
        _ = q.Limit(1);
        const entity_opt = try q.First();
        var entity = entity_opt orelse return null;
        defer zent.codegen.deinitEntity(infos, LicenseInfo, &entity, self.allocator);
        return try self.dupLicense(entity);
    }

    pub fn getLicenseById(self: *CloudStore, id: i64) !?LicenseRow {
        var q = self.client.license.Query();
        defer q.deinit();
        const preds = self.client.license.predicates;
        _ = try q.Where(.{preds.idEQ(.{ .int = id })});
        const entity_opt = try q.First();
        var entity = entity_opt orelse return null;
        defer zent.codegen.deinitEntity(infos, LicenseInfo, &entity, self.allocator);
        return try self.dupLicense(entity);
    }

    pub fn listLicenses(self: *CloudStore, page: usize, page_size: usize, tenant_id: i64) !LicenseListResult {
        var q = self.client.license.Query();
        defer q.deinit();
        const preds = self.client.license.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderDesc("id")});

        var paged = try q.paged(page, page_size);
        defer paged.deinit();

        var out = try self.allocator.alloc(LicenseRow, paged.items.items.len);
        var n: usize = 0;
        errdefer {
            for (out[0..n]) |r| r.free(self.allocator);
            self.allocator.free(out);
        }
        for (paged.items.items) |e| {
            out[n] = try self.dupLicense(e);
            n += 1;
        }
        return .{ .items = out, .total = paged.total };
    }

    pub fn setLicenseStatus(self: *CloudStore, id: i64, status: []const u8, now: i64) !void {
        const preds = self.client.license.predicates;
        var upd = self.client.license.Update();
        defer upd.deinit();
        _ = try upd.set("status", .{ .string = status });
        _ = try upd.setFieldValue("updated_at", now);
        _ = try upd.Where(.{preds.idEQ(.{ .int = id })});
        _ = try upd.Save();
    }

    // ── MarketPackage ─────────────────────────────────────────────

    pub fn getPackageByName(self: *CloudStore, tenant_id: i64, name: []const u8) !?MarketPackageRow {
        var q = self.client.market_package.Query();
        defer q.deinit();
        const preds = self.client.market_package.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.nameEQ(.{ .string = name })});
        _ = q.Limit(1);
        const entity_opt = try q.First();
        var entity = entity_opt orelse return null;
        defer zent.codegen.deinitEntity(infos, MarketPackageInfo, &entity, self.allocator);
        return try self.dupPackage(entity);
    }

    /// Upsert a market package by (tenant_id, name). Returns the package id.
    pub fn upsertPackage(self: *CloudStore, tenant_id: i64, name: []const u8, title: []const u8, version: []const u8, description: []const u8, download_url: []const u8, now: i64) !i64 {
        if (try self.getPackageByName(tenant_id, name)) |row| {
            defer row.free(self.allocator);
            const preds = self.client.market_package.predicates;
            var upd = self.client.market_package.Update();
            defer upd.deinit();
            _ = try upd.set("title", .{ .string = title });
            _ = try upd.set("version", .{ .string = version });
            _ = try upd.set("description", .{ .string = description });
            _ = try upd.set("download_url", .{ .string = download_url });
            _ = try upd.setFieldValue("updated_at", now);
            _ = try upd.Where(.{preds.idEQ(.{ .int = row.id })});
            _ = try upd.Save();
            return row.id;
        }
        var b = try self.client.market_package.Create();
        defer b.deinit();
        _ = try b.setFieldValue("tenant_id", tenant_id);
        _ = try b.setFieldValue("name", name);
        _ = try b.setFieldValue("title", title);
        _ = try b.setFieldValue("version", version);
        _ = try b.setFieldValue("description", description);
        _ = try b.setFieldValue("download_url", download_url);
        _ = try b.setFieldValue("created_at", now);
        _ = try b.setFieldValue("updated_at", now);
        var row = try b.Save();
        defer zent.codegen.deinitEntity(infos, MarketPackageInfo, &row, self.allocator);
        return row.id;
    }

    pub fn listMarket(self: *CloudStore, page: usize, page_size: usize, tenant_id: i64) !MarketListResult {
        var q = self.client.market_package.Query();
        defer q.deinit();
        const preds = self.client.market_package.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderAsc("name")});

        var paged = try q.paged(page, page_size);
        defer paged.deinit();

        var out = try self.allocator.alloc(MarketPackageRow, paged.items.items.len);
        var n: usize = 0;
        errdefer {
            for (out[0..n]) |r| r.free(self.allocator);
            self.allocator.free(out);
        }
        for (paged.items.items) |e| {
            out[n] = try self.dupPackage(e);
            n += 1;
        }
        return .{ .items = out, .total = paged.total };
    }
};
