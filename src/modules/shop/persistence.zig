//! Persistence over the zent Client — 商城商品域（分类/商品/SKU）。

const std = @import("std");
const zent = @import("zent");
const crud = zent.crud_helpers;
const model = @import("model.zig");
const schema = @import("../../schema.zig");

const graph = zent.codegen.graph.buildGraph(&.{ model.ShopCategory, model.ShopProduct, model.ShopProductSku, model.ShopCart, model.ShopAddress, model.ShopOrder, model.ShopOrderProduct, model.ShopRefund, model.ShopComment, model.ShopFavorite, model.ShopOutlet, model.ShopBalancePlan, model.ShopGroupon, model.ShopGrouponTeam, model.ShopInviteGift, model.ShopInviteRecord, model.ShopArticle, model.ShopWebhook });
pub const infos = graph.types;
pub const Client = schema.Client;
pub const ShopCategoryInfo = infos[0];
pub const ShopProductInfo = infos[1];
pub const ShopProductSkuInfo = infos[2];
pub const ShopCartInfo = infos[3];
pub const ShopAddressInfo = infos[4];
pub const ShopOrderInfo = infos[5];
pub const ShopOrderProductInfo = infos[6];
pub const ShopRefundInfo = infos[7];
pub const ShopCommentInfo = infos[8];
pub const ShopFavoriteInfo = infos[9];
pub const ShopOutletInfo = infos[10];
pub const ShopBalancePlanInfo = infos[11];
pub const ShopGrouponInfo = infos[12];
pub const ShopGrouponTeamInfo = infos[13];
pub const ShopInviteGiftInfo = infos[14];
pub const ShopInviteRecordInfo = infos[15];
pub const ShopArticleInfo = infos[16];
pub const ShopWebhookInfo = infos[17];

// ── 行类型 ────────────────────────────────────────────────

pub const ShopCategoryRow = struct {
    id: i64,
    account_id: i64,
    name: []const u8,
    parent_id: i64,
    sort: i64,
    created_at: i64,

    pub fn free(self: ShopCategoryRow, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }
};

pub const ShopProductRow = struct {
    id: i64,
    account_id: i64,
    category_id: i64,
    name: []const u8,
    image: []const u8,
    content: []const u8,
    price: i64,
    original_price: i64,
    stock: i64,
    sales: i64,
    status: i64,
    created_at: i64,

    pub fn free(self: ShopProductRow, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.image);
        allocator.free(self.content);
    }
};

pub const ShopSkuRow = struct {
    id: i64,
    account_id: i64,
    product_id: i64,
    spec_json: []const u8,
    image: []const u8,
    price: i64,
    stock: i64,

    pub fn free(self: ShopSkuRow, allocator: std.mem.Allocator) void {
        allocator.free(self.spec_json);
        allocator.free(self.image);
    }
};

pub const CategoryListResult = struct {
    items: []ShopCategoryRow,
    total: i64,

    pub fn free(self: *CategoryListResult, allocator: std.mem.Allocator) void {
        for (self.items) |r| r.free(allocator);
        allocator.free(self.items);
    }
};

pub const ProductListResult = struct {
    items: []ShopProductRow,
    total: i64,

    pub fn free(self: *ProductListResult, allocator: std.mem.Allocator) void {
        for (self.items) |r| r.free(allocator);
        allocator.free(self.items);
    }
};

// ── Store ─────────────────────────────────────────────────


// ── 交易行类型 ────────────────────────────────────────────

pub const ShopCartRow = struct {
    id: i64,
    account_id: i64,
    openid: []const u8,
    product_id: i64,
    sku_id: i64,
    quantity: i64,
    created_at: i64,

    pub fn free(self: ShopCartRow, allocator: std.mem.Allocator) void {
        allocator.free(self.openid);
    }
};

pub const ShopAddressRow = struct {
    id: i64,
    account_id: i64,
    openid: []const u8,
    name: []const u8,
    mobile: []const u8,
    region: []const u8,
    detail: []const u8,
    is_default: i64,
    created_at: i64,

    pub fn free(self: ShopAddressRow, allocator: std.mem.Allocator) void {
        allocator.free(self.openid);
        allocator.free(self.name);
        allocator.free(self.mobile);
        allocator.free(self.region);
        allocator.free(self.detail);
    }
};

pub const ShopOrderRow = struct {
    id: i64,
    account_id: i64,
    order_no: []const u8,
    client_trade_no: []const u8,
    openid: []const u8,
    total_amount: i64,
    pay_amount: i64,
    status: i64,
    address_json: []const u8,
    express_company: []const u8,
    express_no: []const u8,
    paid_at: i64,
    pickup_type: []const u8,
    pickup_code: []const u8,
    store_id: i64,
    groupon_team_id: i64,
    created_at: i64,

    pub fn free(self: ShopOrderRow, allocator: std.mem.Allocator) void {
        allocator.free(self.order_no);
        allocator.free(self.client_trade_no);
        allocator.free(self.openid);
        allocator.free(self.address_json);
        allocator.free(self.express_company);
        allocator.free(self.express_no);
        allocator.free(self.pickup_type);
        allocator.free(self.pickup_code);
    }
};

pub const ShopOrderProductRow = struct {
    id: i64,
    order_id: i64,
    product_id: i64,
    sku_id: i64,
    name: []const u8,
    image: []const u8,
    spec_json: []const u8,
    price: i64,
    quantity: i64,

    pub fn free(self: ShopOrderProductRow, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.image);
        allocator.free(self.spec_json);
    }
};

pub const OrderListResult = struct {
    items: []ShopOrderRow,
    total: i64,

    pub fn free(self: *OrderListResult, allocator: std.mem.Allocator) void {
        for (self.items) |r| r.free(allocator);
        allocator.free(self.items);
    }
};

pub const ShopRefundRow = struct {
    id: i64,
    account_id: i64,
    order_id: i64,
    openid: []const u8,
    reason: []const u8,
    amount: i64,
    status: i64,
    created_at: i64,

    pub fn free(self: ShopRefundRow, allocator: std.mem.Allocator) void {
        allocator.free(self.openid);
        allocator.free(self.reason);
    }
};

pub const ShopCommentRow = struct {
    id: i64,
    account_id: i64,
    order_product_id: i64,
    product_id: i64,
    openid: []const u8,
    star: i64,
    content: []const u8,
    created_at: i64,

    pub fn free(self: ShopCommentRow, allocator: std.mem.Allocator) void {
        allocator.free(self.openid);
        allocator.free(self.content);
    }
};

pub const RefundListResult = struct {
    items: []ShopRefundRow,
    total: i64,

    pub fn free(self: *RefundListResult, allocator: std.mem.Allocator) void {
        for (self.items) |r| r.free(allocator);
        allocator.free(self.items);
    }
};

pub const ShopFavoriteRow = struct {
    id: i64,
    account_id: i64,
    openid: []const u8,
    product_id: i64,
    created_at: i64,

    pub fn free(self: ShopFavoriteRow, allocator: std.mem.Allocator) void {
        allocator.free(self.openid);
    }
};

pub const ShopOutletRow = struct {
    id: i64,
    account_id: i64,
    name: []const u8,
    address: []const u8,
    mobile: []const u8,
    status: i64,
    created_at: i64,

    pub fn free(self: ShopOutletRow, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.address);
        allocator.free(self.mobile);
    }
};

pub const ShopBalancePlanRow = struct {
    id: i64,
    account_id: i64,
    name: []const u8,
    amount: i64,
    bonus: i64,
    status: i64,
    created_at: i64,

    pub fn free(self: ShopBalancePlanRow, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }
};

pub const ShopGrouponRow = struct {
    id: i64,
    account_id: i64,
    product_id: i64,
    group_price: i64,
    group_size: i64,
    start_at: i64,
    end_at: i64,
    status: i64,
    created_at: i64,
};

