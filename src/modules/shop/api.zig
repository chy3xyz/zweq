//! Shop API — 商品域（C 端公开浏览 + 管理端 CRUD）。

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const mw = @import("../../middleware/auth.zig");
const mw_rate = @import("../../middleware/rate_limit.zig");
const user_svc = @import("../user/service.zig");
const audit_svc = @import("../audit/service.zig");
const member_persist = @import("../member/persistence.zig");
const setting_store_mod = @import("../setting/persistence.zig");
const payment_service = @import("../payment/service.zig");

const service = @import("service.zig");

const CategoryDto = struct {
    id: i64,
    account_id: i64,
    name: []const u8,
    parent_id: i64,
    sort: i64,
};

fn toCategoryDto(row: service.ShopCategoryRow) CategoryDto {
    return .{
        .id = row.id,
        .account_id = row.account_id,
        .name = row.name,
        .parent_id = row.parent_id,
        .sort = row.sort,
    };
}

const ProductDto = struct {
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
};

fn toProductDto(row: service.ShopProductRow) ProductDto {
    return .{
        .id = row.id,
        .account_id = row.account_id,
        .category_id = row.category_id,
        .name = row.name,
        .image = row.image,
        .content = row.content,
        .price = std.fmt.parseInt(i64, row.price, 10) catch 0,
        .original_price = std.fmt.parseInt(i64, row.original_price, 10) catch 0,
        .stock = row.stock,
        .sales = row.sales,
        .status = row.status,
        .created_at = row.created_at,
    };
}

const SkuDto = struct {
    id: i64,
    product_id: i64,
    spec_json: []const u8,
    image: []const u8,
    price: i64,
    stock: i64,
};

fn toSkuDto(row: service.ShopSkuRow) SkuDto {
    return .{
        .id = row.id,
        .product_id = row.product_id,
        .spec_json = row.spec_json,
        .image = row.image,
        .price = std.fmt.parseInt(i64, row.price, 10) catch 0,
        .stock = row.stock,
    };
}

const CreateCategoryReq = struct {
    account_id: i64,
    name: []const u8,
    parent_id: i64 = 0,
    sort: i64 = 0,
};

const SkuReq = service.SkuInput;

const ProductReq = struct {
    account_id: i64,
    category_id: i64 = 0,
    name: []const u8,
    image: []const u8 = "",
    content: []const u8 = "",
    price: i64,
    original_price: i64 = 0,
    stock: i64,
    status: i64 = 1,
    skus: []const SkuReq = &.{},
};

