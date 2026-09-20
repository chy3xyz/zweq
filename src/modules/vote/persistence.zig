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
        defer self.client.vote.deinitRow(&row);
        return row.id;
    }

    /// 按 id 取单条（tenant 过滤）。tenant 来源：service.vote/tally 等业务路径
    /// 上游传入；无 tenant 的只读调用链先经 `getTenantId` 探测再走本方法。
    pub fn getVote(self: *VoteStore, tenant_id: i64, id: i64) !?VoteRow {
        const preds = self.client.vote.predicates;
        var entity = (try crud.first(self.client.vote, .{ preds.tenant_idEQ(.{ .int = tenant_id }), preds.idEQ(.{ .int = id }) })) orelse return null;
        defer self.client.vote.deinitRow(&entity);
        return try self.dup(entity);
    }

    /// 按 id 探测归属 tenant_id（不返回行内容）。供调用链未携带 tenant 的
    /// 只读路径（BFF 详情/计票、测试）先探测、再走 tenant 过滤查询；
    /// 理想方案是上游 handler 传 tenant 后删除本方法。
    pub fn getTenantId(self: *VoteStore, id: i64) !?i64 {
        const preds = self.client.vote.predicates;
        var entity = (try crud.first(self.client.vote, .{preds.idEQ(.{ .int = id })})) orelse return null;
        defer self.client.vote.deinitRow(&entity);
        return entity.tenant_id;
    }

    /// 按 id 取单条（tenant 过滤），供 service 校验存在性与管理端更新/删除。
    pub fn getById(self: *VoteStore, tenant_id: i64, id: i64) !?VoteRow {
        const preds = self.client.vote.predicates;
        var entity = (try crud.first(self.client.vote, .{ preds.tenant_idEQ(.{ .int = tenant_id }), preds.idEQ(.{ .int = id }) })) orelse return null;
        defer self.client.vote.deinitRow(&entity);
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
        defer self.client.vote.deinitRow(&entity);
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

    // ── 管理端更新/删除 ─────────────────────────────────────

    /// 整体更新投票主题（tenant 过滤；account 作用域不变，account_id 不参与更新）。
    pub fn update(self: *VoteStore, tenant_id: i64, id: i64, title: []const u8, options_json: []const u8, end_at: i64, now: i64) !usize {
        const preds = self.client.vote.predicates;
        return crud.update(self.client.vote, .{
            .title = title,
            .options_json = options_json,
            .end_at = end_at,
            .updated_at = now,
        }, .{ preds.tenant_idEQ(.{ .int = tenant_id }), preds.idEQ(.{ .int = id }) });
    }

    /// 删除投票主题（tenant 过滤）。调用方应先删投票记录（`deleteRecordsByVoteId`）。
    pub fn deleteById(self: *VoteStore, tenant_id: i64, id: i64) !void {
        const preds = self.client.vote.predicates;
        _ = try crud.delete(self.client.vote, .{ preds.tenant_idEQ(.{ .int = tenant_id }), preds.idEQ(.{ .int = id }) });
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

    /// 插入投票记录。当前表上无 (vote_id, openid) 唯一索引，重复插入不会
    /// 触发冲突；一旦后续在 model.zig 补 `.indexes` 唯一索引，zent 会把冲突
    /// 冒泡为 `error.UniqueViolation`，service 层据此映射 error.AlreadyVoted。
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
        defer self.client.vote_record.deinitRow(&row);
        return row.id;
    }

    /// 删除某投票的全部投票记录（删除投票前调用，避免孤儿记录）。
    pub fn deleteRecordsByVoteId(self: *VoteStore, vote_id: i64) !void {
        const preds = self.client.vote_record.predicates;
        _ = try crud.delete(self.client.vote_record, .{preds.vote_idEQ(.{ .int = vote_id })});
    }

    /// 计票：某投票各选项的票数（返回 []i64，长度 = 选项数）。
    /// SQL 聚合（GROUP BY option_index）而非全行扫回 Zig 计数；
    /// option_index 越界/为负的脏数据跳过，与旧行为一致。
    pub fn tally(self: *VoteStore, allocator: std.mem.Allocator, tenant_id: i64, vote_id: i64, option_count: usize) ![]i64 {
        var out = try allocator.alloc(i64, option_count);
        errdefer allocator.free(out);
        @memset(out, 0);
        var q = self.client.vote_record.Query();
        defer q.deinit();
        const preds = self.client.vote_record.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.vote_idEQ(.{ .int = vote_id })});
        var metrics = try q.AggregateBy("COUNT(*)", "option_index");
        defer @TypeOf(q).freeGroupMetrics(&metrics);
        for (metrics.items) |m| {
            if (m.key != .int or m.key.int < 0) continue;
            if (m.value != .int) continue;
            const idx: usize = @intCast(m.key.int);
            if (idx < option_count) out[idx] = m.value.int;
        }
        return out;
    }
};
