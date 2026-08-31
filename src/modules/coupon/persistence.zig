//! Persistence over the zent Client — 优惠券模板 + 用户券。

const std = @import("std");
const zent = @import("zent");
const crud = zent.crud_helpers;
const model = @import("model.zig");
const schema = @import("../../schema.zig");

const graph = zent.codegen.graph.buildGraph(&.{ model.Coupon, model.CouponUser });
pub const infos = graph.types;
pub const Client = schema.Client;
pub const CouponInfo = infos[0];
pub const CouponUserInfo = infos[1];

pub const CouponRow = struct {
    id: i64,
    account_id: i64,
    title: []const u8,
    amount: []const u8,
    min_amount: []const u8,
    total: i64,
    per_user: i64,
    start_at: i64,
    end_at: i64,
    status: i64,
    created_at: i64,

    pub fn free(self: CouponRow, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
        allocator.free(self.amount);
        allocator.free(self.min_amount);
    }
};

pub const CouponListResult = struct {
    items: []CouponRow,
    total: i64,

    pub fn free(self: *CouponListResult, allocator: std.mem.Allocator) void {
        for (self.items) |r| r.free(allocator);
        allocator.free(self.items);
    }
};

pub const CouponUserRow = struct {
    id: i64,
    account_id: i64,
    openid: []const u8,
    coupon_id: i64,
    code: []const u8,
    status: []const u8,
    used_at: i64,
    created_at: i64,

    pub fn free(self: CouponUserRow, allocator: std.mem.Allocator) void {
        allocator.free(self.openid);
        allocator.free(self.code);
        allocator.free(self.status);
    }
};

pub const CouponUserListResult = struct {
    items: []CouponUserRow,
    total: i64,

    pub fn free(self: *CouponUserListResult, allocator: std.mem.Allocator) void {
        for (self.items) |r| r.free(allocator);
        allocator.free(self.items);
    }
};