pub fn ShopApi(comptime Service: type, comptime UserService: type) type {
    return struct {
        const Self = @This();
        svc: *Service,
        user_svc: *UserService,
        audit: *audit_svc.AuditService,
        default_tenant_id: i64,
        limiter: *mw_rate.PerIpLimiter,
        fan_store: *member_persist.FanStore,
        settings: *setting_store_mod.SettingStore,
        order_timeout_secs: i64,

        pub const module_name = "shop";
        pub const nest: []const []const u8 = &.{};
        pub const State = Self;

        pub const routes: []const http.RouteSpec(Self) = &.{
            // Public C-end routes
            .{ .method = .GET, .path = "shop/categories", .handler = http.wrapHandler(Self, publicCategories), .meta = .{ .auth = .public } },
            .{ .method = .GET, .path = "shop/products", .handler = http.wrapHandler(Self, publicProducts), .meta = .{ .auth = .public } },
            .{ .method = .GET, .path = "shop/products/{id}", .handler = http.wrapHandler(Self, productDetail), .meta = .{ .auth = .public } },
            .{ .method = .POST, .path = "shop/cart/add", .handler = http.wrapHandler(Self, cartAdd), .meta = .{ .auth = .public } },
            .{ .method = .GET, .path = "shop/cart", .handler = http.wrapHandler(Self, cartList), .meta = .{ .auth = .public } },
            .{ .method = .PUT, .path = "shop/cart/{id}", .handler = http.wrapHandler(Self, cartUpdate), .meta = .{ .auth = .public } },
            .{ .method = .DELETE, .path = "shop/cart/{id}", .handler = http.wrapHandler(Self, cartDelete), .meta = .{ .auth = .public } },
            .{ .method = .POST, .path = "shop/addresses", .handler = http.wrapHandler(Self, addressCreate), .meta = .{ .auth = .public } },
            .{ .method = .GET, .path = "shop/addresses", .handler = http.wrapHandler(Self, addressList), .meta = .{ .auth = .public } },
            .{ .method = .PUT, .path = "shop/addresses/{id}", .handler = http.wrapHandler(Self, addressUpdate), .meta = .{ .auth = .public } },
            .{ .method = .DELETE, .path = "shop/addresses/{id}", .handler = http.wrapHandler(Self, addressDelete), .meta = .{ .auth = .public } },
            .{ .method = .POST, .path = "shop/addresses/{id}/default", .handler = http.wrapHandler(Self, addressSetDefault), .meta = .{ .auth = .public } },
            .{ .method = .POST, .path = "shop/orders", .handler = http.wrapHandler(Self, orderCreate), .meta = .{ .auth = .public } },
            .{ .method = .GET, .path = "shop/orders", .handler = http.wrapHandler(Self, orderList), .meta = .{ .auth = .public } },
            .{ .method = .GET, .path = "shop/orders/overview", .handler = http.wrapHandler(Self, orderOverview), .meta = .{ .auth = .public } },
            .{ .method = .GET, .path = "shop/orders/summaries", .handler = http.wrapHandler(Self, orderSummaries), .meta = .{ .auth = .public } },
            .{ .method = .GET, .path = "shop/orders/{id}", .handler = http.wrapHandler(Self, orderDetail), .meta = .{ .auth = .public } },
            .{ .method = .POST, .path = "shop/orders/{id}/cancel", .handler = http.wrapHandler(Self, orderCancel), .meta = .{ .auth = .public } },
            .{ .method = .POST, .path = "shop/orders/{id}/confirm", .handler = http.wrapHandler(Self, orderConfirm), .meta = .{ .auth = .public } },
            .{ .method = .POST, .path = "shop/refunds", .handler = http.wrapHandler(Self, refundApply), .meta = .{ .auth = .public } },
            .{ .method = .GET, .path = "shop/refunds", .handler = http.wrapHandler(Self, refundByOrder), .meta = .{ .auth = .public } },
            .{ .method = .GET, .path = "shop/comments", .handler = http.wrapHandler(Self, productComments), .meta = .{ .auth = .public } },
            .{ .method = .POST, .path = "shop/comments", .handler = http.wrapHandler(Self, commentCreate), .meta = .{ .auth = .public } },
            .{ .method = .POST, .path = "shop/favorites", .handler = http.wrapHandler(Self, favoriteAdd), .meta = .{ .auth = .public } },
            .{ .method = .GET, .path = "shop/favorites", .handler = http.wrapHandler(Self, favoriteList), .meta = .{ .auth = .public } },
            .{ .method = .GET, .path = "shop/outlets", .handler = http.wrapHandler(Self, outletList), .meta = .{ .auth = .public } },
            .{ .method = .GET, .path = "shop/balance-plans", .handler = http.wrapHandler(Self, planList), .meta = .{ .auth = .public } },
            .{ .method = .POST, .path = "shop/balance-plans/{id}/recharge", .handler = http.wrapHandler(Self, planRecharge), .meta = .{ .auth = .public } },
            .{ .method = .GET, .path = "shop/groupons", .handler = http.wrapHandler(Self, grouponList), .meta = .{ .auth = .public } },
            .{ .method = .POST, .path = "shop/groupons/{id}/open", .handler = http.wrapHandler(Self, grouponOpen), .meta = .{ .auth = .public } },
            .{ .method = .POST, .path = "shop/groupons/teams/{id}/join", .handler = http.wrapHandler(Self, grouponJoin), .meta = .{ .auth = .public } },
            .{ .method = .GET, .path = "shop/invites/gifts", .handler = http.wrapHandler(Self, inviteGifts), .meta = .{ .auth = .public } },
            .{ .method = .POST, .path = "shop/invites/bind", .handler = http.wrapHandler(Self, inviteBind), .meta = .{ .auth = .public } },
            .{ .method = .GET, .path = "shop/invites/my", .handler = http.wrapHandler(Self, inviteMy), .meta = .{ .auth = .public } },
            .{ .method = .GET, .path = "shop/articles", .handler = http.wrapHandler(Self, articleList), .meta = .{ .auth = .public } },
            .{ .method = .GET, .path = "shop/articles/{id}", .handler = http.wrapHandler(Self, articleDetail), .meta = .{ .auth = .public } },
            .{ .method = .POST, .path = "shop/ai/assistant", .handler = http.wrapHandler(Self, aiAssistant), .meta = .{ .auth = .public } },
            .{ .method = .POST, .path = "shop/auth/login", .handler = http.wrapHandler(Self, cLogin), .meta = .{ .auth = .public } },
            .{ .method = .GET, .path = "shop/orders/{id}/pay-params", .handler = http.wrapHandler(Self, orderPayParams), .meta = .{ .auth = .public } },
            .{ .method = .POST, .path = "shop/orders/{id}/pay-complete", .handler = http.wrapHandler(Self, orderPayComplete), .meta = .{ .auth = .public } },
            .{ .method = .DELETE, .path = "shop/favorites/{id}", .handler = http.wrapHandler(Self, favoriteDelete), .meta = .{ .auth = .public } },
            // Admin routes
            .{ .method = .POST, .path = "shop/categories", .handler = http.wrapHandler(Self, createCategory), .meta = .{ .permission = "shop:write" } },
            .{ .method = .DELETE, .path = "shop/categories/{id}", .handler = http.wrapHandler(Self, deleteCategory), .meta = .{ .permission = "shop:write" } },
            .{ .method = .POST, .path = "shop/products", .handler = http.wrapHandler(Self, createProduct), .meta = .{ .permission = "shop:write" } },
            .{ .method = .PUT, .path = "shop/products/{id}", .handler = http.wrapHandler(Self, updateProduct), .meta = .{ .permission = "shop:write" } },
            .{ .method = .DELETE, .path = "shop/products/{id}", .handler = http.wrapHandler(Self, deleteProduct), .meta = .{ .permission = "shop:write" } },
            .{ .method = .GET, .path = "shop/admin/products", .handler = http.wrapHandler(Self, adminProducts), .meta = .{ .permission = "shop:read" } },
            .{ .method = .GET, .path = "shop/admin/orders", .handler = http.wrapHandler(Self, adminOrders), .meta = .{ .permission = "shop:read" } },
            .{ .method = .POST, .path = "shop/admin/orders/{id}/ship", .handler = http.wrapHandler(Self, adminShip), .meta = .{ .permission = "shop:write" } },
            .{ .method = .GET, .path = "shop/admin/refunds", .handler = http.wrapHandler(Self, adminRefunds), .meta = .{ .permission = "shop:read" } },
            .{ .method = .POST, .path = "shop/admin/refunds/{id}/audit", .handler = http.wrapHandler(Self, adminRefundAudit), .meta = .{ .permission = "shop:write" } },
            .{ .method = .GET, .path = "shop/admin/stats", .handler = http.wrapHandler(Self, adminStats), .meta = .{ .permission = "shop:read" } },
            .{ .method = .POST, .path = "shop/admin/outlets", .handler = http.wrapHandler(Self, outletCreate), .meta = .{ .permission = "shop:write" } },
            .{ .method = .POST, .path = "shop/admin/balance-plans", .handler = http.wrapHandler(Self, planCreate), .meta = .{ .permission = "shop:write" } },
            .{ .method = .DELETE, .path = "shop/admin/balance-plans/{id}", .handler = http.wrapHandler(Self, planDelete), .meta = .{ .permission = "shop:write" } },
            .{ .method = .POST, .path = "shop/admin/groupons", .handler = http.wrapHandler(Self, grouponCreate), .meta = .{ .permission = "shop:write" } },
            .{ .method = .POST, .path = "shop/admin/invite-gifts", .handler = http.wrapHandler(Self, inviteGiftCreate), .meta = .{ .permission = "shop:write" } },
            .{ .method = .DELETE, .path = "shop/admin/invite-gifts/{id}", .handler = http.wrapHandler(Self, inviteGiftDelete), .meta = .{ .permission = "shop:write" } },
            .{ .method = .POST, .path = "shop/admin/articles", .handler = http.wrapHandler(Self, articleCreate), .meta = .{ .permission = "shop:write" } },
            .{ .method = .DELETE, .path = "shop/admin/articles/{id}", .handler = http.wrapHandler(Self, articleDelete), .meta = .{ .permission = "shop:write" } },
            .{ .method = .GET, .path = "shop/admin/articles", .handler = http.wrapHandler(Self, adminArticles), .meta = .{ .permission = "shop:read" } },
            .{ .method = .POST, .path = "shop/admin/webhooks", .handler = http.wrapHandler(Self, webhookCreate), .meta = .{ .permission = "shop:write" } },
            .{ .method = .GET, .path = "shop/admin/webhooks", .handler = http.wrapHandler(Self, webhookList), .meta = .{ .permission = "shop:read" } },
            .{ .method = .DELETE, .path = "shop/admin/webhooks/{id}", .handler = http.wrapHandler(Self, webhookDelete), .meta = .{ .permission = "shop:write" } },
            .{ .method = .DELETE, .path = "shop/admin/outlets/{id}", .handler = http.wrapHandler(Self, outletDelete), .meta = .{ .permission = "shop:write" } },
            .{ .method = .POST, .path = "shop/admin/orders/{id}/pickup", .handler = http.wrapHandler(Self, orderPickup), .meta = .{ .permission = "shop:write" } },
        };

        pub fn init(svc: *Service, users: *UserService, audit: *audit_svc.AuditService, default_tenant_id: i64, limiter: *mw_rate.PerIpLimiter, fan_store: *member_persist.FanStore, settings: *setting_store_mod.SettingStore, order_timeout_secs: i64) Self {
            return .{ .svc = svc, .user_svc = users, .audit = audit, .default_tenant_id = default_tenant_id, .limiter = limiter, .fan_store = fan_store, .settings = settings, .order_timeout_secs = order_timeout_secs };
        }

        /// 公开路由：C 端浏览（无 JWT）。
        pub fn registerPublicRoutes(self: *Self, group: *http.RouteGroup) !void {
            try group.get("/shop/categories", publicCategories, @ptrCast(@alignCast(self)));
            try group.get("/shop/products", publicProducts, @ptrCast(@alignCast(self)));
            try group.get("/shop/products/{id}", productDetail, @ptrCast(@alignCast(self)));
            // 交易（C 端，openid 标识粉丝）；写操作 per-IP 限流防刷
            var limited = try group.use(mw_rate.perIpRateLimit(self.limiter));
            try limited.post("/shop/cart/add", cartAdd, @ptrCast(@alignCast(self)));
            try limited.get("/shop/cart", cartList, @ptrCast(@alignCast(self)));
            try limited.put("/shop/cart/{id}", cartUpdate, @ptrCast(@alignCast(self)));
            try limited.delete("/shop/cart/{id}", cartDelete, @ptrCast(@alignCast(self)));
            try limited.post("/shop/addresses", addressCreate, @ptrCast(@alignCast(self)));
            try limited.get("/shop/addresses", addressList, @ptrCast(@alignCast(self)));
            try limited.put("/shop/addresses/{id}", addressUpdate, @ptrCast(@alignCast(self)));
            try limited.delete("/shop/addresses/{id}", addressDelete, @ptrCast(@alignCast(self)));
            try limited.post("/shop/addresses/{id}/default", addressSetDefault, @ptrCast(@alignCast(self)));
            try limited.post("/shop/orders", orderCreate, @ptrCast(@alignCast(self)));
            try limited.get("/shop/orders", orderList, @ptrCast(@alignCast(self)));
            try limited.get("/shop/orders/overview", orderOverview, @ptrCast(@alignCast(self)));
            try limited.get("/shop/orders/summaries", orderSummaries, @ptrCast(@alignCast(self)));
            try limited.get("/shop/orders/{id}", orderDetail, @ptrCast(@alignCast(self)));
            try limited.post("/shop/orders/{id}/cancel", orderCancel, @ptrCast(@alignCast(self)));
            try limited.post("/shop/orders/{id}/confirm", orderConfirm, @ptrCast(@alignCast(self)));
            try limited.post("/shop/refunds", refundApply, @ptrCast(@alignCast(self)));
            try limited.get("/shop/refunds", refundByOrder, @ptrCast(@alignCast(self)));
            try limited.get("/shop/comments", productComments, @ptrCast(@alignCast(self)));
            try limited.post("/shop/comments", commentCreate, @ptrCast(@alignCast(self)));
            try limited.post("/shop/favorites", favoriteAdd, @ptrCast(@alignCast(self)));
            try limited.get("/shop/favorites", favoriteList, @ptrCast(@alignCast(self)));
            try limited.get("/shop/outlets", outletList, @ptrCast(@alignCast(self)));
            try limited.get("/shop/balance-plans", planList, @ptrCast(@alignCast(self)));
            try limited.post("/shop/balance-plans/{id}/recharge", planRecharge, @ptrCast(@alignCast(self)));
            try limited.get("/shop/groupons", grouponList, @ptrCast(@alignCast(self)));
            try limited.post("/shop/groupons/{id}/open", grouponOpen, @ptrCast(@alignCast(self)));
            try limited.post("/shop/groupons/teams/{id}/join", grouponJoin, @ptrCast(@alignCast(self)));
            try limited.get("/shop/invites/gifts", inviteGifts, @ptrCast(@alignCast(self)));
            try limited.post("/shop/invites/bind", inviteBind, @ptrCast(@alignCast(self)));
            try limited.get("/shop/invites/my", inviteMy, @ptrCast(@alignCast(self)));
            try limited.get("/shop/articles", articleList, @ptrCast(@alignCast(self)));
            try limited.get("/shop/articles/{id}", articleDetail, @ptrCast(@alignCast(self)));
            try limited.post("/shop/ai/assistant", aiAssistant, @ptrCast(@alignCast(self)));
            try limited.post("/shop/auth/login", cLogin, @ptrCast(@alignCast(self)));
            try limited.get("/shop/orders/{id}/pay-params", orderPayParams, @ptrCast(@alignCast(self)));
            try limited.post("/shop/orders/{id}/pay-complete", orderPayComplete, @ptrCast(@alignCast(self)));
            try limited.delete("/shop/favorites/{id}", favoriteDelete, @ptrCast(@alignCast(self)));
        }

        /// 管理端路由：分类/商品 CRUD（admin JWT）。
        pub fn registerAdminRoutes(self: *Self, group: *http.RouteGroup) !void {
            var g = try group.use(zigmodu.http.http_middleware.jwtAuthWithSecurity(&self.user_svc.sec.module));
            g = try g.use(mw.tokenVersionGuard(self.user_svc.sec, self.user_svc.store));
            try g.post("/shop/categories", createCategory, @ptrCast(@alignCast(self)));
            try g.delete("/shop/categories/{id}", deleteCategory, @ptrCast(@alignCast(self)));
            try g.post("/shop/products", createProduct, @ptrCast(@alignCast(self)));
            try g.put("/shop/products/{id}", updateProduct, @ptrCast(@alignCast(self)));
            try g.delete("/shop/products/{id}", deleteProduct, @ptrCast(@alignCast(self)));
            try g.get("/shop/admin/products", adminProducts, @ptrCast(@alignCast(self)));
            try g.get("/shop/admin/orders", adminOrders, @ptrCast(@alignCast(self)));
            try g.post("/shop/admin/orders/{id}/ship", adminShip, @ptrCast(@alignCast(self)));
            try g.get("/shop/admin/refunds", adminRefunds, @ptrCast(@alignCast(self)));
            try g.post("/shop/admin/refunds/{id}/audit", adminRefundAudit, @ptrCast(@alignCast(self)));
            try g.get("/shop/admin/stats", adminStats, @ptrCast(@alignCast(self)));
            try g.post("/shop/admin/outlets", outletCreate, @ptrCast(@alignCast(self)));
            try g.post("/shop/admin/balance-plans", planCreate, @ptrCast(@alignCast(self)));
            try g.delete("/shop/admin/balance-plans/{id}", planDelete, @ptrCast(@alignCast(self)));
            try g.post("/shop/admin/groupons", grouponCreate, @ptrCast(@alignCast(self)));
            try g.post("/shop/admin/invite-gifts", inviteGiftCreate, @ptrCast(@alignCast(self)));
            try g.delete("/shop/admin/invite-gifts/{id}", inviteGiftDelete, @ptrCast(@alignCast(self)));
            try g.post("/shop/admin/articles", articleCreate, @ptrCast(@alignCast(self)));
            try g.delete("/shop/admin/articles/{id}", articleDelete, @ptrCast(@alignCast(self)));
            try g.get("/shop/admin/articles", adminArticles, @ptrCast(@alignCast(self)));
            try g.post("/shop/admin/webhooks", webhookCreate, @ptrCast(@alignCast(self)));
            try g.get("/shop/admin/webhooks", webhookList, @ptrCast(@alignCast(self)));
            try g.delete("/shop/admin/webhooks/{id}", webhookDelete, @ptrCast(@alignCast(self)));
            try g.delete("/shop/admin/outlets/{id}", outletDelete, @ptrCast(@alignCast(self)));
            try g.post("/shop/admin/orders/{id}/pickup", orderPickup, @ptrCast(@alignCast(self)));
        }

        pub fn setAuditActor(ctx: *http.Context, self: *Self) !void {
            const uid = ctx.userIdInt(i64) orelse return;
            const row_opt = self.user_svc.getUserById(uid) catch return;
            const row = row_opt orelse return;
            defer row.free(self.user_svc.store.allocator);
            try ctx.setAttr("audit_actor", row.name);
        }

        pub fn requireAdmin(ctx: *http.Context, self: *Self) !?i64 {
            const uid = ctx.userIdInt(i64) orelse {
                try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                return null;
            };
            const row_opt = self.user_svc.getUserById(uid) catch {
                try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                return null;
            };
            const row = row_opt orelse {
                try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                return null;
            };
            defer row.free(self.svc.allocator);
            if (!row.admin) {
                try ctx.sendErrorResponse(403, 403, "需要管理员权限");
                return null;
            }
            try ctx.setAttr("audit_actor", row.name);
            return uid;
        }

        pub fn tenantScope(ctx: *http.Context, self: *Self) i64 {
            return mw.authTenantId(ctx) orelse self.default_tenant_id;
        }

        // ── 公开 ────────────────────────────────────────────

        // ── 处理函数按子域混入（正文见 handlers/*.zig）──────────
        const h_catalog = @import("handlers/catalog.zig").Mixin(Self);
        const h_trade = @import("handlers/trade.zig").Mixin(Self);
        const h_marketing = @import("handlers/marketing.zig").Mixin(Self);
        const h_content = @import("handlers/content.zig").Mixin(Self);

        pub const publicCategories = h_catalog.publicCategories;
        pub const publicProducts = h_catalog.publicProducts;
        pub const productDetail = h_catalog.productDetail;
        pub const createCategory = h_catalog.createCategory;
        pub const deleteCategory = h_catalog.deleteCategory;
        pub const createProduct = h_catalog.createProduct;
        pub const updateProduct = h_catalog.updateProduct;
        pub const deleteProduct = h_catalog.deleteProduct;
        pub const adminProducts = h_catalog.adminProducts;
        pub const cartAdd = h_trade.cartAdd;
        pub const cartList = h_trade.cartList;
        pub const cartUpdate = h_trade.cartUpdate;
        pub const cartDelete = h_trade.cartDelete;
        pub const addressCreate = h_trade.addressCreate;
        pub const addressList = h_trade.addressList;
        pub const addressUpdate = h_trade.addressUpdate;
        pub const addressDelete = h_trade.addressDelete;
        pub const addressSetDefault = h_trade.addressSetDefault;
        pub const orderCreate = h_trade.orderCreate;
        pub const orderList = h_trade.orderList;
        pub const orderOverview = h_trade.orderOverview;
        pub const orderSummaries = h_trade.orderSummaries;
        pub const orderDetail = h_trade.orderDetail;
        pub const orderCancel = h_trade.orderCancel;
        pub const orderConfirm = h_trade.orderConfirm;
        pub const adminOrders = h_trade.adminOrders;
        pub const adminShip = h_trade.adminShip;
        pub const refundApply = h_trade.refundApply;
        pub const refundByOrder = h_trade.refundByOrder;
        pub const productComments = h_trade.productComments;
        pub const commentCreate = h_trade.commentCreate;
        pub const adminRefunds = h_trade.adminRefunds;
        pub const adminRefundAudit = h_trade.adminRefundAudit;
        pub const favoriteAdd = h_trade.favoriteAdd;
        pub const favoriteList = h_trade.favoriteList;
        pub const favoriteDelete = h_trade.favoriteDelete;
        pub const adminStats = h_trade.adminStats;
        pub const orderPickup = h_trade.orderPickup;
        pub const orderPayParams = h_trade.orderPayParams;
        pub const orderPayComplete = h_trade.orderPayComplete;
        pub const planList = h_marketing.planList;
        pub const planRecharge = h_marketing.planRecharge;
        pub const planCreate = h_marketing.planCreate;
        pub const planDelete = h_marketing.planDelete;
        pub const grouponList = h_marketing.grouponList;
        pub const grouponCreate = h_marketing.grouponCreate;
        pub const grouponOpen = h_marketing.grouponOpen;
        pub const grouponJoin = h_marketing.grouponJoin;
        pub const inviteGifts = h_marketing.inviteGifts;
        pub const inviteBind = h_marketing.inviteBind;
        pub const inviteMy = h_marketing.inviteMy;
        pub const inviteGiftCreate = h_marketing.inviteGiftCreate;
        pub const inviteGiftDelete = h_marketing.inviteGiftDelete;
        pub const outletList = h_content.outletList;
        pub const outletCreate = h_content.outletCreate;
        pub const outletDelete = h_content.outletDelete;
        pub const articleList = h_content.articleList;
        pub const articleDetail = h_content.articleDetail;
        pub const articleCreate = h_content.articleCreate;
        pub const articleDelete = h_content.articleDelete;
        pub const adminArticles = h_content.adminArticles;
        pub const aiAssistant = h_content.aiAssistant;
        pub const webhookCreate = h_content.webhookCreate;
        pub const webhookList = h_content.webhookList;
        pub const webhookDelete = h_content.webhookDelete;
        pub const cLogin = h_content.cLogin;
        pub const cOpenid = h_content.cOpenid;
    };
}

pub const DefaultShopApi = ShopApi(service.ShopService, user_svc.UserService);