pub const ShopGrouponTeamRow = struct {
    id: i64,
    account_id: i64,
    activity_id: i64,
    leader_openid: []const u8,
    current: i64,
    status: i64,
    created_at: i64,

    pub fn free(self: ShopGrouponTeamRow, allocator: std.mem.Allocator) void {
        allocator.free(self.leader_openid);
    }
};

pub const ShopInviteGiftRow = struct {
    id: i64,
    account_id: i64,
    target_count: i64,
    reward_type: []const u8,
    reward_value: i64,
    status: i64,
    created_at: i64,

    pub fn free(self: ShopInviteGiftRow, allocator: std.mem.Allocator) void {
        allocator.free(self.reward_type);
    }
};

pub const ShopInviteRecordRow = struct {
    id: i64,
    account_id: i64,
    inviter_openid: []const u8,
    invitee_openid: []const u8,
    created_at: i64,

    pub fn free(self: ShopInviteRecordRow, allocator: std.mem.Allocator) void {
        allocator.free(self.inviter_openid);
        allocator.free(self.invitee_openid);
    }
};

pub const ShopArticleRow = struct {
    id: i64,
    account_id: i64,
    title: []const u8,
    content: []const u8,
    status: i64,
    created_at: i64,

    pub fn free(self: ShopArticleRow, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
        allocator.free(self.content);
    }
};

pub const ArticleListResult = struct {
    items: []ShopArticleRow,
    total: i64,

    pub fn free(self: *ArticleListResult, allocator: std.mem.Allocator) void {
        for (self.items) |r| r.free(allocator);
        allocator.free(self.items);
    }
};

pub const ShopWebhookRow = struct {
    id: i64,
    account_id: i64,
    url: []const u8,
    events: []const u8,
    status: i64,
    created_at: i64,

    pub fn free(self: ShopWebhookRow, allocator: std.mem.Allocator) void {
        allocator.free(self.url);
        allocator.free(self.events);
    }
};

pub const ShopStore = struct {
    allocator: std.mem.Allocator,
    client: Client,

    pub fn init(allocator: std.mem.Allocator, client: Client) ShopStore {
        return .{ .allocator = allocator, .client = client };
    }

    fn dupCategory(self: *ShopStore, e: anytype) !ShopCategoryRow {
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

    fn dupProduct(self: *ShopStore, e: anytype) !ShopProductRow {
        const name = try self.allocator.dupe(u8, e.name);
        errdefer self.allocator.free(name);
        const image = try self.allocator.dupe(u8, e.image);
        errdefer self.allocator.free(image);
        const content = try self.allocator.dupe(u8, e.content);
        errdefer self.allocator.free(content);
        return .{
            .id = e.id,
            .account_id = e.account_id,
            .category_id = e.category_id,
            .name = name,
            .image = image,
            .content = content,
            .price = e.price,
            .original_price = e.original_price,
            .stock = e.stock,
            .sales = e.sales,
            .status = e.status,
            .created_at = e.created_at orelse 0,
        };
    }

    fn dupSku(self: *ShopStore, e: anytype) !ShopSkuRow {
        const spec_json = try self.allocator.dupe(u8, e.spec_json);
        errdefer self.allocator.free(spec_json);
        const image = try self.allocator.dupe(u8, e.image);
        errdefer self.allocator.free(image);
        return .{
            .id = e.id,
            .account_id = e.account_id,
            .product_id = e.product_id,
            .spec_json = spec_json,
            .image = image,
            .price = e.price,
            .stock = e.stock,
        };
    }

    // ── 分类 ───────────────────────────────────────────────

    pub fn createCategory(self: *ShopStore, tenant_id: i64, account_id: i64, name: []const u8, parent_id: i64, sort: i64, now: i64) !i64 {
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

    pub fn listCategories(self: *ShopStore, tenant_id: i64, account_id: i64) !CategoryListResult {
        var q = self.client.shop_category.Query();
        defer q.deinit();
        const preds = self.client.shop_category.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        if (account_id > 0) _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderAsc("sort"), zent.sql.OrderAsc("id")});
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

    pub fn deleteCategory(self: *ShopStore, id: i64) !bool {
        const preds = self.client.shop_category.predicates;
        var d = self.client.shop_category.Delete();
        defer d.deinit();
        _ = try d.Where(.{preds.idEQ(.{ .int = id })});
        const affected = try d.Exec();
        return affected > 0;
    }

    // ── 商品 ───────────────────────────────────────────────

    pub fn createProduct(self: *ShopStore, tenant_id: i64, account_id: i64, p: anytype, now: i64) !i64 {
        var row = try crud.create(self.client.shop_product, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .category_id = p.category_id,
            .name = p.name,
            .image = p.image,
            .content = p.content,
            .price = p.price,
            .original_price = p.original_price,
            .stock = p.stock,
            .sales = 0,
            .status = p.status,
            .created_at = now,
            .updated_at = now,
        });
        defer zent.codegen.deinitEntity(infos, ShopProductInfo, &row, self.allocator);
        return row.id;
    }

    pub fn getProduct(self: *ShopStore, id: i64) !?ShopProductRow {
        const preds = self.client.shop_product.predicates;
        var entity = (try crud.first(self.client.shop_product, .{preds.idEQ(.{ .int = id })})) orelse return null;
        defer zent.codegen.deinitEntity(infos, ShopProductInfo, &entity, self.allocator);
        return try self.dupProduct(entity);
    }

    pub fn updateProduct(self: *ShopStore, id: i64, p: anytype, now: i64) !bool {
        const preds = self.client.shop_product.predicates;
        var upd = self.client.shop_product.Update();
        defer upd.deinit();
        _ = try upd.set("category_id", .{ .int = p.category_id });
        _ = try upd.set("name", .{ .string = p.name });
        _ = try upd.set("image", .{ .string = p.image });
        _ = try upd.set("content", .{ .string = p.content });
        _ = try upd.set("price", .{ .int = p.price });
        _ = try upd.set("original_price", .{ .int = p.original_price });
        _ = try upd.set("stock", .{ .int = p.stock });
        _ = try upd.set("status", .{ .int = p.status });
        _ = try upd.setFieldValue("updated_at", now);
        _ = try upd.Where(.{preds.idEQ(.{ .int = id })});
        return (try upd.Save()) > 0;
    }

    pub fn deleteProduct(self: *ShopStore, id: i64) !bool {
        const preds = self.client.shop_product.predicates;
        var d = self.client.shop_product.Delete();
        defer d.deinit();
        _ = try d.Where(.{preds.idEQ(.{ .int = id })});
        const affected = try d.Exec();
        return affected > 0;
    }

    /// 商品列表：account 过滤 + 分类过滤 + 关键词 + 仅上架 + 分页（on_sale=true 用于 C 端）。
    pub fn listProducts(self: *ShopStore, page: usize, page_size: usize, tenant_id: i64, account_id: i64, category_id: i64, keyword: []const u8, on_sale: bool) !ProductListResult {
        var q = self.client.shop_product.Query();
        defer q.deinit();
        const preds = self.client.shop_product.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        if (account_id > 0) _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        if (category_id > 0) _ = try q.Where(.{preds.category_idEQ(.{ .int = category_id })});
        if (on_sale) _ = try q.Where(.{preds.statusEQ(.{ .int = 1 })});
        if (keyword.len > 0) _ = try q.Where(.{preds.nameContains(keyword)});
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

    pub fn createSku(self: *ShopStore, tenant_id: i64, account_id: i64, product_id: i64, spec_json: []const u8, image: []const u8, price: i64, stock: i64, now: i64) !i64 {
        var row = try crud.create(self.client.shop_product_sku, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .product_id = product_id,
            .spec_json = spec_json,
            .image = image,
            .price = price,
            .stock = stock,
            .created_at = now,
            .updated_at = now,
        });
        defer zent.codegen.deinitEntity(infos, ShopProductSkuInfo, &row, self.allocator);
        return row.id;
    }

    pub fn listSkus(self: *ShopStore, product_id: i64) ![]ShopSkuRow {
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

    pub fn getSku(self: *ShopStore, id: i64) !?ShopSkuRow {
        const preds = self.client.shop_product_sku.predicates;
        var entity = (try crud.first(self.client.shop_product_sku, .{preds.idEQ(.{ .int = id })})) orelse return null;
        defer zent.codegen.deinitEntity(infos, ShopProductSkuInfo, &entity, self.allocator);
        return try self.dupSku(entity);
    }

    pub fn deleteSkusByProduct(self: *ShopStore, product_id: i64) !void {
        const preds = self.client.shop_product_sku.predicates;
        var d = self.client.shop_product_sku.Delete();
        defer d.deinit();
        _ = try d.Where(.{preds.product_idEQ(.{ .int = product_id })});
        _ = try d.Exec();
    }

// ── 购物车 ────────────────────────────────────────────────

    pub fn upsertCart(self: *ShopStore, tenant_id: i64, account_id: i64, openid: []const u8, product_id: i64, sku_id: i64, quantity: i64, now: i64) !i64 {
        // 已存在则数量累加
        var q = self.client.shop_cart.Query();
        defer q.deinit();
        const preds = self.client.shop_cart.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.openidEQ(.{ .string = openid })});
        _ = try q.Where(.{preds.sku_idEQ(.{ .int = sku_id })});
        const entity_opt = try q.First();
        if (entity_opt) |e_opt| {
            var e = e_opt;
            defer zent.codegen.deinitEntity(infos, ShopCartInfo, &e, self.allocator);
            var upd = self.client.shop_cart.Update();
            defer upd.deinit();
            _ = try upd.set("quantity", .{ .int = e.quantity + quantity });
            _ = try upd.Where(.{preds.idEQ(.{ .int = e.id })});
            _ = try upd.Save();
            return e.id;
        }
        var row = try crud.create(self.client.shop_cart, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .openid = openid,
            .product_id = product_id,
            .sku_id = sku_id,
            .quantity = quantity,
            .created_at = now,
            .updated_at = now,
        });
        defer zent.codegen.deinitEntity(infos, ShopCartInfo, &row, self.allocator);
        return row.id;
    }

    pub fn listCarts(self: *ShopStore, tenant_id: i64, openid: []const u8) ![]ShopCartRow {
        var q = self.client.shop_cart.Query();
        defer q.deinit();
        const preds = self.client.shop_cart.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.openidEQ(.{ .string = openid })});
        var rows = try q.All();
        defer {
            for (rows.items) |*e| zent.codegen.deinitEntity(infos, ShopCartInfo, e, self.allocator);
            rows.deinit();
        }
        var out = try self.allocator.alloc(ShopCartRow, rows.items.len);
        errdefer self.allocator.free(out);
        var n: usize = 0;
        errdefer for (out[0..n]) |r| r.free(self.allocator);
        for (rows.items) |e| {
            const openid_dup = try self.allocator.dupe(u8, e.openid);
            out[n] = .{ .id = e.id, .account_id = e.account_id, .openid = openid_dup, .product_id = e.product_id, .sku_id = e.sku_id, .quantity = e.quantity, .created_at = e.created_at orelse 0 };
            n += 1;
        }
        return out;
    }

    pub fn updateCartQuantity(self: *ShopStore, id: i64, quantity: i64) !bool {
        const preds = self.client.shop_cart.predicates;
        var upd = self.client.shop_cart.Update();
        defer upd.deinit();
        _ = try upd.set("quantity", .{ .int = quantity });
        _ = try upd.Where(.{preds.idEQ(.{ .int = id })});
        return (try upd.Save()) > 0;
    }

    pub fn deleteCart(self: *ShopStore, id: i64) !bool {
        const preds = self.client.shop_cart.predicates;
        var d = self.client.shop_cart.Delete();
        defer d.deinit();
        _ = try d.Where(.{preds.idEQ(.{ .int = id })});
        return (try d.Exec()) > 0;
    }

