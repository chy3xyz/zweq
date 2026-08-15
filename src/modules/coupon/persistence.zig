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
    amount: i64,
    min_amount: i64,
    total: i64,
    per_user: i64,
    start_at: i64,
    end_at: i64,
    created_at: i64,

    pub fn free(self: CouponRow, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
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
        return .{
            .id = e.id,
            .account_id = e.account_id,
            .title = title,
            .amount = e.amount,
            .min_amount = e.min_amount,
            .total = e.total,
            .per_user = e.per_user,
            .start_at = e.start_at,
            .end_at = e.end_at,
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

    pub fn createCoupon(self: *CouponStore, tenant_id: i64, account_id: i64, title: []const u8, amount: i64, min_amount: i64, total: i64, per_user: i64, start_at: i64, end_at: i64, now: i64) !i64 {
        var row = try crud.create(self.client.coupon, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .title = title,
            .amount = amount,
            .min_amount = min_amount,
            .total = total,
            .per_user = per_user,
            .start_at = start_at,
            .end_at = end_at,
            .created_at = now,
            .updated_at = now,
        });
        defer zent.codegen.deinitEntity(infos, CouponInfo, &row, self.allocator);
        return row.id;
    }

    pub fn getCoupon(self: *CouponStore, id: i64) !?CouponRow {
        const preds = self.client.coupon.predicates;
        var entity = (try crud.first(self.client.coupon, .{preds.idEQ(.{ .int = id })})) orelse return null;
        defer zent.codegen.deinitEntity(infos, CouponInfo, &entity, self.allocator);
        return try self.dupCoupon(entity);
    }

    pub fn listCoupons(self: *CouponStore, page: usize, page_size: usize, tenant_id: i64, account_id: i64) !CouponListResult {
        var q = self.client.coupon.Query();
        defer q.deinit();
        const preds = self.client.coupon.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
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

    pub fn listUserCoupons(self: *CouponStore, page: usize, page_size: usize, tenant_id: i64, account_id: i64, openid: ?[]const u8) !CouponUserListResult {
        var q = self.client.coupon_user.Query();
        defer q.deinit();
        const preds = self.client.coupon_user.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        if (openid) |o| {
            if (o.len > 0) _ = try q.Where(.{preds.openidEQ(.{ .string = o })});
        }
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
