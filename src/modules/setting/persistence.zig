//! Persistence over the zent Client — site settings (tenant-scoped KV).

const std = @import("std");
const zent = @import("zent");
const crud = zent.crud_helpers;
const model = @import("model.zig");
const schema = @import("../../schema.zig");

const graph = zent.codegen.graph.buildGraph(&.{model.SiteSetting});
pub const infos = graph.types;
/// Shared, application-wide typed client (all schemas registered in schema.zig).
pub const Client = schema.Client;
pub const SettingInfo = infos[0];

pub const SettingRow = struct {
    id: i64,
    tenant_id: i64,
    key: []const u8,
    value: []const u8,
    updated_at: i64,

    pub fn free(self: SettingRow, allocator: std.mem.Allocator) void {
        allocator.free(self.key);
        allocator.free(self.value);
    }
};

pub const SettingListResult = struct {
    items: []SettingRow,
    total: i64,

    pub fn free(self: *SettingListResult, allocator: std.mem.Allocator) void {
        for (self.items) |r| r.free(allocator);
        allocator.free(self.items);
    }
};

pub const SettingStore = struct {
    allocator: std.mem.Allocator,
    client: Client,

    pub fn init(allocator: std.mem.Allocator, client: Client) SettingStore {
        return .{ .allocator = allocator, .client = client };
    }

    fn dup(self: *SettingStore, e: anytype) !SettingRow {
        const key = try self.allocator.dupe(u8, e.key);
        errdefer self.allocator.free(key);
        const value = try self.allocator.dupe(u8, e.value);
        errdefer self.allocator.free(value);
        return .{
            .id = e.id,
            .tenant_id = e.tenant_id,
            .key = key,
            .value = value,
            .updated_at = e.updated_at orelse 0,
        };
    }

    pub fn get(self: *SettingStore, tenant_id: i64, key: []const u8) !?SettingRow {
        const preds = self.client.site_setting.predicates;
        var entity = (try crud.first(self.client.site_setting, .{ preds.tenant_idEQ(.{ .int = tenant_id }), preds.keyEQ(.{ .string = key }) })) orelse return null;
        defer zent.codegen.deinitEntity(infos, SettingInfo, &entity, self.allocator);
        return try self.dup(entity);
    }

    /// Upsert a setting key within a tenant. Returns the row id.
    pub fn set(self: *SettingStore, tenant_id: i64, key: []const u8, value: []const u8, now: i64) !i64 {
        if (try self.get(tenant_id, key)) |row| {
            defer row.free(self.allocator);
            const preds = self.client.site_setting.predicates;
            _ = try crud.update(self.client.site_setting, .{
                .value = value,
                .updated_at = now,
            }, .{preds.idEQ(.{ .int = row.id })});
            return row.id;
        }
        var row = try crud.create(self.client.site_setting, .{
            .tenant_id = tenant_id,
            .key = key,
            .value = value,
            .created_at = now,
            .updated_at = now,
        });
        defer zent.codegen.deinitEntity(infos, SettingInfo, &row, self.allocator);
        return row.id;
    }

    pub fn list(self: *SettingStore, page: usize, page_size: usize, tenant_id: i64) !SettingListResult {
        var q = self.client.site_setting.Query();
        defer q.deinit();
        const preds = self.client.site_setting.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderAsc("key")});

        var paged = try q.paged(page, page_size);
        defer paged.deinit();

        var out = try self.allocator.alloc(SettingRow, paged.items.items.len);
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

    pub fn delete(self: *SettingStore, tenant_id: i64, key: []const u8) !void {
        const preds = self.client.site_setting.predicates;
        var d = self.client.site_setting.Delete();
        defer d.deinit();
        _ = try d.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try d.Where(.{preds.keyEQ(.{ .string = key })});
        _ = try d.Exec();
    }
};
