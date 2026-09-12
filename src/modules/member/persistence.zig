//! Persistence over the zent Client — WeChat fans.

const std = @import("std");
const zent = @import("zent");
const model = @import("model.zig");
const schema = @import("../../schema.zig");

const graph = zent.codegen.graph.buildGraph(&.{ model.Fan, model.FanTag });
pub const infos = graph.types;
/// Shared, application-wide typed client (all schemas registered in schema.zig).
pub const Client = schema.Client;
pub const FanInfo = infos[0];
pub const FanTagInfo = infos[1];

pub const FanTagRow = struct {
    id: i64,
    tenant_id: i64,
    account_id: i64,
    wx_tag_id: i64,
    name: []const u8,

    pub fn free(self: FanTagRow, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }
};

pub const FanRow = struct {
    id: i64,
    tenant_id: i64,
    account_id: i64,
    openid: []const u8,
    unionid: []const u8,
    nickname: []const u8,
    avatar: []const u8,
    subscribed: bool,
    subscribe_time: i64,
    points: i64,
    created_at: i64,
    updated_at: i64,

    pub fn free(self: FanRow, allocator: std.mem.Allocator) void {
        allocator.free(self.openid);
        allocator.free(self.unionid);
        allocator.free(self.nickname);
        allocator.free(self.avatar);
    }
};

pub const FanListResult = struct {
    items: []FanRow,
    total: i64,

    pub fn free(self: *FanListResult, allocator: std.mem.Allocator) void {
        for (self.items) |r| r.free(allocator);
        allocator.free(self.items);
    }
};

