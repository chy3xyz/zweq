//! 交易域存储：购物车 / 地址 / 订单及明细 / 收藏 / 退款 / 评论，含订单取消的库存回滚编排。拆分自原 ShopStore。
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

/// TradeStore 持有独立的 allocator/client 拷贝（Client 内部 driver 为共享句柄，
/// 多份值拷贝指向同一连接与 PreparedCache，与拆分前行为一致）。
pub const TradeStore = struct {
    allocator: std.mem.Allocator,
    client: Client,

    pub fn upsertCart(self: *TradeStore, tenant_id: i64, account_id: i64, openid: []const u8, product_id: i64, sku_id: i64, quantity: i64, now: i64) !i64 {
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

    pub fn listCarts(self: *TradeStore, tenant_id: i64, openid: []const u8) ![]ShopCartRow {
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

    /// 数量更新带归属条件（tenant_id + openid），affected==0 即越权/不存在。
    pub fn updateCartQuantity(self: *TradeStore, tenant_id: i64, openid: []const u8, id: i64, quantity: i64) !bool {
        const preds = self.client.shop_cart.predicates;
        var upd = self.client.shop_cart.Update();
        defer upd.deinit();
        _ = try upd.set("quantity", .{ .int = quantity });
        _ = try upd.Where(.{ preds.idEQ(.{ .int = id }), preds.tenant_idEQ(.{ .int = tenant_id }), preds.openidEQ(.{ .string = openid }) });
        return (try upd.Save()) > 0;
    }

    /// 删除带归属条件（tenant_id + openid），affected==0 即越权/不存在。
    pub fn deleteCart(self: *TradeStore, tenant_id: i64, openid: []const u8, id: i64) !bool {
        const preds = self.client.shop_cart.predicates;
        var d = self.client.shop_cart.Delete();
        defer d.deinit();
        _ = try d.Where(.{ preds.idEQ(.{ .int = id }), preds.tenant_idEQ(.{ .int = tenant_id }), preds.openidEQ(.{ .string = openid }) });
        return (try d.Exec()) > 0;
    }

    // ── 地址 ──────────────────────────────────────────────────

    pub fn createAddress(self: *TradeStore, tenant_id: i64, account_id: i64, a: anytype, now: i64) !i64 {
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

    fn clearDefaultAddress(self: *TradeStore, tenant_id: i64, openid: []const u8, except_id: i64) !void {
        const preds = self.client.shop_address.predicates;
        var upd = self.client.shop_address.Update();
        defer upd.deinit();
        _ = try upd.set("is_default", .{ .int = 0 });
        _ = try upd.Where(.{ preds.tenant_idEQ(.{ .int = tenant_id }), preds.openidEQ(.{ .string = openid }), preds.is_defaultEQ(.{ .int = 1 }), preds.idNE(.{ .int = except_id }) });
        _ = try upd.Save();
    }

    pub fn listAddresses(self: *TradeStore, tenant_id: i64, openid: []const u8) ![]ShopAddressRow {
        var q = self.client.shop_address.Query();
        defer q.deinit();
        const preds = self.client.shop_address.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.openidEQ(.{ .string = openid })});
        _ = try q.OrderBy(&[_]zent.sql.Order{ zent.sql.OrderDesc("is_default"), zent.sql.OrderDesc("created_at") });
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

    /// 按 id 读地址，带 tenant_id 归属条件：防跨租户把他人收货地址
    /// （PII）快照写进本租户订单。
    pub fn getAddress(self: *TradeStore, tenant_id: i64, id: i64) !?ShopAddressRow {
        const preds = self.client.shop_address.predicates;
        var entity = (try crud.first(self.client.shop_address, .{ preds.idEQ(.{ .int = id }), preds.tenant_idEQ(.{ .int = tenant_id }) })) orelse return null;
        defer zent.codegen.deinitEntity(infos, ShopAddressInfo, &entity, self.allocator);
        const openid_dup = try self.allocator.dupe(u8, entity.openid);
        const name = try self.allocator.dupe(u8, entity.name);
        const mobile = try self.allocator.dupe(u8, entity.mobile);
        const region = try self.allocator.dupe(u8, entity.region);
        const detail = try self.allocator.dupe(u8, entity.detail);
        return .{ .id = entity.id, .account_id = entity.account_id, .openid = openid_dup, .name = name, .mobile = mobile, .region = region, .detail = detail, .is_default = entity.is_default, .created_at = entity.created_at orelse 0 };
    }

    /// 删除带归属条件（tenant_id + openid），affected==0 即越权/不存在。
    pub fn deleteAddress(self: *TradeStore, tenant_id: i64, openid: []const u8, id: i64) !bool {
        const preds = self.client.shop_address.predicates;
        var d = self.client.shop_address.Delete();
        defer d.deinit();
        _ = try d.Where(.{ preds.idEQ(.{ .int = id }), preds.tenant_idEQ(.{ .int = tenant_id }), preds.openidEQ(.{ .string = openid }) });
        return (try d.Exec()) > 0;
    }

    pub fn setDefaultAddress(self: *TradeStore, tenant_id: i64, openid: []const u8, id: i64, now: i64) !void {
        const row_opt = try self.getAddress(tenant_id, id);
        const row = row_opt orelse return error.AddressNotFound;
        defer row.free(self.allocator);
        if (!std.mem.eql(u8, row.openid, openid)) return error.InvalidInput;

        const preds = self.client.shop_address.predicates;
        var upd = self.client.shop_address.Update();
        defer upd.deinit();
        _ = try upd.set("is_default", .{ .int = 1 });
        _ = try upd.set("updated_at", .{ .int = now });
        _ = try upd.Where(.{ preds.idEQ(.{ .int = id }) });
        _ = try upd.Save();
        try self.clearDefaultAddress(tenant_id, openid, id);
    }

    pub fn updateAddress(self: *TradeStore, tenant_id: i64, openid: []const u8, id: i64, a: anytype, now: i64) !void {
        const row_opt = try self.getAddress(tenant_id, id);
        const row = row_opt orelse return error.AddressNotFound;
        defer row.free(self.allocator);
        if (!std.mem.eql(u8, row.openid, openid)) return error.InvalidInput;

        const preds = self.client.shop_address.predicates;
        var upd = self.client.shop_address.Update();
        defer upd.deinit();
        _ = try upd.set("name", .{ .string = a.name });
        _ = try upd.set("mobile", .{ .string = a.mobile });
        _ = try upd.set("region", .{ .string = a.region });
        _ = try upd.set("detail", .{ .string = a.detail });
        _ = try upd.set("updated_at", .{ .int = now });
        if (a.is_default == 1) {
            _ = try upd.set("is_default", .{ .int = 1 });
        }
        _ = try upd.Where(.{ preds.idEQ(.{ .int = id }) });
        _ = try upd.Save();
        if (a.is_default == 1) {
            try self.clearDefaultAddress(tenant_id, openid, id);
        }
    }

    // ── 订单 ──────────────────────────────────────────────────

    pub fn createOrder(self: *TradeStore, tenant_id: i64, account_id: i64, order_no: []const u8, client_trade_no: []const u8, openid: []const u8, total_amount: i64, pay_amount: i64, address_json: []const u8, pickup_type: []const u8, pickup_code: []const u8, store_id: i64, groupon_team_id: i64, now: i64) !i64 {
        const total_amount_str = try std.fmt.allocPrint(self.allocator, "{d}", .{total_amount});
        defer self.allocator.free(total_amount_str);
        const pay_amount_str = try std.fmt.allocPrint(self.allocator, "{d}", .{pay_amount});
        defer self.allocator.free(pay_amount_str);
        var row = try crud.create(self.client.shop_order, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .order_no = order_no,
            .client_trade_no = client_trade_no,
            .openid = openid,
            .total_amount = total_amount_str,
            .pay_amount = pay_amount_str,
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

    pub fn createOrderProduct(self: *TradeStore, tenant_id: i64, account_id: i64, order_id: i64, o: anytype, now: i64) !i64 {
        const price = try std.fmt.allocPrint(self.allocator, "{d}", .{o.price});
        defer self.allocator.free(price);
        var row = try crud.create(self.client.shop_order_product, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .order_id = order_id,
            .product_id = o.product_id,
            .sku_id = o.sku_id,
            .name = o.name,
            .image = o.image,
            .spec_json = o.spec_json,
            .price = price,
            .quantity = o.quantity,
            .created_at = now,
            .updated_at = now,
        });
        defer zent.codegen.deinitEntity(infos, ShopOrderProductInfo, &row, self.allocator);
        return row.id;
    }

    pub fn getByClientTradeNo(self: *TradeStore, tenant_id: i64, client_trade_no: []const u8) !?ShopOrderRow {
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
            .total_amount = try self.allocator.dupe(u8, entity.total_amount),
            .pay_amount = try self.allocator.dupe(u8, entity.pay_amount),
            .status = entity.status,
            .address_json = try self.allocator.dupe(u8, entity.address_json),
            .express_company = try self.allocator.dupe(u8, entity.express_company),
            .express_no = try self.allocator.dupe(u8, entity.express_no),
            .paid_at = entity.paid_at,
            .created_at = entity.created_at orelse 0,
        };
    }

    pub fn getOrder(self: *TradeStore, id: i64) !?ShopOrderRow {
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
            .total_amount = try self.allocator.dupe(u8, entity.total_amount),
            .pay_amount = try self.allocator.dupe(u8, entity.pay_amount),
            .status = entity.status,
            .address_json = try self.allocator.dupe(u8, entity.address_json),
            .express_company = try self.allocator.dupe(u8, entity.express_company),
            .express_no = try self.allocator.dupe(u8, entity.express_no),
            .paid_at = entity.paid_at,
            .created_at = entity.created_at orelse 0,
        };
    }

    pub fn listOrders(self: *TradeStore, page: usize, page_size: usize, tenant_id: i64, account_id: i64, openid: []const u8, status: i64, pickup_type: []const u8) !OrderListResult {
        var q = self.client.shop_order.Query();
        defer q.deinit();
        const preds = self.client.shop_order.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        if (account_id > 0) _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        if (openid.len > 0) _ = try q.Where(.{preds.openidEQ(.{ .string = openid })});
        if (status >= 0) _ = try q.Where(.{preds.statusEQ(.{ .int = status })});
        if (pickup_type.len > 0) _ = try q.Where(.{preds.pickup_typeEQ(.{ .string = pickup_type })});
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
                .total_amount = try self.allocator.dupe(u8, e.total_amount),
                .pay_amount = try self.allocator.dupe(u8, e.pay_amount),
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

    /// 事务感知读取：传入 tx.client 时读取发生在同一事务内。
    pub fn listOrderProductsOn(self: *TradeStore, client: anytype, order_id: i64) ![]ShopOrderProductRow {
        var q = client.shop_order_product.Query();
        defer q.deinit();
        const preds = client.shop_order_product.predicates;
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
                .price = try self.allocator.dupe(u8, e.price),
                .quantity = e.quantity,
                .created_at = e.created_at orelse 0,
            };
            n += 1;
        }
        return out;
    }

    pub fn listOrderProducts(self: *TradeStore, order_id: i64) ![]ShopOrderProductRow {
        return self.listOrderProductsOn(self.client, order_id);
    }

    pub fn getOrderProduct(self: *TradeStore, id: i64) !?ShopOrderProductRow {
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
            .price = try self.allocator.dupe(u8, entity.price),
            .quantity = entity.quantity,
            .created_at = entity.created_at orelse 0,
        };
    }

    /// 事务感知状态更新：随下单/退款事务提交或回滚（事务内读写必须走 tx.client）。
    pub fn updateOrderStatusOn(_: *TradeStore, client: anytype, id: i64, status: i64, now: i64) !bool {
        const preds = client.shop_order.predicates;
        var upd = client.shop_order.Update();
        defer upd.deinit();
        _ = try upd.set("status", .{ .int = status });
        _ = try upd.setFieldValue("updated_at", now);
        if (status == 1) _ = try upd.setFieldValue("paid_at", now);
        _ = try upd.Where(.{preds.idEQ(.{ .int = id })});
        return (try upd.Save()) > 0;
    }

    pub fn updateOrderStatus(self: *TradeStore, id: i64, status: i64, now: i64) !bool {
        return self.updateOrderStatusOn(self.client, id, status, now);
    }

    /// 原子支付翻转：仅 待支付(0)→已支付(1) 且本租户 才命中一次。
    /// 重复/并发支付回调 affected=0 → 调用方读回状态做幂等区分，绝不重复发奖。
    pub fn markPaidOn(self: *TradeStore, tenant_id: i64, order_id: i64, now: i64) !bool {
        const preds = self.client.shop_order.predicates;
        var upd = self.client.shop_order.Update();
        defer upd.deinit();
        _ = try upd.set("status", .{ .int = 1 });
        _ = try upd.setFieldValue("updated_at", now);
        _ = try upd.setFieldValue("paid_at", now);
        _ = try upd.Where(.{ preds.idEQ(.{ .int = order_id }), preds.tenant_idEQ(.{ .int = tenant_id }), preds.statusEQ(.{ .int = 0 }) });
        return (try upd.Save()) > 0;
    }

    /// 原子取消：仅 待支付(0) 且 归属（tenant_id + openid）匹配 才置已取消（4）。
    /// 并发/重复取消只有一个调用方 affected=1 → 库存回滚恰好执行一次。
    pub fn cancelOrderOn(self: *TradeStore, tenant_id: i64, openid: []const u8, order_id: i64, now: i64) !bool {
        const preds = self.client.shop_order.predicates;
        var upd = self.client.shop_order.Update();
        defer upd.deinit();
        _ = try upd.set("status", .{ .int = 4 });
        _ = try upd.setFieldValue("updated_at", now);
        _ = try upd.Where(.{ preds.idEQ(.{ .int = order_id }), preds.tenant_idEQ(.{ .int = tenant_id }), preds.openidEQ(.{ .string = openid }), preds.statusEQ(.{ .int = 0 }) });
        return (try upd.Save()) > 0;
    }

    /// 原子自提核销：本租户 + 已支付（1）+ 自提 + 核销码一致 才置已完成（3）。
    /// 条件更新兜底并发重复核销；6 位数字码的暴力破解风险见 service.pickupOrder TODO。
    pub fn pickupOrderOn(self: *TradeStore, tenant_id: i64, order_id: i64, code: []const u8, now: i64) !bool {
        const preds = self.client.shop_order.predicates;
        var upd = self.client.shop_order.Update();
        defer upd.deinit();
        _ = try upd.set("status", .{ .int = 3 });
        _ = try upd.setFieldValue("updated_at", now);
        _ = try upd.Where(.{ preds.idEQ(.{ .int = order_id }), preds.tenant_idEQ(.{ .int = tenant_id }), preds.statusEQ(.{ .int = 1 }), preds.pickup_typeEQ(.{ .string = "self" }), preds.pickup_codeEQ(.{ .string = code }) });
        return (try upd.Save()) > 0;
    }

    pub fn updateOrderExpress(self: *TradeStore, id: i64, company: []const u8, no: []const u8, now: i64) !bool {
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
    pub fn listExpiredPending(self: *TradeStore, tenant_id: i64, account_id: i64, before_ts: i64) ![]ShopOrderRow {
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
                .total_amount = try self.allocator.dupe(u8, e.total_amount),
                .pay_amount = try self.allocator.dupe(u8, e.pay_amount),
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

    /// 事务感知库存回滚：按订单明细返还 SKU 库存、扣减销量（必须走 tx.client，
    /// 与退款审核/订单状态同事务提交，失败整体回滚）。
    pub fn restoreOrderStockOn(self: *TradeStore, client: anytype, order_id: i64) !void {
        const ops = try self.listOrderProductsOn(client, order_id);
        defer {
            for (ops) |op| op.free(self.allocator);
            if (ops.len > 0) self.allocator.free(ops);
        }
        for (ops) |op| {
            self.restoreSkuStockOn(client, op.sku_id, op.quantity) catch {};
            self.subtractProductSalesOn(client, op.product_id, op.quantity) catch {};
        }
    }

    /// 按订单明细回滚库存与销量。
    pub fn restoreOrderStock(self: *TradeStore, order_id: i64) !void {
        return self.restoreOrderStockOn(self.client, order_id);
    }

    // ── 收藏 ──────────────────────────────────────────────

    pub fn favorite(self: *TradeStore, tenant_id: i64, account_id: i64, openid: []const u8, product_id: i64, now: i64) !void {
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

    pub fn isFavorite(self: *TradeStore, tenant_id: i64, openid: []const u8, product_id: i64) !bool {
        var q = self.client.shop_favorite.Query();
        defer q.deinit();
        const preds = self.client.shop_favorite.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.openidEQ(.{ .string = openid })});
        _ = try q.Where(.{preds.product_idEQ(.{ .int = product_id })});
        _ = q.Limit(1);
        return (try q.Count()) > 0;
    }

    pub fn unfavorite(self: *TradeStore, id: i64) !bool {
        const preds = self.client.shop_favorite.predicates;
        var d = self.client.shop_favorite.Delete();
        defer d.deinit();
        _ = try d.Where(.{preds.idEQ(.{ .int = id })});
        return (try d.Exec()) > 0;
    }

    pub fn listFavorites(self: *TradeStore, tenant_id: i64, openid: []const u8) ![]ShopFavoriteRow {
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

    pub fn countOrdersByStatus(self: *TradeStore, tenant_id: i64, account_id: i64, status: i64) !i64 {
        var q = self.client.shop_order.Query();
        defer q.deinit();
        const preds = self.client.shop_order.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        if (account_id > 0) _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.Where(.{preds.statusEQ(.{ .int = status })});
        return q.Count();
    }

    pub fn countOrdersByStatusOpenid(self: *TradeStore, tenant_id: i64, account_id: i64, openid: []const u8, status: i64) !i64 {
        var q = self.client.shop_order.Query();
        defer q.deinit();
        const preds = self.client.shop_order.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        if (account_id > 0) _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        if (openid.len > 0) _ = try q.Where(.{preds.openidEQ(.{ .string = openid })});
        _ = try q.Where(.{preds.statusEQ(.{ .int = status })});
        return q.Count();
    }

    // ── 储值卡套餐 ───────────────────────────────────────

    pub fn sumPaidAmount(self: *TradeStore, tenant_id: i64, account_id: i64) !i64 {
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
            if (e.status != 4) sum += std.fmt.parseInt(i64, e.pay_amount, 10) catch 0;
        }
        return sum;
    }

    // ── 退款 ──────────────────────────────────────────────

    pub fn createRefund(self: *TradeStore, tenant_id: i64, account_id: i64, order_id: i64, openid: []const u8, reason: []const u8, amount: i64, now: i64) !i64 {
        const amount_str = try std.fmt.allocPrint(self.allocator, "{d}", .{amount});
        defer self.allocator.free(amount_str);
        var row = try crud.create(self.client.shop_refund, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .order_id = order_id,
            .openid = openid,
            .reason = reason,
            .amount = amount_str,
            .status = 0,
            .created_at = now,
            .updated_at = now,
        });
        defer zent.codegen.deinitEntity(infos, ShopRefundInfo, &row, self.allocator);
        return row.id;
    }

    pub fn getRefundByOrder(self: *TradeStore, tenant_id: i64, order_id: i64) !?ShopRefundRow {
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
            .amount = try self.allocator.dupe(u8, entity.amount),
            .status = entity.status,
            .created_at = entity.created_at orelse 0,
        };
    }

    pub fn listRefunds(self: *TradeStore, page: usize, page_size: usize, tenant_id: i64, account_id: i64, status: i64) !RefundListResult {
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
                .amount = try self.allocator.dupe(u8, e.amount),
                .status = e.status,
                .created_at = e.created_at orelse 0,
            };
            n += 1;
        }
        return .{ .items = out, .total = paged.total };
    }

    pub fn listRefundsByOpenid(self: *TradeStore, page: usize, page_size: usize, tenant_id: i64, account_id: i64, openid: []const u8) !RefundListResult {
        var q = self.client.shop_refund.Query();
        defer q.deinit();
        const preds = self.client.shop_refund.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        if (account_id > 0) _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.Where(.{preds.openidEQ(.{ .string = openid })});
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
                .amount = try self.allocator.dupe(u8, e.amount),
                .status = e.status,
                .created_at = e.created_at orelse 0,
            };
            n += 1;
        }
        return .{ .items = out, .total = paged.total };
    }

    /// 事务感知退款审核：仅 待审核(0)→终态(1/2) 命中一次；
    /// affected=0 即重复审核/并发审核 → 调用方幂等处理，绝不重复回滚库存。
    pub fn auditRefundOn(_: *TradeStore, client: anytype, id: i64, status: i64, now: i64) !bool {
        const preds = client.shop_refund.predicates;
        var upd = client.shop_refund.Update();
        defer upd.deinit();
        _ = try upd.set("status", .{ .int = status });
        _ = try upd.setFieldValue("updated_at", now);
        _ = try upd.Where(.{ preds.idEQ(.{ .int = id }), preds.statusEQ(.{ .int = 0 }) });
        return (try upd.Save()) > 0;
    }

    pub fn auditRefund(self: *TradeStore, id: i64, status: i64, now: i64) !bool {
        return self.auditRefundOn(self.client, id, status, now);
    }

    /// 事务感知读取：按 id 读退款单（审核幂等判定用）。
    pub fn getRefundByIdOn(self: *TradeStore, client: anytype, id: i64) !?ShopRefundRow {
        const preds = client.shop_refund.predicates;
        var entity = (try crud.first(client.shop_refund, .{preds.idEQ(.{ .int = id })})) orelse return null;
        defer zent.codegen.deinitEntity(infos, ShopRefundInfo, &entity, self.allocator);
        return .{
            .id = entity.id,
            .account_id = entity.account_id,
            .order_id = entity.order_id,
            .openid = try self.allocator.dupe(u8, entity.openid),
            .reason = try self.allocator.dupe(u8, entity.reason),
            .amount = try self.allocator.dupe(u8, entity.amount),
            .status = entity.status,
            .created_at = entity.created_at orelse 0,
        };
    }

    // ── 评价 ──────────────────────────────────────────────

    pub fn getCommentByOrderProduct(self: *TradeStore, order_product_id: i64) !?ShopCommentRow {
        var q = self.client.shop_comment.Query();
        defer q.deinit();
        const preds = self.client.shop_comment.predicates;
        _ = try q.Where(.{preds.order_product_idEQ(.{ .int = order_product_id })});
        _ = q.Limit(1);
        var rows = try q.All();
        defer {
            for (rows.items) |*e| zent.codegen.deinitEntity(infos, ShopCommentInfo, e, self.allocator);
            rows.deinit();
        }
        if (rows.items.len == 0) return null;
        const e = rows.items[0];
        return .{
            .id = e.id,
            .account_id = e.account_id,
            .order_product_id = e.order_product_id,
            .product_id = e.product_id,
            .openid = try self.allocator.dupe(u8, e.openid),
            .star = e.star,
            .content = try self.allocator.dupe(u8, e.content),
            .created_at = e.created_at orelse 0,
        };
    }

    pub fn createComment(self: *TradeStore, tenant_id: i64, account_id: i64, c: anytype, now: i64) !i64 {
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

    pub fn listCommentsByProduct(self: *TradeStore, product_id: i64) ![]ShopCommentRow {
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

    // ── 商品域库存原语的交易侧内联副本 ────────────────────
    // 取消/失败链路需直接增补 SKU 库存、扣减销量；实现与 CatalogStore 同款
    // crud.increment 单行语句。表归属商品域，但为避免子域之间互相持引用而内联。
    pub fn restoreSkuStockOn(_: *TradeStore, client: anytype, sku_id: i64, n: i64) !void {
        const sp = client.shop_product_sku.predicates;
        _ = crud.increment(client.shop_product_sku, "stock", n, &.{sp.idEQ(.{ .int = sku_id })}) catch {};
    }

    pub fn restoreSkuStock(self: *TradeStore, sku_id: i64, n: i64) !void {
        return self.restoreSkuStockOn(self.client, sku_id, n);
    }

    pub fn subtractProductSalesOn(_: *TradeStore, client: anytype, product_id: i64, n: i64) !void {
        const p = client.shop_product.predicates;
        _ = crud.increment(client.shop_product, "sales", -n, &.{p.idEQ(.{ .int = product_id })}) catch {};
    }

    pub fn subtractProductSales(self: *TradeStore, product_id: i64, n: i64) !void {
        return self.subtractProductSalesOn(self.client, product_id, n);
    }
};
