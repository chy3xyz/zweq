//! 商品目录域存储：分类 / 商品 / SKU CRUD 与库存、销量原语。拆分自原 ShopStore，方法逐字保留。
const std = @import("std");
const zent = @import("zent");
const crud = zent.crud_helpers;
const persist = @import("persistence.zig");
const Client = persist.Client;

// 行类型经 rows.zig 引用（沿用原名，正文逐字搬运）。
const rows_mod = @import("rows.zig");
const infos = persist.infos;
const ShopCategoryInfo = persist.ShopCategoryInfo;
const ShopProductInfo = persist.ShopProductInfo;
const ShopProductSkuInfo = persist.ShopProductSkuInfo;
const ShopCartInfo = persist.ShopCartInfo;
const ShopAddressInfo = persist.ShopAddressInfo;
const ShopOrderInfo = persist.ShopOrderInfo;
const ShopOrderProductInfo = persist.ShopOrderProductInfo;
const ShopRefundInfo = persist.ShopRefundInfo;
const ShopCommentInfo = persist.ShopCommentInfo;
const ShopFavoriteInfo = persist.ShopFavoriteInfo;
const ShopOutletInfo = persist.ShopOutletInfo;
const ShopBalancePlanInfo = persist.ShopBalancePlanInfo;
const ShopGrouponInfo = persist.ShopGrouponInfo;
const ShopGrouponTeamInfo = persist.ShopGrouponTeamInfo;
const ShopInviteGiftInfo = persist.ShopInviteGiftInfo;
const ShopInviteRecordInfo = persist.ShopInviteRecordInfo;
const ShopArticleInfo = persist.ShopArticleInfo;
const ShopWebhookInfo = persist.ShopWebhookInfo;
const ShopCategoryRow = rows_mod.ShopCategoryRow;
const ShopProductRow = rows_mod.ShopProductRow;
const ShopSkuRow = rows_mod.ShopSkuRow;
const CategoryListResult = rows_mod.CategoryListResult;
const ProductListResult = rows_mod.ProductListResult;
const ShopCartRow = rows_mod.ShopCartRow;
const ShopAddressRow = rows_mod.ShopAddressRow;
const ShopOrderRow = rows_mod.ShopOrderRow;
const ShopOrderProductRow = rows_mod.ShopOrderProductRow;
const OrderListResult = rows_mod.OrderListResult;
const ShopRefundRow = rows_mod.ShopRefundRow;
const ShopCommentRow = rows_mod.ShopCommentRow;
const RefundListResult = rows_mod.RefundListResult;
const ShopFavoriteRow = rows_mod.ShopFavoriteRow;
const ShopOutletRow = rows_mod.ShopOutletRow;
const ShopBalancePlanRow = rows_mod.ShopBalancePlanRow;
const ShopGrouponRow = rows_mod.ShopGrouponRow;
const ShopGrouponTeamRow = rows_mod.ShopGrouponTeamRow;
const ShopInviteGiftRow = rows_mod.ShopInviteGiftRow;
const ShopInviteRecordRow = rows_mod.ShopInviteRecordRow;
const ShopArticleRow = rows_mod.ShopArticleRow;
const ArticleListResult = rows_mod.ArticleListResult;
const ShopWebhookRow = rows_mod.ShopWebhookRow;

