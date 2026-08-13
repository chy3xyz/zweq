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
        defer zent.codegen.deinitEntity(infos, FanInfo, &entity, self.allocator);
        return try self.dup(entity);
    }

    /// Upsert a fan by (account_id, openid). Returns the fan id.
    pub fn upsert(self: *FanStore, tenant_id: i64, account_id: i64, openid: []const u8, unionid: []const u8, nickname: []const u8, avatar: []const u8, subscribed: bool, subscribe_time: i64, now: i64) !i64 {
        if (try self.getByOpenid(tenant_id, account_id, openid)) |row| {
            defer row.free(self.allocator);
            const preds = self.client.fan.predicates;
            var upd = self.client.fan.Update();
            defer upd.deinit();
            _ = try upd.set("unionid", .{ .string = unionid });
            if (nickname.len > 0) _ = try upd.set("nickname", .{ .string = nickname });
            if (avatar.len > 0) _ = try upd.set("avatar", .{ .string = avatar });
            _ = try upd.set("subscribed", .{ .bool = subscribed });
            if (subscribe_time > 0) _ = try upd.setFieldValue("subscribe_time", subscribe_time);
            _ = try upd.setFieldValue("updated_at", now);
            _ = try upd.Where(.{preds.idEQ(.{ .int = row.id })});
            _ = try upd.Save();
            return row.id;
        }
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
        var row = try b.Save();
        defer zent.codegen.deinitEntity(infos, FanInfo, &row, self.allocator);
        return row.id;
    }

    /// 调整粉丝积分（delta 可为正/负）。返回调整后的积分。
    pub fn adjustPoints(self: *FanStore, tenant_id: i64, account_id: i64, openid: []const u8, delta: i64, now: i64) !i64 {
        const row_opt = try self.getByOpenid(tenant_id, account_id, openid);
        const row = row_opt orelse return error.FanNotFound;
        defer row.free(self.allocator);
        const new_points = row.points + delta;
        if (new_points < 0) return error.InsufficientPoints;
        const preds = self.client.fan.predicates;
        var upd = self.client.fan.Update();
        defer upd.deinit();
        _ = try upd.setFieldValue("points", new_points);
        _ = try upd.setFieldValue("updated_at", now);
        _ = try upd.Where(.{preds.idEQ(.{ .int = row.id })});
        _ = try upd.Save();
        return new_points;
    }

    pub fn getById(self: *FanStore, id: i64) !?FanRow {
        var q = self.client.fan.Query();
        defer q.deinit();
        const preds = self.client.fan.predicates;
        _ = try q.Where(.{preds.idEQ(.{ .int = id })});
        const entity_opt = try q.First();
        var entity = entity_opt orelse return null;
        defer zent.codegen.deinitEntity(infos, FanInfo, &entity, self.allocator);
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
        defer zent.codegen.deinitEntity(infos, FanTagInfo, &entity, self.allocator);
        return try self.dupTag(entity);
    }

    /// Upsert by wx_tag_id。返回行 id。
    pub fn upsert(self: *TagStore, tenant_id: i64, account_id: i64, wx_tag_id: i64, name: []const u8, now: i64) !i64 {
        if (try self.getByWxTagId(tenant_id, account_id, wx_tag_id)) |row| {
            defer row.free(self.allocator);
            const preds = self.client.fan_tag.predicates;
            var upd = self.client.fan_tag.Update();
            defer upd.deinit();
            _ = try upd.set("name", .{ .string = name });
            _ = try upd.setFieldValue("updated_at", now);
            _ = try upd.Where(.{preds.idEQ(.{ .int = row.id })});
            _ = try upd.Save();
            return row.id;
        }
        var b = try self.client.fan_tag.Create();
        defer b.deinit();
        _ = try b.setFieldValue("tenant_id", tenant_id);
        _ = try b.setFieldValue("account_id", account_id);
        _ = try b.setFieldValue("wx_tag_id", wx_tag_id);
        _ = try b.setFieldValue("name", name);
        _ = try b.setFieldValue("created_at", now);
        _ = try b.setFieldValue("updated_at", now);
        var nrow = try b.Save();
        defer zent.codegen.deinitEntity(infos, FanTagInfo, &nrow, self.allocator);
        return nrow.id;
    }

    pub fn list(self: *TagStore, tenant_id: i64, account_id: i64) ![]FanTagRow {
        var q = self.client.fan_tag.Query();
        defer q.deinit();
        const preds = self.client.fan_tag.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderAsc("wx_tag_id")});
        var rows = try q.All();
        defer {
            for (rows.items) |*e| zent.codegen.deinitEntity(infos, FanTagInfo, e, self.allocator);
            rows.deinit();
        }
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