// ── 地址 ──────────────────────────────────────────────────

    pub fn createAddress(self: *ShopStore, tenant_id: i64, account_id: i64, a: anytype, now: i64) !i64 {
        var row = try crud.create(self.client.shop_address, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .openid = a.openid,
            .name = a.name,
            .mobile = a.mobile,
            .region = a.region,
            .detail = a.detail,
            .is_default = a.is_default,
            .created_at = now,
            .updated_at = now,
        });
        defer zent.codegen.deinitEntity(infos, ShopAddressInfo, &row, self.allocator);
        if (a.is_default == 1) {
            self.clearDefaultAddress(tenant_id, a.openid, row.id) catch {};
        }
        return row.id;
    }

    fn clearDefaultAddress(self: *ShopStore, tenant_id: i64, openid: []const u8, except_id: i64) !void {
        const preds = self.client.shop_address.predicates;
        var upd = self.client.shop_address.Update();
        defer upd.deinit();
        _ = try upd.set("is_default", .{ .int = 0 });
        _ = try upd.Where(.{ preds.tenant_idEQ(.{ .int = tenant_id }), preds.openidEQ(.{ .string = openid }), preds.is_defaultEQ(.{ .int = 1 }), preds.idNE(.{ .int = except_id }) });
        _ = try upd.Save();
    }

    pub fn listAddresses(self: *ShopStore, tenant_id: i64, openid: []const u8) ![]ShopAddressRow {
        var q = self.client.shop_address.Query();
        defer q.deinit();
        const preds = self.client.shop_address.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.openidEQ(.{ .string = openid })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderDesc("is_default"), zent.sql.OrderDesc("created_at")});
        var rows = try q.All();
        defer {
            for (rows.items) |*e| zent.codegen.deinitEntity(infos, ShopAddressInfo, e, self.allocator);
            rows.deinit();
        }
        var out = try self.allocator.alloc(ShopAddressRow, rows.items.len);
        errdefer self.allocator.free(out);
        var n: usize = 0;
        errdefer for (out[0..n]) |r| r.free(self.allocator);
        for (rows.items) |e| {
            const openid_dup = try self.allocator.dupe(u8, e.openid);
            errdefer self.allocator.free(openid_dup);
            const name = try self.allocator.dupe(u8, e.name);
            errdefer self.allocator.free(name);
            const mobile = try self.allocator.dupe(u8, e.mobile);
            errdefer self.allocator.free(mobile);
            const region = try self.allocator.dupe(u8, e.region);
            errdefer self.allocator.free(region);
            const detail = try self.allocator.dupe(u8, e.detail);
            out[n] = .{ .id = e.id, .account_id = e.account_id, .openid = openid_dup, .name = name, .mobile = mobile, .region = region, .detail = detail, .is_default = e.is_default, .created_at = e.created_at orelse 0 };
            n += 1;
        }
        return out;
    }

    pub fn getAddress(self: *ShopStore, id: i64) !?ShopAddressRow {
        const preds = self.client.shop_address.predicates;
        var entity = (try crud.first(self.client.shop_address, .{preds.idEQ(.{ .int = id })})) orelse return null;
        defer zent.codegen.deinitEntity(infos, ShopAddressInfo, &entity, self.allocator);
        const openid_dup = try self.allocator.dupe(u8, entity.openid);
        const name = try self.allocator.dupe(u8, entity.name);
        const mobile = try self.allocator.dupe(u8, entity.mobile);
        const region = try self.allocator.dupe(u8, entity.region);
        const detail = try self.allocator.dupe(u8, entity.detail);
        return .{ .id = entity.id, .account_id = entity.account_id, .openid = openid_dup, .name = name, .mobile = mobile, .region = region, .detail = detail, .is_default = entity.is_default, .created_at = entity.created_at orelse 0 };
    }

    pub fn deleteAddress(self: *ShopStore, id: i64) !bool {
        const preds = self.client.shop_address.predicates;
        var d = self.client.shop_address.Delete();
        defer d.deinit();
        _ = try d.Where(.{preds.idEQ(.{ .int = id })});
        return (try d.Exec()) > 0;
    }

