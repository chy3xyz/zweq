//! Persistence over the zent Client — 签到记录。

const std = @import("std");
const zent = @import("zent");
const crud = zent.crud_helpers;
const model = @import("model.zig");
const schema = @import("../../schema.zig");

const graph = zent.codegen.graph.buildGraph(&.{ model.CheckinRecord });
pub const infos = graph.types;
/// Shared, application-wide typed client (all schemas registered in schema.zig).
pub const Client = schema.Client;
pub const CheckinRecordInfo = infos[0];

pub const CheckinRecordRow = struct {
    id: i64,
    tenant_id: i64,
    account_id: i64,
    openid: []const u8,
    checkin_day: i64,
    points: i64,
    created_at: i64,

    pub fn free(self: CheckinRecordRow, allocator: std.mem.Allocator) void {
        allocator.free(self.openid);
    }
};

pub const CheckinListResult = struct {
    items: []CheckinRecordRow,
    total: i64,

    pub fn free(self: *CheckinListResult, allocator: std.mem.Allocator) void {
        for (self.items) |r| r.free(allocator);
        allocator.free(self.items);
    }
};

pub const CheckinStore = struct {
    allocator: std.mem.Allocator,
    client: Client,

    pub fn init(allocator: std.mem.Allocator, client: Client) CheckinStore {
        return .{ .allocator = allocator, .client = client };
    }

    fn dup(self: *CheckinStore, e: anytype) !CheckinRecordRow {
        const openid = try self.allocator.dupe(u8, e.openid);
        errdefer self.allocator.free(openid);
        return .{
            .id = e.id,
            .tenant_id = e.tenant_id,
            .account_id = e.account_id,
            .openid = openid,
            .checkin_day = e.checkin_day,
            .points = e.points,
            .created_at = e.created_at orelse 0,
        };
    }

    /// Find today's (same `checkin_day`) record for an openid, if any.
    pub fn findByDay(self: *CheckinStore, tenant_id: i64, account_id: i64, openid: []const u8, day: i64) !?CheckinRecordRow {
        const preds = self.client.checkin_record.predicates;
        var entity = (try crud.first(self.client.checkin_record, .{
            preds.tenant_idEQ(.{ .int = tenant_id }),
            preds.account_idEQ(.{ .int = account_id }),
            preds.openidEQ(.{ .string = openid }),
            preds.checkin_dayEQ(.{ .int = day }),
        })) orelse return null;
        defer zent.codegen.deinitEntity(infos, CheckinRecordInfo, &entity, self.allocator);
        return try self.dup(entity);
    }

    pub fn create(self: *CheckinStore, tenant_id: i64, account_id: i64, openid: []const u8, day: i64, points: i64, now: i64) !i64 {
        var row = try crud.create(self.client.checkin_record, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .openid = openid,
            .checkin_day = day,
            .points = points,
            .created_at = now,
            .updated_at = now,
        });
        defer zent.codegen.deinitEntity(infos, CheckinRecordInfo, &row, self.allocator);
        return row.id;
    }

    pub fn list(self: *CheckinStore, page: usize, page_size: usize, tenant_id: i64, account_id: i64) !CheckinListResult {
        var q = self.client.checkin_record.Query();
        defer q.deinit();
        const preds = self.client.checkin_record.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderDesc("created_at")});

        var paged = try q.paged(page, page_size);
        defer paged.deinit();

        var out = try self.allocator.alloc(CheckinRecordRow, paged.items.items.len);
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
