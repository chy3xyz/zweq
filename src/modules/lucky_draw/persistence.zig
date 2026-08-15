//! Persistence over the zent Client — 大转盘抽奖（lucky_draw）中奖记录。

const std = @import("std");
const zent = @import("zent");
const crud = zent.crud_helpers;
const model = @import("model.zig");
const schema = @import("../../schema.zig");

const graph = zent.codegen.graph.buildGraph(&.{model.DrawRecord});
pub const infos = graph.types;
/// Shared, application-wide typed client (all schemas registered in schema.zig).
pub const Client = schema.Client;
pub const DrawRecordInfo = infos[0];

pub const DrawRecordRow = struct {
    id: i64,
    tenant_id: i64,
    account_id: i64,
    openid: []const u8,
    prize_name: []const u8,
    points: i64,
    created_at: i64,

    pub fn free(self: DrawRecordRow, allocator: std.mem.Allocator) void {
        allocator.free(self.openid);
        allocator.free(self.prize_name);
    }
};

pub const DrawListResult = struct {
    items: []DrawRecordRow,
    total: i64,

    pub fn free(self: *DrawListResult, allocator: std.mem.Allocator) void {
        for (self.items) |r| r.free(allocator);
        allocator.free(self.items);
    }
};

pub const DrawStore = struct {
    allocator: std.mem.Allocator,
    client: Client,

    pub fn init(allocator: std.mem.Allocator, client: Client) DrawStore {
        return .{ .allocator = allocator, .client = client };
    }

    fn dup(self: *DrawStore, e: anytype) !DrawRecordRow {
        const openid = try self.allocator.dupe(u8, e.openid);
        errdefer self.allocator.free(openid);
        const prize_name = try self.allocator.dupe(u8, e.prize_name);
        errdefer self.allocator.free(prize_name);
        return .{
            .id = e.id,
            .tenant_id = e.tenant_id,
            .account_id = e.account_id,
            .openid = openid,
            .prize_name = prize_name,
            .points = e.points,
            .created_at = e.created_at orelse 0,
        };
    }

    pub fn create(self: *DrawStore, tenant_id: i64, account_id: i64, openid: []const u8, prize_name: []const u8, points: i64, now: i64) !i64 {
        var row = try crud.create(self.client.draw_record, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .openid = openid,
            .prize_name = prize_name,
            .points = points,
            .created_at = now,
            .updated_at = now,
        });
        defer zent.codegen.deinitEntity(infos, DrawRecordInfo, &row, self.allocator);
        return row.id;
    }

    /// 某 openid 当天已抽次数（用于 daily_limit）。
    pub fn countToday(self: *DrawStore, tenant_id: i64, account_id: i64, openid: []const u8, day: i64) !i64 {
        var q = self.client.draw_record.Query();
        defer q.deinit();
        const preds = self.client.draw_record.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.Where(.{preds.openidEQ(.{ .string = openid })});
        // 按创建时间当天过滤：created_at 落在 [day*86400, (day+1)*86400)。
        _ = try q.Where(.{preds.created_atGTE(.{ .int = day * 86400 })});
        _ = try q.Where(.{preds.created_atLT(.{ .int = (day + 1) * 86400 })});
        const total = try q.Count();
        return total;
    }

    pub fn list(self: *DrawStore, page: usize, page_size: usize, tenant_id: i64, account_id: i64) !DrawListResult {
        var q = self.client.draw_record.Query();
        defer q.deinit();
        const preds = self.client.draw_record.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderDesc("created_at")});

        var paged = try q.paged(page, page_size);
        defer paged.deinit();

        var out = try self.allocator.alloc(DrawRecordRow, paged.items.items.len);
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