// ── 订单 ──────────────────────────────────────────────────

    pub fn createOrder(self: *ShopStore, tenant_id: i64, account_id: i64, order_no: []const u8, client_trade_no: []const u8, openid: []const u8, total_amount: i64, pay_amount: i64, address_json: []const u8, pickup_type: []const u8, pickup_code: []const u8, store_id: i64, groupon_team_id: i64, now: i64) !i64 {
        var row = try crud.create(self.client.shop_order, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .order_no = order_no,
            .client_trade_no = client_trade_no,
            .openid = openid,
            .total_amount = total_amount,
            .pay_amount = pay_amount,
            .status = 0,
            .address_json = address_json,
            .express_company = "",
            .express_no = "",
            .paid_at = 0,
            .pickup_type = pickup_type,
            .pickup_code = pickup_code,
            .store_id = store_id,
            .groupon_team_id = groupon_team_id,
            .created_at = now,
            .updated_at = now,
        });
        defer zent.codegen.deinitEntity(infos, ShopOrderInfo, &row, self.allocator);
        return row.id;
    }

    pub fn createOrderProduct(self: *ShopStore, tenant_id: i64, account_id: i64, order_id: i64, o: anytype, now: i64) !i64 {
        var row = try crud.create(self.client.shop_order_product, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .order_id = order_id,
            .product_id = o.product_id,
            .sku_id = o.sku_id,
            .name = o.name,
            .image = o.image,
            .spec_json = o.spec_json,
            .price = o.price,
            .quantity = o.quantity,
            .created_at = now,
            .updated_at = now,
        });
        defer zent.codegen.deinitEntity(infos, ShopOrderProductInfo, &row, self.allocator);
        return row.id;
    }

    pub fn getByClientTradeNo(self: *ShopStore, tenant_id: i64, client_trade_no: []const u8) !?ShopOrderRow {
        if (client_trade_no.len == 0) return null;
        var q = self.client.shop_order.Query();
        defer q.deinit();
        const preds = self.client.shop_order.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.client_trade_noEQ(.{ .string = client_trade_no })});
        const entity_opt = try q.First();
        var entity = entity_opt orelse return null;
        defer zent.codegen.deinitEntity(infos, ShopOrderInfo, &entity, self.allocator);
        return .{
            .id = entity.id,
            .account_id = entity.account_id,
            .order_no = try self.allocator.dupe(u8, entity.order_no),
            .client_trade_no = try self.allocator.dupe(u8, entity.client_trade_no),
            .openid = try self.allocator.dupe(u8, entity.openid),
            .pickup_type = try self.allocator.dupe(u8, entity.pickup_type),
            .pickup_code = try self.allocator.dupe(u8, entity.pickup_code),
            .store_id = entity.store_id,
            .groupon_team_id = entity.groupon_team_id,
            .total_amount = entity.total_amount,
            .pay_amount = entity.pay_amount,
            .status = entity.status,
            .address_json = try self.allocator.dupe(u8, entity.address_json),
            .express_company = try self.allocator.dupe(u8, entity.express_company),
            .express_no = try self.allocator.dupe(u8, entity.express_no),
            .paid_at = entity.paid_at,
            .created_at = entity.created_at orelse 0,
        };
    }

    pub fn getOrder(self: *ShopStore, id: i64) !?ShopOrderRow {
        const preds = self.client.shop_order.predicates;
        var entity = (try crud.first(self.client.shop_order, .{preds.idEQ(.{ .int = id })})) orelse return null;
        defer zent.codegen.deinitEntity(infos, ShopOrderInfo, &entity, self.allocator);
        return .{
            .id = entity.id,
            .account_id = entity.account_id,
            .order_no = try self.allocator.dupe(u8, entity.order_no),
            .client_trade_no = try self.allocator.dupe(u8, entity.client_trade_no),
            .openid = try self.allocator.dupe(u8, entity.openid),
            .pickup_type = try self.allocator.dupe(u8, entity.pickup_type),
            .pickup_code = try self.allocator.dupe(u8, entity.pickup_code),
            .store_id = entity.store_id,
            .groupon_team_id = entity.groupon_team_id,
            .total_amount = entity.total_amount,
            .pay_amount = entity.pay_amount,
            .status = entity.status,
            .address_json = try self.allocator.dupe(u8, entity.address_json),
            .express_company = try self.allocator.dupe(u8, entity.express_company),
            .express_no = try self.allocator.dupe(u8, entity.express_no),
            .paid_at = entity.paid_at,
            .created_at = entity.created_at orelse 0,
        };
    }

    pub fn listOrders(self: *ShopStore, page: usize, page_size: usize, tenant_id: i64, account_id: i64, openid: []const u8, status: i64) !OrderListResult {
        var q = self.client.shop_order.Query();
        defer q.deinit();
        const preds = self.client.shop_order.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        if (account_id > 0) _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        if (openid.len > 0) _ = try q.Where(.{preds.openidEQ(.{ .string = openid })});
        if (status >= 0) _ = try q.Where(.{preds.statusEQ(.{ .int = status })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderDesc("created_at")});
        var paged = try q.paged(page, page_size);
        defer paged.deinit();
        var out = try self.allocator.alloc(ShopOrderRow, paged.items.items.len);
        var n: usize = 0;
        errdefer {
            for (out[0..n]) |r| r.free(self.allocator);
            self.allocator.free(out);
        }
        for (paged.items.items) |e| {
            out[n] = .{
                .id = e.id,
                .account_id = e.account_id,
                .order_no = try self.allocator.dupe(u8, e.order_no),
                .client_trade_no = try self.allocator.dupe(u8, e.client_trade_no),
                .openid = try self.allocator.dupe(u8, e.openid),
                .pickup_type = try self.allocator.dupe(u8, e.pickup_type),
                .pickup_code = try self.allocator.dupe(u8, e.pickup_code),
                .store_id = e.store_id,
            .groupon_team_id = e.groupon_team_id,
                .total_amount = e.total_amount,
                .pay_amount = e.pay_amount,
                .status = e.status,
                .address_json = try self.allocator.dupe(u8, e.address_json),
                .express_company = try self.allocator.dupe(u8, e.express_company),
                .express_no = try self.allocator.dupe(u8, e.express_no),
                .paid_at = e.paid_at,
                .created_at = e.created_at orelse 0,
            };
            n += 1;
        }
        return .{ .items = out, .total = paged.total };
    }

    pub fn listOrderProducts(self: *ShopStore, order_id: i64) ![]ShopOrderProductRow {
        var q = self.client.shop_order_product.Query();
        defer q.deinit();
        const preds = self.client.shop_order_product.predicates;
        _ = try q.Where(.{preds.order_idEQ(.{ .int = order_id })});
        var rows = try q.All();
        defer {
            for (rows.items) |*e| zent.codegen.deinitEntity(infos, ShopOrderProductInfo, e, self.allocator);
            rows.deinit();
        }
        var out = try self.allocator.alloc(ShopOrderProductRow, rows.items.len);
        errdefer self.allocator.free(out);
        var n: usize = 0;
        errdefer for (out[0..n]) |r| r.free(self.allocator);
        for (rows.items) |e| {
            out[n] = .{
                .id = e.id,
                .order_id = e.order_id,
                .product_id = e.product_id,
                .sku_id = e.sku_id,
                .name = try self.allocator.dupe(u8, e.name),
                .image = try self.allocator.dupe(u8, e.image),
                .spec_json = try self.allocator.dupe(u8, e.spec_json),
                .price = e.price,
                .quantity = e.quantity,
            };
            n += 1;
        }
        return out;
    }

    pub fn getOrderProduct(self: *ShopStore, id: i64) !?ShopOrderProductRow {
        const preds = self.client.shop_order_product.predicates;
        var entity = (try crud.first(self.client.shop_order_product, .{preds.idEQ(.{ .int = id })})) orelse return null;
        defer zent.codegen.deinitEntity(infos, ShopOrderProductInfo, &entity, self.allocator);
        return .{
            .id = entity.id,
            .order_id = entity.order_id,
            .product_id = entity.product_id,
            .sku_id = entity.sku_id,
            .name = try self.allocator.dupe(u8, entity.name),
            .image = try self.allocator.dupe(u8, entity.image),
            .spec_json = try self.allocator.dupe(u8, entity.spec_json),
            .price = entity.price,
            .quantity = entity.quantity,
        };
    }

    pub fn updateOrderStatus(self: *ShopStore, id: i64, status: i64, now: i64) !bool {
        const preds = self.client.shop_order.predicates;
        var upd = self.client.shop_order.Update();
        defer upd.deinit();
        _ = try upd.set("status", .{ .int = status });
        _ = try upd.setFieldValue("updated_at", now);
        if (status == 1) _ = try upd.setFieldValue("paid_at", now);
        _ = try upd.Where(.{preds.idEQ(.{ .int = id })});
        return (try upd.Save()) > 0;
    }

    pub fn updateOrderExpress(self: *ShopStore, id: i64, company: []const u8, no: []const u8, now: i64) !bool {
        const preds = self.client.shop_order.predicates;
        var upd = self.client.shop_order.Update();
        defer upd.deinit();
        _ = try upd.set("express_company", .{ .string = company });
        _ = try upd.set("express_no", .{ .string = no });
        _ = try upd.setFieldValue("updated_at", now);
        _ = try upd.Where(.{preds.idEQ(.{ .int = id })});
        return (try upd.Save()) > 0;
    }

    /// 过期待支付订单（status=0 且 created_at < before_ts）。
    pub fn listExpiredPending(self: *ShopStore, tenant_id: i64, account_id: i64, before_ts: i64) ![]ShopOrderRow {
        var q = self.client.shop_order.Query();
        defer q.deinit();
        const preds = self.client.shop_order.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        if (account_id > 0) _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.Where(.{preds.statusEQ(.{ .int = 0 })});
        _ = try q.Where(.{preds.created_atLTE(.{ .int = before_ts })});
        _ = q.Limit(50);
        var rows = try q.All();
        defer {
            for (rows.items) |*e| zent.codegen.deinitEntity(infos, ShopOrderInfo, e, self.allocator);
            rows.deinit();
        }
        var out = try self.allocator.alloc(ShopOrderRow, rows.items.len);
        errdefer self.allocator.free(out);
        var n: usize = 0;
        errdefer for (out[0..n]) |r| r.free(self.allocator);
        for (rows.items) |e| {
            out[n] = .{
                .id = e.id,
                .account_id = e.account_id,
                .order_no = try self.allocator.dupe(u8, e.order_no),
                .client_trade_no = try self.allocator.dupe(u8, e.client_trade_no),
                .openid = try self.allocator.dupe(u8, e.openid),
                .total_amount = e.total_amount,
                .pay_amount = e.pay_amount,
                .status = e.status,
                .address_json = try self.allocator.dupe(u8, e.address_json),
                .express_company = try self.allocator.dupe(u8, e.express_company),
                .express_no = try self.allocator.dupe(u8, e.express_no),
                .paid_at = e.paid_at,
                .pickup_type = try self.allocator.dupe(u8, e.pickup_type),
                .pickup_code = try self.allocator.dupe(u8, e.pickup_code),
                .store_id = e.store_id,
                .groupon_team_id = e.groupon_team_id,
                .created_at = e.created_at orelse 0,
            };
            n += 1;
        }
        return out;
    }

    /// 原子扣 SKU 库存（乐观锁）：UPDATE stock=stock-n WHERE id=? AND stock>=n。
    pub fn consumeSkuStock(self: *ShopStore, allocator: std.mem.Allocator, sku_id: i64, n: i64) !bool {
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
    pub fn addProductSales(self: *ShopStore, product_id: i64, n: i64) !void {
        const preds = self.client.shop_product.predicates;
        _ = crud.increment(self.client.shop_product, "sales", n, &.{preds.idEQ(.{ .int = product_id })}) catch {};
    }

    /// 库存返还（取消/退款）：sku.stock += n；销量回退：product.sales -= n。
    pub fn restoreSkuStock(self: *ShopStore, sku_id: i64, n: i64) !void {
        const sp = self.client.shop_product_sku.predicates;
        _ = crud.increment(self.client.shop_product_sku, "stock", n, &.{sp.idEQ(.{ .int = sku_id })}) catch {};
    }

    pub fn subtractProductSales(self: *ShopStore, product_id: i64, n: i64) !void {
        const preds = self.client.shop_product.predicates;
        _ = crud.increment(self.client.shop_product, "sales", -n, &.{preds.idEQ(.{ .int = product_id })}) catch {};
    }

    /// 按订单明细回滚库存与销量。
    pub fn restoreOrderStock(self: *ShopStore, order_id: i64) !void {
        const ops = try self.listOrderProducts(order_id);
        defer {
            for (ops) |op| op.free(self.allocator);
            if (ops.len > 0) self.allocator.free(ops);
        }
        for (ops) |op| {
            self.restoreSkuStock(op.sku_id, op.quantity) catch {};
            self.subtractProductSales(op.product_id, op.quantity) catch {};
        }
    }

    // ── 收藏 ──────────────────────────────────────────────

    pub fn favorite(self: *ShopStore, tenant_id: i64, account_id: i64, openid: []const u8, product_id: i64, now: i64) !void {
        if (self.isFavorite(tenant_id, openid, product_id) catch false) return;
        var row = try crud.create(self.client.shop_favorite, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .openid = openid,
            .product_id = product_id,
            .created_at = now,
            .updated_at = now,
        });
        defer zent.codegen.deinitEntity(infos, ShopFavoriteInfo, &row, self.allocator);
    }

    pub fn isFavorite(self: *ShopStore, tenant_id: i64, openid: []const u8, product_id: i64) !bool {
        var q = self.client.shop_favorite.Query();
        defer q.deinit();
        const preds = self.client.shop_favorite.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.openidEQ(.{ .string = openid })});
        _ = try q.Where(.{preds.product_idEQ(.{ .int = product_id })});
        _ = q.Limit(1);
        return (try q.Count()) > 0;
    }

    pub fn unfavorite(self: *ShopStore, id: i64) !bool {
        const preds = self.client.shop_favorite.predicates;
        var d = self.client.shop_favorite.Delete();
        defer d.deinit();
        _ = try d.Where(.{preds.idEQ(.{ .int = id })});
        return (try d.Exec()) > 0;
    }

    pub fn listFavorites(self: *ShopStore, tenant_id: i64, openid: []const u8) ![]ShopFavoriteRow {
        var q = self.client.shop_favorite.Query();
        defer q.deinit();
        const preds = self.client.shop_favorite.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.openidEQ(.{ .string = openid })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderDesc("created_at")});
        var rows = try q.All();
        defer {
            for (rows.items) |*e| zent.codegen.deinitEntity(infos, ShopFavoriteInfo, e, self.allocator);
            rows.deinit();
        }
        var out = try self.allocator.alloc(ShopFavoriteRow, rows.items.len);
        errdefer self.allocator.free(out);
        var n: usize = 0;
        errdefer for (out[0..n]) |r| r.free(self.allocator);
        for (rows.items) |e| {
            out[n] = .{
                .id = e.id,
                .account_id = e.account_id,
                .openid = try self.allocator.dupe(u8, e.openid),
                .product_id = e.product_id,
                .created_at = e.created_at orelse 0,
            };
            n += 1;
        }
        return out;
    }

    // ── 订单统计（管理端仪表盘） ─────────────────────────

    pub fn countOrdersByStatus(self: *ShopStore, tenant_id: i64, account_id: i64, status: i64) !i64 {
        var q = self.client.shop_order.Query();
        defer q.deinit();
        const preds = self.client.shop_order.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        if (account_id > 0) _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.Where(.{preds.statusEQ(.{ .int = status })});
        return q.Count();
    }

    // ── 储值卡套餐 ───────────────────────────────────────

    pub fn createBalancePlan(self: *ShopStore, tenant_id: i64, account_id: i64, name: []const u8, amount: i64, bonus: i64, now: i64) !i64 {
        var row = try crud.create(self.client.shop_balance_plan, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .name = name,
            .amount = amount,
            .bonus = bonus,
            .status = 1,
            .created_at = now,
            .updated_at = now,
        });
        defer zent.codegen.deinitEntity(infos, ShopBalancePlanInfo, &row, self.allocator);
        return row.id;
    }

    pub fn listBalancePlans(self: *ShopStore, tenant_id: i64, account_id: i64) ![]ShopBalancePlanRow {
        var q = self.client.shop_balance_plan.Query();
        defer q.deinit();
        const preds = self.client.shop_balance_plan.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        if (account_id > 0) _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.Where(.{preds.statusEQ(.{ .int = 1 })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderAsc("amount")});
        var rows = try q.All();
        defer {
            for (rows.items) |*e| zent.codegen.deinitEntity(infos, ShopBalancePlanInfo, e, self.allocator);
            rows.deinit();
        }
        var out = try self.allocator.alloc(ShopBalancePlanRow, rows.items.len);
        errdefer self.allocator.free(out);
        var n: usize = 0;
        errdefer for (out[0..n]) |r| r.free(self.allocator);
        for (rows.items) |e| {
            out[n] = .{
                .id = e.id,
                .account_id = e.account_id,
                .name = try self.allocator.dupe(u8, e.name),
                .amount = e.amount,
                .bonus = e.bonus,
                .status = e.status,
                .created_at = e.created_at orelse 0,
            };
            n += 1;
        }
        return out;
    }

    pub fn getBalancePlan(self: *ShopStore, id: i64) !?ShopBalancePlanRow {
        const preds = self.client.shop_balance_plan.predicates;
        var entity = (try crud.first(self.client.shop_balance_plan, .{preds.idEQ(.{ .int = id })})) orelse return null;
        defer zent.codegen.deinitEntity(infos, ShopBalancePlanInfo, &entity, self.allocator);
        return .{
            .id = entity.id,
            .account_id = entity.account_id,
            .name = try self.allocator.dupe(u8, entity.name),
            .amount = entity.amount,
            .bonus = entity.bonus,
            .status = entity.status,
            .created_at = entity.created_at orelse 0,
        };
    }

    pub fn deleteBalancePlan(self: *ShopStore, id: i64) !bool {
        const preds = self.client.shop_balance_plan.predicates;
        var d = self.client.shop_balance_plan.Delete();
        defer d.deinit();
        _ = try d.Where(.{preds.idEQ(.{ .int = id })});
        return (try d.Exec()) > 0;
    }

    // ── Webhook ───────────────────────────────────────────

    pub fn createWebhook(self: *ShopStore, tenant_id: i64, account_id: i64, url: []const u8, events: []const u8, now: i64) !i64 {
        var row = try crud.create(self.client.shop_webhook, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .url = url,
            .events = events,
            .status = 1,
            .created_at = now,
            .updated_at = now,
        });
        defer zent.codegen.deinitEntity(infos, ShopWebhookInfo, &row, self.allocator);
        return row.id;
    }

    pub fn listWebhooks(self: *ShopStore, tenant_id: i64, account_id: i64) ![]ShopWebhookRow {
        var q = self.client.shop_webhook.Query();
        defer q.deinit();
        const preds = self.client.shop_webhook.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        if (account_id > 0) _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.Where(.{preds.statusEQ(.{ .int = 1 })});
        var rows = try q.All();
        defer {
            for (rows.items) |*e| zent.codegen.deinitEntity(infos, ShopWebhookInfo, e, self.allocator);
            rows.deinit();
        }
        var out = try self.allocator.alloc(ShopWebhookRow, rows.items.len);
        errdefer self.allocator.free(out);
        var n: usize = 0;
        errdefer for (out[0..n]) |r| r.free(self.allocator);
        for (rows.items) |e| {
            out[n] = .{
                .id = e.id,
                .account_id = e.account_id,
                .url = try self.allocator.dupe(u8, e.url),
                .events = try self.allocator.dupe(u8, e.events),
                .status = e.status,
                .created_at = e.created_at orelse 0,
            };
            n += 1;
        }
        return out;
    }

    pub fn deleteWebhook(self: *ShopStore, id: i64) !bool {
        const preds = self.client.shop_webhook.predicates;
        var d = self.client.shop_webhook.Delete();
        defer d.deinit();
        _ = try d.Where(.{preds.idEQ(.{ .int = id })});
        return (try d.Exec()) > 0;
    }

    // ── 文章 ──────────────────────────────────────────────

    pub fn createArticle(self: *ShopStore, tenant_id: i64, account_id: i64, title: []const u8, content: []const u8, now: i64) !i64 {
        var row = try crud.create(self.client.shop_article, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .title = title,
            .content = content,
            .status = 1,
            .created_at = now,
            .updated_at = now,
        });
        defer zent.codegen.deinitEntity(infos, ShopArticleInfo, &row, self.allocator);
        return row.id;
    }

    pub fn getArticle(self: *ShopStore, id: i64) !?ShopArticleRow {
        const preds = self.client.shop_article.predicates;
        var entity = (try crud.first(self.client.shop_article, .{preds.idEQ(.{ .int = id })})) orelse return null;
        defer zent.codegen.deinitEntity(infos, ShopArticleInfo, &entity, self.allocator);
        return .{
            .id = entity.id,
            .account_id = entity.account_id,
            .title = try self.allocator.dupe(u8, entity.title),
            .content = try self.allocator.dupe(u8, entity.content),
            .status = entity.status,
            .created_at = entity.created_at orelse 0,
        };
    }

    pub fn listArticles(self: *ShopStore, page: usize, page_size: usize, tenant_id: i64, account_id: i64, on_sale: bool) !ArticleListResult {
        var q = self.client.shop_article.Query();
        defer q.deinit();
        const preds = self.client.shop_article.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        if (account_id > 0) _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        if (on_sale) _ = try q.Where(.{preds.statusEQ(.{ .int = 1 })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderDesc("created_at")});
        var paged = try q.paged(page, page_size);
        defer paged.deinit();
        var out = try self.allocator.alloc(ShopArticleRow, paged.items.items.len);
        var n: usize = 0;
        errdefer {
            for (out[0..n]) |r| r.free(self.allocator);
            self.allocator.free(out);
        }
        for (paged.items.items) |e| {
            out[n] = .{
                .id = e.id,
                .account_id = e.account_id,
                .title = try self.allocator.dupe(u8, e.title),
                .content = try self.allocator.dupe(u8, e.content),
                .status = e.status,
                .created_at = e.created_at orelse 0,
            };
            n += 1;
        }
        return .{ .items = out, .total = paged.total };
    }

    pub fn deleteArticle(self: *ShopStore, id: i64) !bool {
        const preds = self.client.shop_article.predicates;
        var d = self.client.shop_article.Delete();
        defer d.deinit();
        _ = try d.Where(.{preds.idEQ(.{ .int = id })});
        return (try d.Exec()) > 0;
    }

    // ── 邀请有礼 ─────────────────────────────────────────

    pub fn createInviteGift(self: *ShopStore, tenant_id: i64, account_id: i64, target_count: i64, reward_type: []const u8, reward_value: i64, now: i64) !i64 {
        var row = try crud.create(self.client.shop_invite_gift, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .target_count = target_count,
            .reward_type = reward_type,
            .reward_value = reward_value,
            .status = 1,
            .created_at = now,
            .updated_at = now,
        });
        defer zent.codegen.deinitEntity(infos, ShopInviteGiftInfo, &row, self.allocator);
        return row.id;
    }

    pub fn listInviteGifts(self: *ShopStore, tenant_id: i64, account_id: i64) ![]ShopInviteGiftRow {
        var q = self.client.shop_invite_gift.Query();
        defer q.deinit();
        const preds = self.client.shop_invite_gift.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        if (account_id > 0) _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.Where(.{preds.statusEQ(.{ .int = 1 })});
        var rows = try q.All();
        defer {
            for (rows.items) |*e| zent.codegen.deinitEntity(infos, ShopInviteGiftInfo, e, self.allocator);
            rows.deinit();
        }
        var out = try self.allocator.alloc(ShopInviteGiftRow, rows.items.len);
        errdefer self.allocator.free(out);
        var n: usize = 0;
        errdefer for (out[0..n]) |r| r.free(self.allocator);
        for (rows.items) |e| {
            out[n] = .{
                .id = e.id,
                .account_id = e.account_id,
                .target_count = e.target_count,
                .reward_type = try self.allocator.dupe(u8, e.reward_type),
                .reward_value = e.reward_value,
                .status = e.status,
                .created_at = e.created_at orelse 0,
            };
            n += 1;
        }
        return out;
    }

    pub fn deleteInviteGift(self: *ShopStore, id: i64) !bool {
        const preds = self.client.shop_invite_gift.predicates;
        var d = self.client.shop_invite_gift.Delete();
        defer d.deinit();
        _ = try d.Where(.{preds.idEQ(.{ .int = id })});
        return (try d.Exec()) > 0;
    }

    /// 绑定邀请关系（幂等：同 invitee 只记一次）。
    pub fn bindInvite(self: *ShopStore, tenant_id: i64, account_id: i64, inviter_openid: []const u8, invitee_openid: []const u8, now: i64) !bool {
        var q = self.client.shop_invite_record.Query();
        defer q.deinit();
        const preds = self.client.shop_invite_record.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.invitee_openidEQ(.{ .string = invitee_openid })});
        _ = q.Limit(1);
        if ((try q.Count()) > 0) return false; // 已绑定
        var row = try crud.create(self.client.shop_invite_record, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .inviter_openid = inviter_openid,
            .invitee_openid = invitee_openid,
            .created_at = now,
            .updated_at = now,
        });
        defer zent.codegen.deinitEntity(infos, ShopInviteRecordInfo, &row, self.allocator);
        return true;
    }

    /// 邀请人已邀请人数。
    pub fn countInvites(self: *ShopStore, tenant_id: i64, inviter_openid: []const u8) !i64 {
        var q = self.client.shop_invite_record.Query();
        defer q.deinit();
        const preds = self.client.shop_invite_record.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.inviter_openidEQ(.{ .string = inviter_openid })});
        return q.Count();
    }

    // ── 拼团 ──────────────────────────────────────────────

    pub fn createGroupon(self: *ShopStore, tenant_id: i64, account_id: i64, product_id: i64, group_price: i64, group_size: i64, start_at: i64, end_at: i64, now: i64) !i64 {
        var row = try crud.create(self.client.shop_groupon, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .product_id = product_id,
            .group_price = group_price,
            .group_size = group_size,
            .start_at = start_at,
            .end_at = end_at,
            .status = 1,
            .created_at = now,
            .updated_at = now,
        });
        defer zent.codegen.deinitEntity(infos, ShopGrouponInfo, &row, self.allocator);
        return row.id;
    }

    pub fn getGroupon(self: *ShopStore, id: i64) !?ShopGrouponRow {
        const preds = self.client.shop_groupon.predicates;
        var entity = (try crud.first(self.client.shop_groupon, .{preds.idEQ(.{ .int = id })})) orelse return null;
        defer zent.codegen.deinitEntity(infos, ShopGrouponInfo, &entity, self.allocator);
        return .{
            .id = entity.id,
            .account_id = entity.account_id,
            .product_id = entity.product_id,
            .group_price = entity.group_price,
            .group_size = entity.group_size,
            .start_at = entity.start_at,
            .end_at = entity.end_at,
            .status = entity.status,
            .created_at = entity.created_at orelse 0,
        };
    }

    pub fn listGroupons(self: *ShopStore, tenant_id: i64, account_id: i64) ![]ShopGrouponRow {
        var q = self.client.shop_groupon.Query();
        defer q.deinit();
        const preds = self.client.shop_groupon.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        if (account_id > 0) _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.Where(.{preds.statusEQ(.{ .int = 1 })});
        var rows = try q.All();
        defer {
            for (rows.items) |*e| zent.codegen.deinitEntity(infos, ShopGrouponInfo, e, self.allocator);
            rows.deinit();
        }
        var out = try self.allocator.alloc(ShopGrouponRow, rows.items.len);
        errdefer self.allocator.free(out);
        var n: usize = 0;
        for (rows.items) |e| {
            out[n] = .{
                .id = e.id,
                .account_id = e.account_id,
                .product_id = e.product_id,
                .group_price = e.group_price,
                .group_size = e.group_size,
                .start_at = e.start_at,
                .end_at = e.end_at,
                .status = e.status,
                .created_at = e.created_at orelse 0,
            };
            n += 1;
        }
        return out;
    }

    pub fn createTeam(self: *ShopStore, tenant_id: i64, account_id: i64, activity_id: i64, leader_openid: []const u8, now: i64) !i64 {
        var row = try crud.create(self.client.shop_groupon_team, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .activity_id = activity_id,
            .leader_openid = leader_openid,
            .current = 1,
            .status = 0,
            .created_at = now,
            .updated_at = now,
        });
        defer zent.codegen.deinitEntity(infos, ShopGrouponTeamInfo, &row, self.allocator);
        return row.id;
    }

    pub fn getTeam(self: *ShopStore, id: i64) !?ShopGrouponTeamRow {
        const preds = self.client.shop_groupon_team.predicates;
        var entity = (try crud.first(self.client.shop_groupon_team, .{preds.idEQ(.{ .int = id })})) orelse return null;
        defer zent.codegen.deinitEntity(infos, ShopGrouponTeamInfo, &entity, self.allocator);
        return .{
            .id = entity.id,
            .account_id = entity.account_id,
            .activity_id = entity.activity_id,
            .leader_openid = try self.allocator.dupe(u8, entity.leader_openid),
            .current = entity.current,
            .status = entity.status,
            .created_at = entity.created_at orelse 0,
        };
    }

    /// 参团计数 +1，返回是否成团（current >= group_size）。
    pub fn joinTeam(self: *ShopStore, allocator: std.mem.Allocator, team_id: i64, group_size: i64) !bool {
        const preds = self.client.shop_groupon_team.predicates;
        _ = crud.increment(self.client.shop_groupon_team, "current", 1, &.{
            preds.idEQ(.{ .int = team_id }),
        }) catch return false;
        const team_opt = self.getTeam(team_id) catch return false;
        const team = team_opt orelse return false;
        defer team.free(allocator);
        if (team.current >= group_size) {
            var upd = self.client.shop_groupon_team.Update();
            defer upd.deinit();
            _ = try upd.set("status", .{ .int = 1 });
            _ = try upd.Where(.{preds.idEQ(.{ .int = team_id })});
            _ = try upd.Save();
            return true;
        }
        return false;
    }

    /// 按团查订单（成团后批量标记支付）。
    pub fn listOrdersByTeam(self: *ShopStore, team_id: i64) ![]ShopOrderRow {
        var q = self.client.shop_order.Query();
        defer q.deinit();
        const preds = self.client.shop_order.predicates;
        _ = try q.Where(.{preds.groupon_team_idEQ(.{ .int = team_id })});
        var rows = try q.All();
        defer {
            for (rows.items) |*e| zent.codegen.deinitEntity(infos, ShopOrderInfo, e, self.allocator);
            rows.deinit();
        }
        var out = try self.allocator.alloc(ShopOrderRow, rows.items.len);
        errdefer self.allocator.free(out);
        var n: usize = 0;
        errdefer for (out[0..n]) |r| r.free(self.allocator);
        for (rows.items) |e| {
            out[n] = .{
                .id = e.id,
                .account_id = e.account_id,
                .order_no = try self.allocator.dupe(u8, e.order_no),
                .client_trade_no = try self.allocator.dupe(u8, e.client_trade_no),
                .openid = try self.allocator.dupe(u8, e.openid),
                .total_amount = e.total_amount,
                .pay_amount = e.pay_amount,
                .status = e.status,
                .address_json = try self.allocator.dupe(u8, e.address_json),
                .express_company = try self.allocator.dupe(u8, e.express_company),
                .express_no = try self.allocator.dupe(u8, e.express_no),
                .paid_at = e.paid_at,
                .pickup_type = try self.allocator.dupe(u8, e.pickup_type),
                .pickup_code = try self.allocator.dupe(u8, e.pickup_code),
                .store_id = e.store_id,
                .groupon_team_id = e.groupon_team_id,
                .created_at = e.created_at orelse 0,
            };
            n += 1;
        }
        return out;
    }

    // ── 门店 ──────────────────────────────────────────────

    pub fn createOutlet(self: *ShopStore, tenant_id: i64, account_id: i64, name: []const u8, address: []const u8, mobile: []const u8, now: i64) !i64 {
        var row = try crud.create(self.client.shop_outlet, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .name = name,
            .address = address,
            .mobile = mobile,
            .status = 1,
            .created_at = now,
            .updated_at = now,
        });
        defer zent.codegen.deinitEntity(infos, ShopOutletInfo, &row, self.allocator);
        return row.id;
    }

    pub fn listOutlets(self: *ShopStore, tenant_id: i64, account_id: i64) ![]ShopOutletRow {
        var q = self.client.shop_outlet.Query();
        defer q.deinit();
        const preds = self.client.shop_outlet.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        if (account_id > 0) _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        var rows = try q.All();
        defer {
            for (rows.items) |*e| zent.codegen.deinitEntity(infos, ShopOutletInfo, e, self.allocator);
            rows.deinit();
        }
        var out = try self.allocator.alloc(ShopOutletRow, rows.items.len);
        errdefer self.allocator.free(out);
        var n: usize = 0;
        errdefer for (out[0..n]) |r| r.free(self.allocator);
        for (rows.items) |e| {
            out[n] = .{
                .id = e.id,
                .account_id = e.account_id,
                .name = try self.allocator.dupe(u8, e.name),
                .address = try self.allocator.dupe(u8, e.address),
                .mobile = try self.allocator.dupe(u8, e.mobile),
                .status = e.status,
                .created_at = e.created_at orelse 0,
            };
            n += 1;
        }
        return out;
    }

    pub fn deleteOutlet(self: *ShopStore, id: i64) !bool {
        const preds = self.client.shop_outlet.predicates;
        var d = self.client.shop_outlet.Delete();
        defer d.deinit();
        _ = try d.Where(.{preds.idEQ(.{ .int = id })});
        return (try d.Exec()) > 0;
    }

    pub fn sumPaidAmount(self: *ShopStore, tenant_id: i64, account_id: i64) !i64 {
        var q = self.client.shop_order.Query();
        defer q.deinit();
        const preds = self.client.shop_order.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        if (account_id > 0) _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.Where(.{preds.statusGT(.{ .int = 0 })});
        // 求和用 SQL：直接扫行累加（量小场景足够；跳过已取消 4）。
        var rows = try q.All();
        defer {
            for (rows.items) |*e| zent.codegen.deinitEntity(infos, ShopOrderInfo, e, self.allocator);
            rows.deinit();
        }
        var sum: i64 = 0;
        for (rows.items) |e| {
            if (e.status != 4) sum += e.pay_amount;
        }
        return sum;
    }

    // ── 退款 ──────────────────────────────────────────────

    pub fn createRefund(self: *ShopStore, tenant_id: i64, account_id: i64, order_id: i64, openid: []const u8, reason: []const u8, amount: i64, now: i64) !i64 {
        var row = try crud.create(self.client.shop_refund, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .order_id = order_id,
            .openid = openid,
            .reason = reason,
            .amount = amount,
            .status = 0,
            .created_at = now,
            .updated_at = now,
        });
        defer zent.codegen.deinitEntity(infos, ShopRefundInfo, &row, self.allocator);
        return row.id;
    }

    pub fn getRefundByOrder(self: *ShopStore, tenant_id: i64, order_id: i64) !?ShopRefundRow {
        var q = self.client.shop_refund.Query();
        defer q.deinit();
        const preds = self.client.shop_refund.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.order_idEQ(.{ .int = order_id })});
        const entity_opt = try q.First();
        var entity = entity_opt orelse return null;
        defer zent.codegen.deinitEntity(infos, ShopRefundInfo, &entity, self.allocator);
        return .{
            .id = entity.id,
            .account_id = entity.account_id,
            .order_id = entity.order_id,
            .openid = try self.allocator.dupe(u8, entity.openid),
            .reason = try self.allocator.dupe(u8, entity.reason),
            .amount = entity.amount,
            .status = entity.status,
            .created_at = entity.created_at orelse 0,
        };
    }

    pub fn listRefunds(self: *ShopStore, page: usize, page_size: usize, tenant_id: i64, account_id: i64, status: i64) !RefundListResult {
        var q = self.client.shop_refund.Query();
        defer q.deinit();
        const preds = self.client.shop_refund.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        if (account_id > 0) _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        if (status >= 0) _ = try q.Where(.{preds.statusEQ(.{ .int = status })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderDesc("created_at")});
        var paged = try q.paged(page, page_size);
        defer paged.deinit();
        var out = try self.allocator.alloc(ShopRefundRow, paged.items.items.len);
        var n: usize = 0;
        errdefer {
            for (out[0..n]) |r| r.free(self.allocator);
            self.allocator.free(out);
        }
        for (paged.items.items) |e| {
            out[n] = .{
                .id = e.id,
                .account_id = e.account_id,
                .order_id = e.order_id,
                .openid = try self.allocator.dupe(u8, e.openid),
                .reason = try self.allocator.dupe(u8, e.reason),
                .amount = e.amount,
                .status = e.status,
                .created_at = e.created_at orelse 0,
            };
            n += 1;
        }
        return .{ .items = out, .total = paged.total };
    }

    pub fn auditRefund(self: *ShopStore, id: i64, status: i64, now: i64) !bool {
        const preds = self.client.shop_refund.predicates;
        var upd = self.client.shop_refund.Update();
        defer upd.deinit();
        _ = try upd.set("status", .{ .int = status });
        _ = try upd.setFieldValue("updated_at", now);
        _ = try upd.Where(.{preds.idEQ(.{ .int = id })});
        return (try upd.Save()) > 0;
    }

    // ── 评价 ──────────────────────────────────────────────

    pub fn createComment(self: *ShopStore, tenant_id: i64, account_id: i64, c: anytype, now: i64) !i64 {
        var row = try crud.create(self.client.shop_comment, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .order_product_id = c.order_product_id,
            .product_id = c.product_id,
            .openid = c.openid,
            .star = c.star,
            .content = c.content,
            .created_at = now,
            .updated_at = now,
        });
        defer zent.codegen.deinitEntity(infos, ShopCommentInfo, &row, self.allocator);
        return row.id;
    }

    pub fn listCommentsByProduct(self: *ShopStore, product_id: i64) ![]ShopCommentRow {
        var q = self.client.shop_comment.Query();
        defer q.deinit();
        const preds = self.client.shop_comment.predicates;
        _ = try q.Where(.{preds.product_idEQ(.{ .int = product_id })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderDesc("created_at")});
        var rows = try q.All();
        defer {
            for (rows.items) |*e| zent.codegen.deinitEntity(infos, ShopCommentInfo, e, self.allocator);
            rows.deinit();
        }
        var out = try self.allocator.alloc(ShopCommentRow, rows.items.len);
        errdefer self.allocator.free(out);
        var n: usize = 0;
        errdefer for (out[0..n]) |r| r.free(self.allocator);
        for (rows.items) |e| {
            out[n] = .{
                .id = e.id,
                .account_id = e.account_id,
                .order_product_id = e.order_product_id,
                .product_id = e.product_id,
                .openid = try self.allocator.dupe(u8, e.openid),
                .star = e.star,
                .content = try self.allocator.dupe(u8, e.content),
                .created_at = e.created_at orelse 0,
            };
            n += 1;
        }
        return out;
    }
};


