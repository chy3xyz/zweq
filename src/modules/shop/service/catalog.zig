//! 商品目录域服务：分类 / 商品 / SKU 的 CRUD 与列表（拆分自原 ShopService 单体，方法正文逐字搬运）。
const std = @import("std");
const zigmodu = @import("zigmodu");
const zent = @import("zent");
const persist = @import("../persistence.zig");
const schema = @import("../../../schema.zig");
const crud = zent.crud_helpers;
const coupon_service = @import("../../coupon/service.zig");
const member_persist = @import("../../member/persistence.zig");
const task_service = @import("../../task/service.zig");
const db_mod = @import("../../../db.zig");
const host = @import("../service.zig");

// 宿主符号沿用原名（方法正文逐字搬运、零改动）。
const ShopService = host.ShopService;
const ShopError = host.ShopError;
const ProductInput = host.ProductInput;
const SkuInput = host.SkuInput;
const OrderItemInput = host.OrderItemInput;
const AddressInput = host.AddressInput;
const OrderSummary = host.OrderSummary;
const OrderStats = host.OrderStats;
const FanOrderOverview = host.FanOrderOverview;
const ShopCategoryRow = host.ShopCategoryRow;
const ShopProductRow = host.ShopProductRow;
const ShopSkuRow = host.ShopSkuRow;
const CategoryListResult = host.CategoryListResult;
const ProductListResult = host.ProductListResult;
const ShopCartRow = host.ShopCartRow;
const ShopAddressRow = host.ShopAddressRow;
const ShopOrderRow = host.ShopOrderRow;
const ShopOrderProductRow = host.ShopOrderProductRow;
const OrderListResult = host.OrderListResult;
const ShopRefundRow = host.ShopRefundRow;
const ShopCommentRow = host.ShopCommentRow;
const RefundListResult = host.RefundListResult;
const ShopFavoriteRow = host.ShopFavoriteRow;
const ShopOutletRow = host.ShopOutletRow;
const ShopBalancePlanRow = host.ShopBalancePlanRow;
const ShopGrouponRow = host.ShopGrouponRow;
const ShopGrouponTeamRow = host.ShopGrouponTeamRow;
const ShopInviteGiftRow = host.ShopInviteGiftRow;
const ShopInviteRecordRow = host.ShopInviteRecordRow;
const ShopArticleRow = host.ShopArticleRow;
const ArticleListResult = host.ArticleListResult;
const ShopWebhookRow = host.ShopWebhookRow;

pub fn createCategory(self: *ShopService, tenant_id: i64, account_id: i64, name: []const u8, parent_id: i64, sort: i64) ShopError!i64 {
    if (std.mem.trim(u8, name, " \t").len == 0) return error.InvalidInput;
    return self.store.catalog.createCategory(tenant_id, account_id, name, parent_id, sort, self.now()) catch error.Unexpected;
}

pub fn listCategories(self: *ShopService, tenant_id: i64, account_id: i64) ShopError!CategoryListResult {
    return self.store.catalog.listCategories(tenant_id, account_id) catch error.Unexpected;
}

pub fn deleteCategory(self: *ShopService, id: i64) ShopError!void {
    _ = self.store.catalog.deleteCategory(id) catch return error.Unexpected;
}

// ── 商品 ───────────────────────────────────────────────

pub fn createProduct(self: *ShopService, tenant_id: i64, account_id: i64, p: ProductInput) ShopError!i64 {
    if (std.mem.trim(u8, p.name, " \t").len == 0 or p.price < 0 or p.stock < 0) return error.InvalidInput;
    const id = self.store.catalog.createProduct(tenant_id, account_id, p, self.now()) catch return error.Unexpected;
    // 回滚清理：SKU 写入失败时删除已建商品行；清理失败无可挽回，且各失败分支
    // 均已 return 具体错误给调用方（失败已反馈），故此处只吞错。
    errdefer _ = self.store.catalog.deleteProduct(id) catch {};

    // 默认 SKU：未传 skus 时按商品主数据建一行（spec_json="[]"）。
    if (p.skus.len == 0) {
        _ = self.store.catalog.createSku(tenant_id, account_id, id, "[]", p.image, p.price, p.stock, self.now()) catch return error.Unexpected;
    } else {
        for (p.skus) |s| {
            _ = self.store.catalog.createSku(tenant_id, account_id, id, s.spec_json, s.image, s.price, s.stock, self.now()) catch return error.Unexpected;
        }
    }
    return id;
}

pub fn getProduct(self: *ShopService, id: i64) ShopError!?ShopProductRow {
    return self.store.catalog.getProduct(id) catch error.Unexpected;
}

pub fn updateProduct(self: *ShopService, tenant_id: i64, account_id: i64, id: i64, p: ProductInput) ShopError!void {
    if (std.mem.trim(u8, p.name, " \t").len == 0 or p.price < 0 or p.stock < 0) return error.InvalidInput;
    if (!(self.store.catalog.updateProduct(id, p, self.now()) catch return error.Unexpected)) return error.NotFound;
    // 重建 SKU（幂等：删旧建新）。下面三处写入失败时商品主数据已更新、本函数
    // 仍返回成功，会让 SKU 缺失或新旧混杂，故只吞错但留痕供对账。
    self.store.catalog.deleteSkusByProduct(id) catch |err| std.log.err("[shop] 更新商品删除旧 SKU 失败 product_id={d} err={s}", .{ id, @errorName(err) });
    if (p.skus.len == 0) {
        _ = self.store.catalog.createSku(tenant_id, account_id, id, "[]", p.image, p.price, p.stock, self.now()) catch |err| std.log.err("[shop] 更新商品写入默认 SKU 失败 product_id={d} err={s}", .{ id, @errorName(err) });
    } else {
        for (p.skus) |s| {
            _ = self.store.catalog.createSku(tenant_id, account_id, id, s.spec_json, s.image, s.price, s.stock, self.now()) catch |err| std.log.err("[shop] 更新商品写入 SKU 失败 product_id={d} err={s}", .{ id, @errorName(err) });
        }
    }
}

pub fn deleteProduct(self: *ShopService, id: i64) ShopError!void {
    _ = self.store.catalog.deleteProduct(id) catch return error.Unexpected;
    // 商品行已删除且本函数返回成功；残留 SKU 仍可被 listSkus/getSku 读到，留痕对账。
    self.store.catalog.deleteSkusByProduct(id) catch |err| std.log.err("[shop] 删除商品后清理 SKU 失败 product_id={d} err={s}", .{ id, @errorName(err) });
}

/// `status` 为 -1 表示不过滤（管理端），0/1 按下架/上架筛选。
pub fn listProducts(self: *ShopService, page: usize, page_size: usize, tenant_id: i64, account_id: i64, category_id: i64, keyword: []const u8, status: i64) ShopError!ProductListResult {
    return self.store.catalog.listProducts(page, page_size, tenant_id, account_id, category_id, keyword, status) catch error.Unexpected;
}

// ── SKU ───────────────────────────────────────────────

pub fn listSkus(self: *ShopService, product_id: i64) ShopError![]ShopSkuRow {
    return self.store.catalog.listSkus(product_id) catch error.Unexpected;
}

pub fn getSku(self: *ShopService, id: i64) ShopError!?ShopSkuRow {
    return self.store.catalog.getSku(id) catch error.Unexpected;
}
// ── 购物车 ───────────────────────────────────────────
