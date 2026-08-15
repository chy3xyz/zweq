//! Persistence over the zent Client — 会员卡等级 + 会员积分账户。

const std = @import("std");
const zent = @import("zent");
const crud = zent.crud_helpers;
const model = @import("model.zig");
const schema = @import("../../schema.zig");

const graph = zent.codegen.graph.buildGraph(&.{ model.MemberCardLevel, model.MemberAccount });
pub const infos = graph.types;
pub const Client = schema.Client;
pub const MemberCardLevelInfo = infos[0];
pub const MemberAccountInfo = infos[1];

pub const MemberCardLevelRow = struct {
    id: i64,
    account_id: i64,
    name: []const u8,
    level: i64,
    discount: i64,
    points_ratio: i64,
    threshold: i64,
    created_at: i64,

    pub fn free(self: MemberCardLevelRow, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }
};

pub const MemberAccountRow = struct {
    id: i64,
    account_id: i64,
    openid: []const u8,
    level_id: i64,
    points: i64,
    total_points: i64,
    created_at: i64,

    pub fn free(self: MemberAccountRow, allocator: std.mem.Allocator) void {
        allocator.free(self.openid);
    }
};

pub const LevelListResult = struct {
    items: []MemberCardLevelRow,
    total: i64,

    pub fn free(self: *LevelListResult, allocator: std.mem.Allocator) void {
        for (self.items) |r| r.free(allocator);
        allocator.free(self.items);
    }
};

pub const MemberAccountListResult = struct {
    items: []MemberAccountRow,
    total: i64,

    pub fn free(self: *MemberAccountListResult, allocator: std.mem.Allocator) void {
        for (self.items) |r| r.free(allocator);
        allocator.free(self.items);
    }
};

