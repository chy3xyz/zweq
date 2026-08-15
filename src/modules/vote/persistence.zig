//! Persistence over the zent Client — 投票主题 + 投票记录。

const std = @import("std");
const zent = @import("zent");
const crud = zent.crud_helpers;
const model = @import("model.zig");
const schema = @import("../../schema.zig");

const graph = zent.codegen.graph.buildGraph(&.{ model.Vote, model.VoteRecord });
pub const infos = graph.types;
pub const Client = schema.Client;
pub const VoteInfo = infos[0];
pub const VoteRecordInfo = infos[1];

pub const VoteRow = struct {
    id: i64,
    account_id: i64,
    title: []const u8,
    options_json: []const u8,
    end_at: i64,
    created_at: i64,

    pub fn free(self: VoteRow, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
        allocator.free(self.options_json);
    }
};

pub const VoteListResult = struct {
    items: []VoteRow,
    total: i64,

    pub fn free(self: *VoteListResult, allocator: std.mem.Allocator) void {
        for (self.items) |r| r.free(allocator);
        allocator.free(self.items);
    }
};

pub const VoteStore = struct {
    allocator: std.mem.Allocator,
    client: Client,

    pub fn init(allocator: std.mem.Allocator, client: Client) VoteStore {
        return .{ .allocator = allocator, .client = client };
    }

    fn dup(self: *VoteStore, e: anytype) !VoteRow {
        const title = try self.allocator.dupe(u8, e.title);
        errdefer self.allocator.free(title);
        const options_json = try self.allocator.dupe(u8, e.options_json);
        errdefer self.allocator.free(options_json);
        return .{
            .id = e.id,
            .account_id = e.account_id,
            .title = title,
            .options_json = options_json,
            .end_at = e.end_at,
            .created_at = e.created_at orelse 0,
        };
    }

    pub fn createVote(self: *VoteStore, tenant_id: i64, account_id: i64, title: []const u8, options_json: []const u8, end_at: i64, now: i64) !i64 {
        var row = try crud.create(self.client.vote, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .title = title,
            .options_json = options_json,
            .end_at = end_at,
            .created_at = now,
            .updated_at = now,
        });
        defer zent.codegen.deinitEntity(infos, VoteInfo, &row, self.allocator);
        return row.id;
    }

    pub fn getVote(self: *VoteStore, id: i64) !?VoteRow {
        const preds = self.client.vote.predicates;
        var entity = (try crud.first(self.client.vote, .{preds.idEQ(.{ .int = id })})) orelse return null;
        defer zent.codegen.deinitEntity(infos, VoteInfo, &entity, self.allocator);
        return try self.dup(entity);
    }

    /// 该账号最新的投票主题（receiver 用）。
    pub fn latestVote(self: *VoteStore, tenant_id: i64, account_id: i64) !?VoteRow {
        var q = self.client.vote.Query();
        defer q.deinit();
        const preds = self.client.vote.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderDesc("created_at")});
        _ = q.Limit(1);
        const entity_opt = try q.First();
        var entity = entity_opt orelse return null;
        defer zent.codegen.deinitEntity(infos, VoteInfo, &entity, self.allocator);
        return try self.dup(entity);
    }

    pub fn listVotes(self: *VoteStore, page: usize, page_size: usize, tenant_id: i64, account_id: i64) !VoteListResult {
        var q = self.client.vote.Query();
        defer q.deinit();
        const preds = self.client.vote.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderDesc("created_at")});
        var paged = try q.paged(page, page_size);
        defer paged.deinit();
        var out = try self.allocator.alloc(VoteRow, paged.items.items.len);
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

    // ── 投票记录 ─────────────────────────────────────────────

    /// 某 openid 对某投票是否已投（防重）。
    pub fn findRecord(self: *VoteStore, tenant_id: i64, vote_id: i64, openid: []const u8) !bool {
        var q = self.client.vote_record.Query();
        defer q.deinit();
        const preds = self.client.vote_record.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.vote_idEQ(.{ .int = vote_id })});
        _ = try q.Where(.{preds.openidEQ(.{ .string = openid })});
        _ = q.Limit(1);
        const count = try q.Count();
        return count > 0;
    }

    pub fn createRecord(self: *VoteStore, tenant_id: i64, account_id: i64, openid: []const u8, vote_id: i64, option_index: i64, now: i64) !i64 {
        var row = try crud.create(self.client.vote_record, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .openid = openid,
            .vote_id = vote_id,
            .option_index = option_index,
            .created_at = now,
            .updated_at = now,
        });
        defer zent.codegen.deinitEntity(infos, VoteRecordInfo, &row, self.allocator);
        return row.id;
    }

    /// 计票：某投票各选项的票数（返回 []i64，长度 = 选项数）。
    pub fn tally(self: *VoteStore, allocator: std.mem.Allocator, vote_id: i64, option_count: usize) ![]i64 {
        var out = try allocator.alloc(i64, option_count);
        errdefer allocator.free(out);
        @memset(out, 0);
        var q = self.client.vote_record.Query();
        defer q.deinit();
        const preds = self.client.vote_record.predicates;
        _ = try q.Where(.{preds.vote_idEQ(.{ .int = vote_id })});
        var rows = try q.All();
        defer {
            for (rows.items) |*e| zent.codegen.deinitEntity(infos, VoteRecordInfo, e, self.allocator);
            rows.deinit();
        }
        for (rows.items) |e| {
            const idx: usize = @intCast(e.option_index);
            if (idx < option_count) out[idx] += 1;
        }
        return out;
    }
};