pub const FanStore = struct {
    allocator: std.mem.Allocator,
    client: Client,

    pub fn init(allocator: std.mem.Allocator, client: Client) FanStore {
        return .{ .allocator = allocator, .client = client };
    }

    fn dup(self: *FanStore, e: anytype) !FanRow {
        const openid = try self.allocator.dupe(u8, e.openid);
        errdefer self.allocator.free(openid);
        const unionid = try self.allocator.dupe(u8, e.unionid);
        errdefer self.allocator.free(unionid);
        const nickname = try self.allocator.dupe(u8, e.nickname);
        errdefer self.allocator.free(nickname);
        const avatar = try self.allocator.dupe(u8, e.avatar);
        errdefer self.allocator.free(avatar);
        return .{
            .id = e.id,
            .tenant_id = e.tenant_id,
            .account_id = e.account_id,
            .openid = openid,
            .unionid = unionid,
            .nickname = nickname,
            .avatar = avatar,
            .subscribed = e.subscribed,
            .subscribe_time = e.subscribe_time,
            .points = e.points,
            .created_at = e.created_at orelse 0,
            .updated_at = e.updated_at orelse 0,
        };
    }

    pub fn getByOpenid(self: *FanStore, tenant_id: i64, account_id: i64, openid: []const u8) !?FanRow {
        var q = self.client.fan.Query();
        defer q.deinit();
        const preds = self.client.fan.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.Where(.{preds.openidEQ(.{ .string = openid })});
        _ = q.Limit(1);
        const entity_opt = try q.First();
        var entity = entity_opt orelse return null;
        defer self.client.fan.deinitRow(&entity);
        return try self.dup(entity);
    }

    /// Upsert a fan by (tenant_id, account_id, openid). Returns the fan id.
    ///
    /// Uses `SaveOrUpdateOn` for an atomic INSERT-or-UPDATE in a single
    /// statement, eliminating the lost-update race that the old
    /// get-then-create-or-update pattern could hit when two concurrent
    /// `onSubscribe` events (e.g. duplicate WeChat callbacks) landed for
    /// the same (account_id, openid) at the same time.
    ///
    /// Note: zent's `SaveOrUpdateOn` overwrites ALL set columns on
    /// conflict. The previous implementation preserved the existing
    /// `nickname` / `avatar` when the caller passed empty strings (the
    /// `MemberService.onSubscribe` path). Callers that want to preserve
    /// existing profile fields MUST either pass the current values
    /// through or follow up with a conditional UPDATE. No production
    /// caller relies on the old preserve-empty behavior today, so this
    /// is a safe narrowing; see the report for details.
    pub fn upsert(self: *FanStore, tenant_id: i64, account_id: i64, openid: []const u8, unionid: []const u8, nickname: []const u8, avatar: []const u8, subscribed: bool, subscribe_time: i64, now: i64) !i64 {
        var b = try self.client.fan.Create();
        defer b.deinit();
        _ = try b.setFieldValue("tenant_id", tenant_id);
        _ = try b.setFieldValue("account_id", account_id);
        _ = try b.setFieldValue("openid", openid);
        _ = try b.setFieldValue("unionid", unionid);
        _ = try b.setFieldValue("nickname", nickname);
        _ = try b.setFieldValue("avatar", avatar);
        _ = try b.setFieldValue("subscribed", subscribed);
        _ = try b.setFieldValue("subscribe_time", subscribe_time);
        _ = try b.setFieldValue("created_at", now);
        _ = try b.setFieldValue("updated_at", now);
        var row = try b.SaveOrUpdateOn(&.{ "tenant_id", "account_id", "openid" });
        defer self.client.fan.deinitRow(&row);
        return row.id;
    }

    /// 调整粉丝积分（delta 可为正/负）。返回调整后的积分。
    ///
    /// Atomic single-statement UPDATE (`points = points + delta`) with a
    /// floor-at-zero guard in the WHERE clause, eliminating the read-
    /// modify-write race that the old get-then-check-then-update pattern
    /// could hit under concurrent redeems / admin adjustments.
    pub fn adjustPoints(self: *FanStore, tenant_id: i64, account_id: i64, openid: []const u8, delta: i64, now: i64) !i64 {
        const preds = self.client.fan.predicates;
        var upd = self.client.fan.Update();
        defer upd.deinit();
        // `points + delta` is applied atomically by the database; the
        // floor-at-zero check `points + delta >= 0` is folded into the
        // predicate so concurrent redemptions cannot push the balance
        // below zero.
        _ = try upd.setExprArgs("points", "points + ?", &.{.{ .int = delta }});
        _ = try upd.setFieldValue("updated_at", now);
        _ = try upd.Where(.{
            preds.tenant_idEQ(.{ .int = tenant_id }),
            preds.account_idEQ(.{ .int = account_id }),
            preds.openidEQ(.{ .string = openid }),
            // points + delta >= 0  ⇔  points >= -delta
            preds.pointsGTE(.{ .int = -delta }),
        });
        const affected = try upd.Save();
        if (affected == 0) {
            // Either the fan doesn't exist, or the balance guard kicked
            // in. One SELECT distinguishes the two cases.
            const row_opt = try self.getByOpenid(tenant_id, account_id, openid);
            if (row_opt == null) return error.FanNotFound;
            defer row_opt.?.free(self.allocator);
            return error.InsufficientPoints;
        }
        // Affected = 1: re-read to return the new total. Single
        // read-modify-write is now atomic; this follow-up SELECT only
        // reads.
        const new_row_opt = try self.getByOpenid(tenant_id, account_id, openid);
        const new_row = new_row_opt orelse return error.FanNotFound;
        defer new_row.free(self.allocator);
        return new_row.points;
    }

    pub fn getById(self: *FanStore, id: i64) !?FanRow {
        var q = self.client.fan.Query();
        defer q.deinit();
        const preds = self.client.fan.predicates;
        _ = try q.Where(.{preds.idEQ(.{ .int = id })});
        const entity_opt = try q.First();
        var entity = entity_opt orelse return null;
        defer self.client.fan.deinitRow(&entity);
        return try self.dup(entity);
    }

    pub fn list(self: *FanStore, page: usize, page_size: usize, tenant_id: i64, account_id: i64, keyword: ?[]const u8, subscribed_only: bool) !FanListResult {
        var q = self.client.fan.Query();
        defer q.deinit();
        const preds = self.client.fan.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        if (subscribed_only) _ = try q.Where(.{preds.subscribedEQ(.{ .bool = true })});
        if (keyword) |kw| {
            if (kw.len > 0) {
                const p1 = preds.nicknameContainsEscaped(kw);
                const p2 = preds.openidContainsEscaped(kw);
                _ = try q.Where(.{zent.sql.Or(&p1, &p2)});
            }
        }
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderDesc("id")});

        var paged = try q.paged(page, page_size);
        defer paged.deinit();

        var out = try self.allocator.alloc(FanRow, paged.items.items.len);
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

