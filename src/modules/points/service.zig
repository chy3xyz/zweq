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

    pub fn createProduct(self: *PointsService, tenant_id: i64, account_id: i64, name: []const u8, points: i64, stock: i64, status: i64, image: []const u8, detail: []const u8) PointsError!i64 {
        if (std.mem.trim(u8, name, " \t").len == 0) return error.InvalidName;
        if (points <= 0) return error.InvalidPoints;
        if (stock < 0) return error.InvalidStock;
        return self.store.createProduct(tenant_id, account_id, name, points, stock, status, image, detail, self.now()) catch error.Unexpected;
    }

    pub fn getProduct(self: *PointsService, tenant_id: i64, id: i64) PointsError!?PointsProductRow {
        return self.store.getProduct(tenant_id, id) catch error.Unexpected;
    }

    /// `status` 为 -1 表示不过滤；0 下架 / 1 上架（C 端固定传 1）。
    pub fn listProducts(self: *PointsService, page: usize, page_size: usize, tenant_id: i64, account_id: i64, keyword: []const u8, status: i64) PointsError!ProductListResult {
        return self.store.listProducts(page, page_size, tenant_id, account_id, keyword, status) catch error.Unexpected;
    }

    pub fn updateProduct(self: *PointsService, id: i64, name: []const u8, points: i64, stock: i64, status: i64, image: []const u8, detail: []const u8) PointsError!void {
        if (std.mem.trim(u8, name, " \t").len == 0) return error.InvalidName;
        if (points <= 0) return error.InvalidPoints;
        if (stock < 0) return error.InvalidStock;
        self.store.updateProduct(id, name, points, stock, status, image, detail, self.now()) catch return error.Unexpected;
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

    /// 粉丝兑换积分商品：读校验 → 原子减库存 → 扣积分 → 建兑换记录。
    /// 三步写落在不同表（points_product / member.fan / points_order），
    /// 无法共用一个本地事务，改用补偿模式：任一步失败即返回，并把已落库的
    /// 写按相反方向回补；补偿本身再失败只能 log 留痕，无法回滚。
    /// 返回订单 id。
    pub fn redeem(self: *PointsService, tenant_id: i64, account_id: i64, openid: []const u8, product_id: i64) PointsError!i64 {
        // ── 读校验（均带租户过滤，不产生写，无需补偿）──
        const prod_opt = self.store.getProduct(tenant_id, product_id) catch return error.Unexpected;
        const prod = prod_opt orelse return error.ProductNotFound;
        defer prod.free(self.allocator);
        // 下架商品不可兑换：C 端列表与兑换入口都必须挡住。
        if (prod.status != 1) return error.ProductNotFound;
        if (prod.stock <= 0) return error.OutOfStock;

        const fan_opt = self.fan_store.getByOpenid(tenant_id, account_id, openid) catch return error.Unexpected;
        const fan = fan_opt orelse return error.FanNotFound;
        defer fan.free(self.allocator);
        if (fan.points < prod.points) return error.InsufficientPoints;

        // ── 写 1：原子减库存（guard 挡超卖）──
        const consumed = self.store.decrementStock(tenant_id, product_id, 1) catch return error.Unexpected;
        // 读校验与扣库存之间存在剩余窗口：并发兑换可在此期间抢光库存，
        // guard 命中即 affected=0，这里兜底报库存不足。
        if (!consumed) return error.OutOfStock;

        // ── 写 2：扣积分（原子 points+delta，余额下限守卫在 DB 语句内）──
        _ = self.fan_store.adjustPoints(tenant_id, account_id, openid, -prod.points, self.now()) catch |err| {
            // 扣积分失败 → 回补库存后返回；补偿失败只能留痕。
            self.store.restoreStock(tenant_id, product_id, 1) catch |rerr|
                std.log.err("points redeem 补偿失败：扣积分失败后库存未回补 product_id={d} err={s}", .{ product_id, @errorName(rerr) });
            return switch (err) {
                error.FanNotFound => error.FanNotFound,
                error.InsufficientPoints => error.InsufficientPoints,
                else => error.Unexpected,
            };
        };

        // ── 写 3：建兑换记录 ──
        return self.store.createOrder(tenant_id, account_id, openid, product_id, prod.name, prod.points, self.now()) catch {
            // 建单失败 → 按扣减的相反顺序回补积分、库存后返回。
            _ = self.fan_store.adjustPoints(tenant_id, account_id, openid, prod.points, self.now()) catch |rerr|
                std.log.err("points redeem 补偿失败：建单失败后积分未回补 openid={s} err={s}", .{ openid, @errorName(rerr) });
            self.store.restoreStock(tenant_id, product_id, 1) catch |rerr|
                std.log.err("points redeem 补偿失败：建单失败后库存未回补 product_id={d} err={s}", .{ product_id, @errorName(rerr) });
            return error.Unexpected;
        };
    }

    /// 查询兑换记录（openid 可空 = 全部）。
    pub fn listOrders(self: *PointsService, tenant_id: i64, account_id: i64, openid: ?[]const u8) PointsError![]PointsOrderRow {
        return self.store.listOrders(tenant_id, account_id, openid) catch error.Unexpected;
    }
};