pub const CouponStore = struct {
    allocator: std.mem.Allocator,
    client: Client,

    pub fn init(allocator: std.mem.Allocator, client: Client) CouponStore {
        return .{ .allocator = allocator, .client = client };
    }

    fn dupCoupon(self: *CouponStore, e: anytype) !CouponRow {
        const title = try self.allocator.dupe(u8, e.title);
        errdefer self.allocator.free(title);
        const amount = try self.allocator.dupe(u8, e.amount);
        errdefer self.allocator.free(amount);
        const min_amount = try self.allocator.dupe(u8, e.min_amount);
        errdefer self.allocator.free(min_amount);
        return .{
            .id = e.id,
            .account_id = e.account_id,
            .title = title,
            .amount = amount,
            .min_amount = min_amount,
            .total = e.total,
            .per_user = e.per_user,
            .start_at = e.start_at,
            .end_at = e.end_at,
            .status = e.status,
            .created_at = e.created_at orelse 0,
        };
    }

    fn dupUser(self: *CouponStore, e: anytype) !CouponUserRow {
        const openid = try self.allocator.dupe(u8, e.openid);
        errdefer self.allocator.free(openid);
        const code = try self.allocator.dupe(u8, e.code);
        errdefer self.allocator.free(code);
        const status = try self.allocator.dupe(u8, e.status);
        errdefer self.allocator.free(status);
        return .{
            .id = e.id,
            .account_id = e.account_id,
            .openid = openid,
            .coupon_id = e.coupon_id,
            .code = code,
            .status = status,
            .used_at = e.used_at,
            .created_at = e.created_at orelse 0,
        };
    }

    // ── 券模板 ─────────────────────────────────────────────

    pub fn createCoupon(self: *CouponStore, tenant_id: i64, account_id: i64, title: []const u8, amount: i64, min_amount: i64, total: i64, per_user: i64, start_at: i64, end_at: i64, status: i64, now: i64) !i64 {
        const amount_str = try std.fmt.allocPrint(self.allocator, "{d}", .{amount});
        defer self.allocator.free(amount_str);
        const min_amount_str = try std.fmt.allocPrint(self.allocator, "{d}", .{min_amount});
        defer self.allocator.free(min_amount_str);
        var b = try self.client.coupon.Create();
        defer b.deinit();
        _ = try b.setFieldValue("tenant_id", tenant_id);
        _ = try b.setFieldValue("account_id", account_id);
        _ = try b.setFieldValue("title", title);
        _ = try b.setFieldValue("amount", amount_str);
        _ = try b.setFieldValue("min_amount", min_amount_str);
        _ = try b.setFieldValue("total", total);
        _ = try b.setFieldValue("per_user", per_user);
        _ = try b.setFieldValue("start_at", start_at);
        _ = try b.setFieldValue("end_at", end_at);
        // 显式写入，不依赖 DB 默认值（迁移加的列在老库上是 nullable）。
        _ = try b.setFieldValue("status", status);
        _ = try b.setFieldValue("created_at", now);
        _ = try b.setFieldValue("updated_at", now);
        var row = try b.Save();
        defer zent.codegen.deinitEntity(infos, CouponInfo, &row, self.allocator);
        return row.id;
    }

    pub fn getCoupon(self: *CouponStore, id: i64) !?CouponRow {
        const preds = self.client.coupon.predicates;
        var entity = (try crud.first(self.client.coupon, .{preds.idEQ(.{ .int = id })})) orelse return null;
        defer zent.codegen.deinitEntity(infos, CouponInfo, &entity, self.allocator);
        return try self.dupCoupon(entity);
    }

    /// `status` 为 -1 表示不过滤；0 下架 / 1 上架（C 端固定传 1）。
    pub fn listCoupons(self: *CouponStore, page: usize, page_size: usize, tenant_id: i64, account_id: i64, keyword: []const u8, status: i64) !CouponListResult {
        var q = self.client.coupon.Query();
        defer q.deinit();
        const preds = self.client.coupon.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        if (keyword.len > 0) _ = try q.Where(.{preds.titleContainsEscaped(keyword)});
        if (status >= 0) _ = try q.Where(.{preds.statusEQ(.{ .int = status })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderDesc("created_at")});
        var paged = try q.paged(page, page_size);
        defer paged.deinit();
        var out = try self.allocator.alloc(CouponRow, paged.items.items.len);
        var n: usize = 0;
        errdefer {
            for (out[0..n]) |r| r.free(self.allocator);
            self.allocator.free(out);
        }
        for (paged.items.items) |e| {
            out[n] = try self.dupCoupon(e);
            n += 1;
        }
        return .{ .items = out, .total = paged.total };
    }

    /// 上下架：1 上架 / 0 下架。
    pub fn setCouponStatus(self: *CouponStore, id: i64, status: i64, now: i64) !bool {
        const preds = self.client.coupon.predicates;
        const affected = try crud.update(self.client.coupon, .{
            .status = status,
            .updated_at = now,
        }, .{preds.idEQ(.{ .int = id })});
        return affected > 0;
    }

    pub fn deleteCoupon(self: *CouponStore, id: i64) !void {
        const preds = self.client.coupon.predicates;
        _ = try crud.delete(self.client.coupon, .{preds.idEQ(.{ .int = id })});
    }

    // ── 用户券 ─────────────────────────────────────────────

    /// 某用户已领某券的数量（限领检查）。
    pub fn countUserCoupons(self: *CouponStore, tenant_id: i64, coupon_id: i64, openid: []const u8) !i64 {
        var q = self.client.coupon_user.Query();
        defer q.deinit();
        const preds = self.client.coupon_user.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.coupon_idEQ(.{ .int = coupon_id })});
        _ = try q.Where(.{preds.openidEQ(.{ .string = openid })});
        return try q.Count();
    }

    /// 某券已发放总数（库存检查）。
    pub fn countIssued(self: *CouponStore, coupon_id: i64) !i64 {
        var q = self.client.coupon_user.Query();
        defer q.deinit();
        const preds = self.client.coupon_user.predicates;
        _ = try q.Where(.{preds.coupon_idEQ(.{ .int = coupon_id })});
        return try q.Count();
    }

    pub fn createUserCoupon(self: *CouponStore, tenant_id: i64, account_id: i64, openid: []const u8, coupon_id: i64, code: []const u8, now: i64) !i64 {
        var row = try crud.create(self.client.coupon_user, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .openid = openid,
            .coupon_id = coupon_id,
            .code = code,
            .status = "unused",
            .used_at = 0,
            .created_at = now,
            .updated_at = now,
        });
        defer zent.codegen.deinitEntity(infos, CouponUserInfo, &row, self.allocator);
        return row.id;
    }

    pub fn getByCode(self: *CouponStore, code: []const u8) !?CouponUserRow {
        const preds = self.client.coupon_user.predicates;
        var entity = (try crud.first(self.client.coupon_user, .{preds.codeEQ(.{ .string = code })})) orelse return null;
        defer zent.codegen.deinitEntity(infos, CouponUserInfo, &entity, self.allocator);
        return try self.dupUser(entity);
    }

    pub fn setStatus(self: *CouponStore, id: i64, status: []const u8, now: i64) !void {
        const preds = self.client.coupon_user.predicates;
        var upd = self.client.coupon_user.Update();
        defer upd.deinit();
        _ = try upd.set("status", .{ .string = status });
        _ = try upd.setFieldValue("used_at", now);
        _ = try upd.setFieldValue("updated_at", now);
        _ = try upd.Where(.{preds.idEQ(.{ .int = id })});
        _ = try upd.Save();
    }

    /// `keyword` 同时匹配 openid 与券码；`status` 为空表示不过滤（unused/used/expired）。
    pub fn listUserCoupons(self: *CouponStore, page: usize, page_size: usize, tenant_id: i64, account_id: i64, openid: ?[]const u8, keyword: []const u8, status: []const u8) !CouponUserListResult {
        var q = self.client.coupon_user.Query();
        defer q.deinit();
        const preds = self.client.coupon_user.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        if (openid) |o| {
            if (o.len > 0) _ = try q.Where(.{preds.openidEQ(.{ .string = o })});
        }
        if (keyword.len > 0) {
            const p1 = preds.openidContainsEscaped(keyword);
            const p2 = preds.codeContainsEscaped(keyword);
            _ = try q.Where(.{zent.sql.Or(&p1, &p2)});
        }
        if (status.len > 0) _ = try q.Where(.{preds.statusEQ(.{ .string = status })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderDesc("created_at")});
        var paged = try q.paged(page, page_size);
        defer paged.deinit();
        var out = try self.allocator.alloc(CouponUserRow, paged.items.items.len);
        var n: usize = 0;
        errdefer {
            for (out[0..n]) |r| r.free(self.allocator);
            self.allocator.free(out);
        }
        for (paged.items.items) |e| {
            out[n] = try self.dupUser(e);
            n += 1;
        }
        return .{ .items = out, .total = paged.total };
    }
};