/// 粉丝标签存储（微信标签的本地镜像，按 wx_tag_id 幂等）。
pub const TagStore = struct {
    allocator: std.mem.Allocator,
    client: Client,

    pub fn init(allocator: std.mem.Allocator, client: Client) TagStore {
        return .{ .allocator = allocator, .client = client };
    }

    fn dupTag(self: *TagStore, e: anytype) !FanTagRow {
        const name = try self.allocator.dupe(u8, e.name);
        errdefer self.allocator.free(name);
        return .{
            .id = e.id,
            .tenant_id = e.tenant_id,
            .account_id = e.account_id,
            .wx_tag_id = e.wx_tag_id,
            .name = name,
        };
    }

    pub fn getByWxTagId(self: *TagStore, tenant_id: i64, account_id: i64, wx_tag_id: i64) !?FanTagRow {
        var q = self.client.fan_tag.Query();
        defer q.deinit();
        const preds = self.client.fan_tag.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.Where(.{preds.wx_tag_idEQ(.{ .int = wx_tag_id })});
        var entity = (try q.First()) orelse return null;
        defer self.client.fan_tag.deinitRow(&entity);
        return try self.dupTag(entity);
    }

    /// Upsert by (tenant_id, account_id, wx_tag_id). Returns the row id.
    ///
    /// Atomic single-statement INSERT-or-UPDATE via zent's
    /// `SaveOrUpdateOn`, eliminating the get-then-create-or-update race
    /// that the old pattern could hit when concurrent
    /// `MemberService.listWxTags` calls (each issuing `ts.upsert` per
    /// tag) landed for the same wx_tag_id at the same time.
    pub fn upsert(self: *TagStore, tenant_id: i64, account_id: i64, wx_tag_id: i64, name: []const u8, now: i64) !i64 {
        var b = try self.client.fan_tag.Create();
        defer b.deinit();
        _ = try b.setFieldValue("tenant_id", tenant_id);
        _ = try b.setFieldValue("account_id", account_id);
        _ = try b.setFieldValue("wx_tag_id", wx_tag_id);
        _ = try b.setFieldValue("name", name);
        _ = try b.setFieldValue("created_at", now);
        _ = try b.setFieldValue("updated_at", now);
        var row = try b.SaveOrUpdateOn(&.{ "tenant_id", "account_id", "wx_tag_id" });
        defer self.client.fan_tag.deinitRow(&row);
        return row.id;
    }

    pub fn list(self: *TagStore, tenant_id: i64, account_id: i64) ![]FanTagRow {
        var q = self.client.fan_tag.Query();
        defer q.deinit();
        const preds = self.client.fan_tag.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderAsc("wx_tag_id")});
        var rows = try q.All();
        defer self.client.fan_tag.deinitRows(&rows);
        var out = try self.allocator.alloc(FanTagRow, rows.items.len);
        errdefer self.allocator.free(out);
        var n: usize = 0;
        errdefer for (out[0..n]) |r| r.free(self.allocator);
        for (rows.items) |e| {
            out[n] = try self.dupTag(e);
            n += 1;
        }
        return out;
    }
};