/// CatalogStore 持有独立的 allocator/client 拷贝（Client 内部 driver 为共享句柄，
/// 多份值拷贝指向同一连接与 PreparedCache，与拆分前行为一致）。
pub const CatalogStore = struct {
    allocator: std.mem.Allocator,
    client: Client,

    fn dupCategory(self: *CatalogStore, e: anytype) !ShopCategoryRow {
        const name = try self.allocator.dupe(u8, e.name);
        errdefer self.allocator.free(name);
        return .{
            .id = e.id,
            .account_id = e.account_id,
            .name = name,
            .parent_id = e.parent_id,
            .sort = e.sort,
            .created_at = e.created_at orelse 0,
        };
    }

    fn dupProduct(self: *CatalogStore, e: anytype) !ShopProductRow {
        const name = try self.allocator.dupe(u8, e.name);
        errdefer self.allocator.free(name);
        const image = try self.allocator.dupe(u8, e.image);
        errdefer self.allocator.free(image);
        const images = try self.allocator.dupe(u8, e.images);
        errdefer self.allocator.free(images);
        const content = try self.allocator.dupe(u8, e.content);
        errdefer self.allocator.free(content);
        const price = try self.allocator.dupe(u8, e.price);
        errdefer self.allocator.free(price);
        const original_price = try self.allocator.dupe(u8, e.original_price);
        errdefer self.allocator.free(original_price);
        return .{
            .id = e.id,
            .account_id = e.account_id,
            .category_id = e.category_id,
            .name = name,
            .image = image,
            .images = images,
            .content = content,
            .price = price,
            .original_price = original_price,
            .stock = e.stock,
            .sales = e.sales,
            .status = e.status,
            .created_at = e.created_at orelse 0,
        };
    }

    fn dupSku(self: *CatalogStore, e: anytype) !ShopSkuRow {
        const spec_json = try self.allocator.dupe(u8, e.spec_json);
        errdefer self.allocator.free(spec_json);
        const image = try self.allocator.dupe(u8, e.image);
        errdefer self.allocator.free(image);
        const price = try self.allocator.dupe(u8, e.price);
        errdefer self.allocator.free(price);
        return .{
            .id = e.id,
            .account_id = e.account_id,
            .product_id = e.product_id,
            .spec_json = spec_json,
            .image = image,
            .price = price,
            .stock = e.stock,
        };
    }

    // ── 分类 ───────────────────────────────────────────────

    pub fn createCategory(self: *CatalogStore, tenant_id: i64, account_id: i64, name: []const u8, parent_id: i64, sort: i64, now: i64) !i64 {
        var row = try crud.create(self.client.shop_category, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .name = name,
            .parent_id = parent_id,
            .sort = sort,
            .created_at = now,
            .updated_at = now,
        });
        defer zent.codegen.deinitEntity(infos, ShopCategoryInfo, &row, self.allocator);
        return row.id;
    }

    pub fn listCategories(self: *CatalogStore, tenant_id: i64, account_id: i64) !CategoryListResult {
        var q = self.client.shop_category.Query();
        defer q.deinit();
        const preds = self.client.shop_category.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        if (account_id > 0) _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.OrderBy(&[_]zent.sql.Order{ zent.sql.OrderAsc("sort"), zent.sql.OrderAsc("id") });
        var rows = try q.All();
        defer {
            for (rows.items) |*e| zent.codegen.deinitEntity(infos, ShopCategoryInfo, e, self.allocator);
            rows.deinit();
        }
        var out = try self.allocator.alloc(ShopCategoryRow, rows.items.len);
        errdefer self.allocator.free(out);
        var n: usize = 0;
        errdefer for (out[0..n]) |r| r.free(self.allocator);
        for (rows.items) |e| {
            out[n] = try self.dupCategory(e);
            n += 1;
        }
        return .{ .items = out, .total = @intCast(out.len) };
    }

    pub fn deleteCategory(self: *CatalogStore, id: i64) !bool {
        const preds = self.client.shop_category.predicates;
        var d = self.client.shop_category.Delete();
        defer d.deinit();
        _ = try d.Where(.{preds.idEQ(.{ .int = id })});
        const affected = try d.Exec();
        return affected > 0;
    }

    // ── 商品 ───────────────────────────────────────────────

    pub fn createProduct(self: *CatalogStore, tenant_id: i64, account_id: i64, p: anytype, now: i64) !i64 {
        const price = try std.fmt.allocPrint(self.allocator, "{d}", .{p.price});
        defer self.allocator.free(price);
        const original_price = try std.fmt.allocPrint(self.allocator, "{d}", .{p.original_price});
        defer self.allocator.free(original_price);
        var row = try crud.create(self.client.shop_product, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .category_id = p.category_id,
            .name = p.name,
            .image = p.image,
            .images = p.images,
            .content = p.content,
            .price = price,
            .original_price = original_price,
            .stock = p.stock,
            .sales = 0,
            .status = p.status,
            .created_at = now,
            .updated_at = now,
        });
        defer zent.codegen.deinitEntity(infos, ShopProductInfo, &row, self.allocator);
        return row.id;
    }

    /// 事务感知读取：传入 `tx.client` 时，读取发生在同一事务内（连接池下
    /// 事务期间不能再从池里借连接，且事务外读会读到未提交前的状态）。
    pub fn getProductOn(self: *CatalogStore, client: Client, id: i64) !?ShopProductRow {
        const preds = client.shop_product.predicates;
        var entity = (try crud.first(client.shop_product, .{preds.idEQ(.{ .int = id })})) orelse return null;
        defer zent.codegen.deinitEntity(infos, ShopProductInfo, &entity, self.allocator);
        return try self.dupProduct(entity);
    }

    pub fn getProduct(self: *CatalogStore, id: i64) !?ShopProductRow {
        return self.getProductOn(self.client, id);
    }

    pub fn updateProduct(self: *CatalogStore, id: i64, p: anytype, now: i64) !bool {
        const preds = self.client.shop_product.predicates;
        var upd = self.client.shop_product.Update();
        defer upd.deinit();
        const price = try std.fmt.allocPrint(self.allocator, "{d}", .{p.price});
        defer self.allocator.free(price);
        const original_price = try std.fmt.allocPrint(self.allocator, "{d}", .{p.original_price});
        defer self.allocator.free(original_price);
        _ = try upd.set("category_id", .{ .int = p.category_id });
        _ = try upd.set("name", .{ .string = p.name });
        _ = try upd.set("image", .{ .string = p.image });
        _ = try upd.set("images", .{ .string = p.images });
        _ = try upd.set("content", .{ .string = p.content });
        _ = try upd.set("price", .{ .string = price });
        _ = try upd.set("original_price", .{ .string = original_price });
        _ = try upd.set("stock", .{ .int = p.stock });
        _ = try upd.set("status", .{ .int = p.status });
        _ = try upd.setFieldValue("updated_at", now);
        _ = try upd.Where(.{preds.idEQ(.{ .int = id })});
        return (try upd.Save()) > 0;
    }

    pub fn deleteProduct(self: *CatalogStore, id: i64) !bool {
        const preds = self.client.shop_product.predicates;
        var d = self.client.shop_product.Delete();
        defer d.deinit();
        _ = try d.Where(.{preds.idEQ(.{ .int = id })});
        const affected = try d.Exec();
        return affected > 0;
    }

    /// 商品列表：account 过滤 + 分类过滤 + 关键词 + 上下架 + 分页。
    /// `status` 为 -1 表示不过滤；0 下架 / 1 上架（C 端固定传 1）。
    pub fn listProducts(self: *CatalogStore, page: usize, page_size: usize, tenant_id: i64, account_id: i64, category_id: i64, keyword: []const u8, status: i64) !ProductListResult {
        var q = self.client.shop_product.Query();
        defer q.deinit();
        const preds = self.client.shop_product.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        if (account_id > 0) _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        if (category_id > 0) _ = try q.Where(.{preds.category_idEQ(.{ .int = category_id })});
        if (status >= 0) _ = try q.Where(.{preds.statusEQ(.{ .int = status })});
        // ContainsEscaped 会补 %…% 并转义 LIKE 通配符；Contains 是等值匹配，不能用于搜索。
        if (keyword.len > 0) _ = try q.Where(.{preds.nameContainsEscaped(keyword)});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderDesc("created_at")});
        var paged = try q.paged(page, page_size);
        defer paged.deinit();
        var out = try self.allocator.alloc(ShopProductRow, paged.items.items.len);
        var n: usize = 0;
        errdefer {
            for (out[0..n]) |r| r.free(self.allocator);
            self.allocator.free(out);
        }
        for (paged.items.items) |e| {
            out[n] = try self.dupProduct(e);
            n += 1;
        }
        return .{ .items = out, .total = paged.total };
    }

    // ── SKU ────────────────────────────────────────────────

    pub fn createSku(self: *CatalogStore, tenant_id: i64, account_id: i64, product_id: i64, spec_json: []const u8, image: []const u8, price: i64, stock: i64, now: i64) !i64 {
        const price_str = try std.fmt.allocPrint(self.allocator, "{d}", .{price});
        defer self.allocator.free(price_str);
        var row = try crud.create(self.client.shop_product_sku, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .product_id = product_id,
            .spec_json = spec_json,
            .image = image,
            .price = price_str,
            .stock = stock,
            .created_at = now,
            .updated_at = now,
        });
        defer zent.codegen.deinitEntity(infos, ShopProductSkuInfo, &row, self.allocator);
        return row.id;
    }

    pub fn listSkus(self: *CatalogStore, product_id: i64) ![]ShopSkuRow {
        var q = self.client.shop_product_sku.Query();
        defer q.deinit();
        const preds = self.client.shop_product_sku.predicates;
        _ = try q.Where(.{preds.product_idEQ(.{ .int = product_id })});
        var rows = try q.All();
        defer {
            for (rows.items) |*e| zent.codegen.deinitEntity(infos, ShopProductSkuInfo, e, self.allocator);
            rows.deinit();
        }
        var out = try self.allocator.alloc(ShopSkuRow, rows.items.len);
        errdefer self.allocator.free(out);
        var n: usize = 0;
        errdefer for (out[0..n]) |r| r.free(self.allocator);
        for (rows.items) |e| {
            out[n] = try self.dupSku(e);
            n += 1;
        }
        return out;
    }

    /// 事务感知读取，见 `getProductOn`。
    pub fn getSkuOn(self: *CatalogStore, client: Client, id: i64) !?ShopSkuRow {
        const preds = client.shop_product_sku.predicates;
        var entity = (try crud.first(client.shop_product_sku, .{preds.idEQ(.{ .int = id })})) orelse return null;
        defer zent.codegen.deinitEntity(infos, ShopProductSkuInfo, &entity, self.allocator);
        return try self.dupSku(entity);
    }

    pub fn getSku(self: *CatalogStore, id: i64) !?ShopSkuRow {
        return self.getSkuOn(self.client, id);
    }

    pub fn deleteSkusByProduct(self: *CatalogStore, product_id: i64) !void {
        const preds = self.client.shop_product_sku.predicates;
        var d = self.client.shop_product_sku.Delete();
        defer d.deinit();
        _ = try d.Where(.{preds.product_idEQ(.{ .int = product_id })});
        _ = try d.Exec();
    }

    // ── 购物车 ────────────────────────────────────────────────

    /// 原子扣 SKU 库存（乐观锁）：UPDATE stock=stock-n WHERE id=? AND stock>=n。
    pub fn consumeSkuStock(self: *CatalogStore, allocator: std.mem.Allocator, sku_id: i64, n: i64) !bool {
        const preds = self.client.shop_product_sku.predicates;
        const guard = try std.fmt.allocPrint(allocator, "stock >= {d}", .{n});
        defer allocator.free(guard);
        const affected = crud.increment(self.client.shop_product_sku, "stock", -n, &.{
            preds.idEQ(.{ .int = sku_id }),
            zent.sql.Predicate{ .raw = guard },
        }) catch return false;
        return affected > 0;
    }

    /// 商品销量累计：sales += n。
    pub fn addProductSales(self: *CatalogStore, product_id: i64, n: i64) !void {
        const preds = self.client.shop_product.predicates;
        _ = crud.increment(self.client.shop_product, "sales", n, &.{preds.idEQ(.{ .int = product_id })}) catch {};
    }

    /// 库存返还（取消/退款）：sku.stock += n；销量回退：product.sales -= n。
    pub fn restoreSkuStock(self: *CatalogStore, sku_id: i64, n: i64) !void {
        const sp = self.client.shop_product_sku.predicates;
        _ = crud.increment(self.client.shop_product_sku, "stock", n, &.{sp.idEQ(.{ .int = sku_id })}) catch {};
    }

    pub fn subtractProductSales(self: *CatalogStore, product_id: i64, n: i64) !void {
        const preds = self.client.shop_product.predicates;
        _ = crud.increment(self.client.shop_product, "sales", -n, &.{preds.idEQ(.{ .int = product_id })}) catch {};
    }
};