pub const MemberCardStore = struct {
    allocator: std.mem.Allocator,
    client: Client,

    pub fn init(allocator: std.mem.Allocator, client: Client) MemberCardStore {
        return .{ .allocator = allocator, .client = client };
    }

    fn dupLevel(self: *MemberCardStore, e: anytype) !MemberCardLevelRow {
        const name = try self.allocator.dupe(u8, e.name);
        errdefer self.allocator.free(name);
        return .{
            .id = e.id,
            .account_id = e.account_id,
            .name = name,
            .level = e.level,
            .discount = e.discount,
            .points_ratio = e.points_ratio,
            .threshold = e.threshold,
            .created_at = e.created_at orelse 0,
        };
    }

    fn dupAccount(self: *MemberCardStore, e: anytype) !MemberAccountRow {
        const openid = try self.allocator.dupe(u8, e.openid);
        errdefer self.allocator.free(openid);
        return .{
            .id = e.id,
            .account_id = e.account_id,
            .openid = openid,
            .level_id = e.level_id,
            .points = e.points,
            .total_points = e.total_points,
            .created_at = e.created_at orelse 0,
        };
    }

    // ── 卡等级 ───────────────────────────────────────────────

    pub fn createLevel(self: *MemberCardStore, tenant_id: i64, account_id: i64, name: []const u8, level: i64, discount: i64, points_ratio: i64, threshold: i64, now: i64) !i64 {
        var row = try crud.create(self.client.member_card_level, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .name = name,
            .level = level,
            .discount = discount,
            .points_ratio = points_ratio,
            .threshold = threshold,
            .created_at = now,
            .updated_at = now,
        });
        defer zent.codegen.deinitEntity(infos, MemberCardLevelInfo, &row, self.allocator);
        return row.id;
    }

    pub fn getLevel(self: *MemberCardStore, id: i64) !?MemberCardLevelRow {
        const preds = self.client.member_card_level.predicates;
        var entity = (try crud.first(self.client.member_card_level, .{preds.idEQ(.{ .int = id })})) orelse return null;
        defer zent.codegen.deinitEntity(infos, MemberCardLevelInfo, &entity, self.allocator);
        return try self.dupLevel(entity);
    }

    /// 当前累计积分对应的最高等级（升级依据 threshold）。
    pub fn levelForPoints(self: *MemberCardStore, tenant_id: i64, account_id: i64, total_points: i64) !?MemberCardLevelRow {
        var q = self.client.member_card_level.Query();
        defer q.deinit();
        const preds = self.client.member_card_level.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.Where(.{preds.thresholdLTE(.{ .int = total_points })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderDesc("threshold")});
        _ = q.Limit(1);
        const entity_opt = try q.First();
        var entity = entity_opt orelse return null;
        defer zent.codegen.deinitEntity(infos, MemberCardLevelInfo, &entity, self.allocator);
        return try self.dupLevel(entity);
    }

    pub fn listLevels(self: *MemberCardStore, page: usize, page_size: usize, tenant_id: i64, account_id: i64) !LevelListResult {
        var q = self.client.member_card_level.Query();
        defer q.deinit();
        const preds = self.client.member_card_level.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderAsc("level")});
        var paged = try q.paged(page, page_size);
        defer paged.deinit();
        var out = try self.allocator.alloc(MemberCardLevelRow, paged.items.items.len);
        var n: usize = 0;
        errdefer {
            for (out[0..n]) |r| r.free(self.allocator);
            self.allocator.free(out);
        }
        for (paged.items.items) |e| {
            out[n] = try self.dupLevel(e);
            n += 1;
        }
        return .{ .items = out, .total = paged.total };
    }

    // ── 会员账户 ─────────────────────────────────────────────

    pub fn getAccountByOpenid(self: *MemberCardStore, tenant_id: i64, account_id: i64, openid: []const u8) !?MemberAccountRow {
        var q = self.client.member_account.Query();
        defer q.deinit();
        const preds = self.client.member_account.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.Where(.{preds.openidEQ(.{ .string = openid })});
        const entity_opt = try q.First();
        var entity = entity_opt orelse return null;
        defer zent.codegen.deinitEntity(infos, MemberAccountInfo, &entity, self.allocator);
        return try self.dupAccount(entity);
    }

    pub fn createAccount(self: *MemberCardStore, tenant_id: i64, account_id: i64, openid: []const u8, level_id: i64, now: i64) !i64 {
        var row = try crud.create(self.client.member_account, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .openid = openid,
            .level_id = level_id,
            .points = 0,
            .total_points = 0,
            .created_at = now,
            .updated_at = now,
        });
        defer zent.codegen.deinitEntity(infos, MemberAccountInfo, &row, self.allocator);
        return row.id;
    }

    /// 原子积分增减：points += delta, total_points += max(delta,0)。
    pub fn adjustPoints(self: *MemberCardStore, account_id: i64, delta: i64) !bool {
        const preds = self.client.member_account.predicates;
        const affected = crud.increment(self.client.member_account, "points", delta, &.{
            preds.idEQ(.{ .int = account_id }),
        }) catch return false;
        if (delta > 0) {
            _ = crud.increment(self.client.member_account, "total_points", delta, &.{
                preds.idEQ(.{ .int = account_id }),
            }) catch {};
        }
        return affected > 0;
    }

    /// 设置等级（升级/降级）。
    pub fn setLevel(self: *MemberCardStore, account_id: i64, level_id: i64) !void {
        const preds = self.client.member_account.predicates;
        var upd = self.client.member_account.Update();
        defer upd.deinit();
        _ = try upd.set("level_id", .{ .int = level_id });
        _ = try upd.Where(.{preds.idEQ(.{ .int = account_id })});
        _ = try upd.Save();
    }

    pub fn listAccounts(self: *MemberCardStore, page: usize, page_size: usize, tenant_id: i64, account_id: i64) !MemberAccountListResult {
        var q = self.client.member_account.Query();
        defer q.deinit();
        const preds = self.client.member_account.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderDesc("created_at")});
        var paged = try q.paged(page, page_size);
        defer paged.deinit();
        var out = try self.allocator.alloc(MemberAccountRow, paged.items.items.len);
        var n: usize = 0;
        errdefer {
            for (out[0..n]) |r| r.free(self.allocator);
            self.allocator.free(out);
        }
        for (paged.items.items) |e| {
            out[n] = try self.dupAccount(e);
            n += 1;
        }
        return .{ .items = out, .total = paged.total };
    }
};
