//! Persistence over the zent Client — 授权码。

const std = @import("std");
const zent = @import("zent");
const crud = zent.crud_helpers;
const model = @import("model.zig");
const schema = @import("../../schema.zig");

const graph = zent.codegen.graph.buildGraph(&.{model.License});
pub const infos = graph.types;
pub const Client = schema.Client;
pub const LicenseInfo = infos[0];

pub const LicenseRow = struct {
    id: i64,
    license_key: []const u8,
    status: []const u8,
    expires_at: i64,
    created_at: i64,

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

pub const LicenseStore = struct {
    allocator: std.mem.Allocator,
    client: Client,

    pub fn init(allocator: std.mem.Allocator, client: Client) LicenseStore {
        return .{ .allocator = allocator, .client = client };
    }

    fn dup(self: *LicenseStore, e: anytype) !LicenseRow {
        const key = try self.allocator.dupe(u8, e.license_key);
        errdefer self.allocator.free(key);
        const status = try self.allocator.dupe(u8, e.status);
        errdefer self.allocator.free(status);
        return .{
            .id = e.id,
            .license_key = key,
            .status = status,
            .expires_at = e.expires_at,
            .created_at = e.created_at orelse 0,
        };
    }

    pub fn create(self: *LicenseStore, license_key: []const u8, expires_at: i64, now: i64) !i64 {
        var row = try crud.create(self.client.license, .{
            .license_key = license_key,
            .status = "active",
            .expires_at = expires_at,
            .created_at = now,
            .updated_at = now,
        });
        defer zent.codegen.deinitEntity(infos, LicenseInfo, &row, self.allocator);
        return row.id;
    }

    pub fn getByKey(self: *LicenseStore, license_key: []const u8) !?LicenseRow {
        const preds = self.client.license.predicates;
        var entity = (try crud.first(self.client.license, .{preds.license_keyEQ(.{ .string = license_key })})) orelse return null;
        defer zent.codegen.deinitEntity(infos, LicenseInfo, &entity, self.allocator);
        return try self.dup(entity);
    }

    pub fn setStatus(self: *LicenseStore, id: i64, status: []const u8, now: i64) !void {
        const preds = self.client.license.predicates;
        _ = try crud.update(self.client.license, .{
            .status = status,
            .updated_at = now,
        }, .{preds.idEQ(.{ .int = id })});
    }

    pub fn list(self: *LicenseStore, page: usize, page_size: usize) !LicenseListResult {
        var q = self.client.license.Query();
        defer q.deinit();
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
            out[n] = try self.dup(e);
            n += 1;
        }
        return .{ .items = out, .total = paged.total };
    }
};
