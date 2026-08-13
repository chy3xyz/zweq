//! Points service — 积分商城业务（商品 CRUD + 兑换 + 积分调整）。

const std = @import("std");
const zigmodu = @import("zigmodu");
const persist = @import("persistence.zig");
const member_persist = @import("../member/persistence.zig");

pub const PointsProductRow = persist.PointsProductRow;
pub const ProductListResult = persist.ProductListResult;
pub const PointsOrderRow = persist.PointsOrderRow;

pub const PointsError = error{
    InvalidName,
    InvalidPoints,
    InvalidStock,
    ProductNotFound,
    OutOfStock,
    FanNotFound,
    InsufficientPoints,
    NotFound,
    Unexpected,
};

pub const PointsService = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    store: *persist.PointsStore,
    fan_store: *member_persist.FanStore,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, store: *persist.PointsStore, fan_store: *member_persist.FanStore) PointsService {
        return .{ .allocator = allocator, .io = io, .store = store, .fan_store = fan_store };
    }

    fn now(self: *PointsService) i64 {
        return zigmodu.time.wallClockSeconds(self.io);
    }

    // ── 商品 ─────────────────────────────────────────────────────

    pub fn createProduct(self: *PointsService, tenant_id: i64, account_id: i64, name: []const u8, points: i64, stock: i64) PointsError!i64 {
        if (std.mem.trim(u8, name, " \t").len == 0) return error.InvalidName;
        if (points <= 0) return error.InvalidPoints;
        if (stock < 0) return error.InvalidStock;
        return self.store.createProduct(tenant_id, account_id, name, points, stock, self.now()) catch error.Unexpected;
    }

    pub fn getProduct(self: *PointsService, id: i64) PointsError!?PointsProductRow {
        return self.store.getProduct(id) catch error.Unexpected;
    }

    pub fn listProducts(self: *PointsService, page: usize, page_size: usize, tenant_id: i64, account_id: i64) PointsError!ProductListResult {
        return self.store.listProducts(page, page_size, tenant_id, account_id) catch error.Unexpected;
    }

    pub fn updateProduct(self: *PointsService, id: i64, name: []const u8, points: i64, stock: i64) PointsError!void {
        if (std.mem.trim(u8, name, " \t").len == 0) return error.InvalidName;
        if (points <= 0) return error.InvalidPoints;
        if (stock < 0) return error.InvalidStock;
        self.store.updateProduct(id, name, points, stock, self.now()) catch return error.Unexpected;
    }

    pub fn deleteProduct(self: *PointsService, id: i64) PointsError!void {
        self.store.deleteProduct(id) catch return error.Unexpected;
    }

    // ── 积分 / 兑换 ──────────────────────────────────────────────

    /// 调整粉丝积分（admin 发/扣积分）。
    pub fn adjustPoints(self: *PointsService, tenant_id: i64, account_id: i64, openid: []const u8, delta: i64) PointsError!i64 {
        return self.fan_store.adjustPoints(tenant_id, account_id, openid, delta, self.now()) catch |err| switch (err) {
            error.FanNotFound => error.FanNotFound,
            error.InsufficientPoints => error.InsufficientPoints,
            else => error.Unexpected,
        };
    }

    /// 粉丝兑换积分商品：校验库存 + 积分 → 扣积分 → 减库存 → 建订单。
    /// 返回订单 id。
    pub fn redeem(self: *PointsService, tenant_id: i64, account_id: i64, openid: []const u8, product_id: i64) PointsError!i64 {
        const prod_opt = self.store.getProduct(product_id) catch return error.Unexpected;
        const prod = prod_opt orelse return error.ProductNotFound;
        defer prod.free(self.allocator);
        if (prod.stock <= 0) return error.OutOfStock;

        const fan_opt = self.fan_store.getByOpenid(tenant_id, account_id, openid) catch return error.Unexpected;
        const fan = fan_opt orelse return error.FanNotFound;
        defer fan.free(self.allocator);
        if (fan.points < prod.points) return error.InsufficientPoints;

        _ = self.fan_store.adjustPoints(tenant_id, account_id, openid, -prod.points, self.now()) catch return error.Unexpected;
        _ = self.store.decrementStock(product_id, 1, self.now()) catch |err| switch (err) {
            error.ProductNotFound => return error.ProductNotFound,
            error.OutOfStock => return error.OutOfStock,
            else => return error.Unexpected,
        };
        return self.store.createOrder(tenant_id, account_id, openid, product_id, prod.name, prod.points, self.now()) catch error.Unexpected;
    }

    /// 查询兑换记录（openid 可空 = 全部）。
    pub fn listOrders(self: *PointsService, tenant_id: i64, account_id: i64, openid: ?[]const u8) PointsError![]PointsOrderRow {
        return self.store.listOrders(tenant_id, account_id, openid) catch error.Unexpected;
    }
};
