//! Persistence over the zent Client — 应用市场包。

const std = @import("std");
const zent = @import("zent");
const crud = zent.crud_helpers;
const model = @import("model.zig");
const schema = @import("../../schema.zig");

const graph = zent.codegen.graph.buildGraph(&.{model.MarketPackage});
pub const infos = graph.types;
pub const Client = schema.Client;
pub const MarketPackageInfo = infos[0];

pub const MarketPackageRow = struct {
    id: i64,
    name: []const u8,
    title: []const u8,
    version: []const u8,
    description: []const u8,
    download_url: []const u8,
    checksum: []const u8,
    created_at: i64,

    pub fn free(self: MarketPackageRow, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.title);
        allocator.free(self.version);
        allocator.free(self.description);
        allocator.free(self.download_url);
        allocator.free(self.checksum);
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

pub const MarketStore = struct {
    allocator: std.mem.Allocator,
    client: Client,

    pub fn init(allocator: std.mem.Allocator, client: Client) MarketStore {
        return .{ .allocator = allocator, .client = client };
    }

    fn dup(self: *MarketStore, e: anytype) !MarketPackageRow {
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
        const checksum = try self.allocator.dupe(u8, e.checksum);
        errdefer self.allocator.free(checksum);
        return .{
            .id = e.id,
            .name = name,
            .title = title,
            .version = version,
            .description = description,
            .download_url = download_url,
            .checksum = checksum,
            .created_at = e.created_at orelse 0,
        };
    }

    pub fn getByName(self: *MarketStore, name: []const u8) !?MarketPackageRow {
        const preds = self.client.market_package.predicates;
        var entity = (try crud.first(self.client.market_package, .{preds.nameEQ(.{ .string = name })})) orelse return null;
        defer zent.codegen.deinitEntity(infos, MarketPackageInfo, &entity, self.allocator);
        return try self.dup(entity);
    }

    pub fn upsert(self: *MarketStore, name: []const u8, title: []const u8, version: []const u8, description: []const u8, download_url: []const u8, checksum: []const u8, now: i64) !i64 {
        if (try self.getByName(name)) |row| {
            defer row.free(self.allocator);
            const preds = self.client.market_package.predicates;
            _ = try crud.update(self.client.market_package, .{
                .title = title,
                .version = version,
                .description = description,
                .download_url = download_url,
                .checksum = checksum,
                .updated_at = now,
            }, .{preds.idEQ(.{ .int = row.id })});
            return row.id;
        }
        var row = try crud.create(self.client.market_package, .{
            .name = name,
            .title = title,
            .version = version,
            .description = description,
            .download_url = download_url,
            .checksum = checksum,
            .created_at = now,
            .updated_at = now,
        });
        defer zent.codegen.deinitEntity(infos, MarketPackageInfo, &row, self.allocator);
        return row.id;
    }

    pub fn list(self: *MarketStore, page: usize, page_size: usize) !MarketListResult {
        var q = self.client.market_package.Query();
        defer q.deinit();
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
            out[n] = try self.dup(e);
            n += 1;
        }
        return .{ .items = out, .total = paged.total };
    }
};
