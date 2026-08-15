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
        .price = row.price,
        .original_price = row.original_price,
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
        .price = row.price,
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
        registry: *zigmodu.RateLimiterRegistry,
        fan_store: *member_persist.FanStore,
        settings: *setting_store_mod.SettingStore,

        pub fn init(svc: *Service, users: *UserService, audit: *audit_svc.AuditService, default_tenant_id: i64, registry: *zigmodu.RateLimiterRegistry, fan_store: *member_persist.FanStore, settings: *setting_store_mod.SettingStore) Self {
            return .{ .svc = svc, .user_svc = users, .audit = audit, .default_tenant_id = default_tenant_id, .registry = registry, .fan_store = fan_store, .settings = settings };
        }

        /// 公开路由：C 端浏览（无 JWT）。
        pub fn registerPublicRoutes(self: *Self, group: *http.RouteGroup) !void {
            try group.get("/shop/categories", publicCategories, @ptrCast(@alignCast(self)));
            try group.get("/shop/products", publicProducts, @ptrCast(@alignCast(self)));
            try group.get("/shop/products/{id}", productDetail, @ptrCast(@alignCast(self)));
            // 交易（C 端，openid 标识粉丝）；写操作 per-IP 限流防刷
            var limited = try group.use(mw_rate.perIpRateLimit(self.registry, 30, 1));
            try limited.post("/shop/cart/add", cartAdd, @ptrCast(@alignCast(self)));
            try limited.get("/shop/cart", cartList, @ptrCast(@alignCast(self)));
            try limited.put("/shop/cart/{id}", cartUpdate, @ptrCast(@alignCast(self)));
            try limited.delete("/shop/cart/{id}", cartDelete, @ptrCast(@alignCast(self)));
            try limited.post("/shop/addresses", addressCreate, @ptrCast(@alignCast(self)));
            try limited.get("/shop/addresses", addressList, @ptrCast(@alignCast(self)));
            try limited.delete("/shop/addresses/{id}", addressDelete, @ptrCast(@alignCast(self)));
            try limited.post("/shop/orders", orderCreate, @ptrCast(@alignCast(self)));
            try limited.get("/shop/orders", orderList, @ptrCast(@alignCast(self)));
            try limited.get("/shop/orders/{id}", orderDetail, @ptrCast(@alignCast(self)));
            try limited.post("/shop/orders/{id}/cancel", orderCancel, @ptrCast(@alignCast(self)));
            try limited.post("/shop/orders/{id}/confirm", orderConfirm, @ptrCast(@alignCast(self)));
            try limited.post("/shop/refunds", refundApply, @ptrCast(@alignCast(self)));
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

        fn requireAdmin(ctx: *http.Context, self: *Self) !?i64 {
            const uid = mw.authUserId(ctx) orelse {
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

        fn tenantScope(ctx: *http.Context, self: *Self) i64 {
            return mw.authTenantId(ctx) orelse self.default_tenant_id;
        }

        // ── 公开 ────────────────────────────────────────────

        fn publicCategories(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            var result = self.svc.listCategories(tid, account_id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer result.free(self.svc.allocator);
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, CategoryDto, toCategoryDto);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = dtos });
        }

        fn publicProducts(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const category_id = ctx.queryInt(i64, "category_id", 0);
            const keyword = ctx.query.get("keyword") orelse "";
            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 50 });
            var result = self.svc.listProducts(params.page, params.page_size, tid, account_id, category_id, keyword, true) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer result.free(self.svc.allocator);
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, ProductDto, toProductDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }

        fn productDetail(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的商品 ID");
                return;
            };
            const p_opt = self.svc.getProduct(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            const p = p_opt orelse {
                try ctx.sendErrorResponse(404, 404, "商品不存在");
                return;
            };
            defer p.free(self.svc.allocator);
            const skus = self.svc.listSkus(id) catch &.{};
            defer {
                for (skus) |s| s.free(self.svc.allocator);
                if (skus.len > 0) self.svc.allocator.free(skus);
            }
            const sku_dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, skus, SkuDto, toSkuDto);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = .{ .product = toProductDto(p), .skus = sku_dtos } });
        }

        // ── 管理端 ──────────────────────────────────────────

        fn createCategory(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);
            const req = ctx.bindJson(CreateCategoryReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer ctx.allocator.free(req.name);
            const id = self.svc.createCategory(tid, req.account_id, req.name, req.parent_id, req.sort) catch |err| {
                try ctx.sendErrorResponse(400, 400, @errorName(err));
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "shop.category.create", "shop_category", id, "创建分类", zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(201, .{ .code = 0, .msg = "已创建", .data = .{ .id = id } });
        }

        fn deleteCategory(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的分类 ID");
                return;
            };
            self.svc.deleteCategory(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "shop.category.delete", "shop_category", id, "删除分类", zigmodu.http.RequestUtil.getRealIp(ctx), true, tenantScope(ctx, self));
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "已删除", .data = null });
        }

        fn createProduct(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);
            const req = ctx.bindJson(ProductReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer {
                ctx.allocator.free(req.name);
                ctx.allocator.free(req.image);
                ctx.allocator.free(req.content);
                for (req.skus) |s| {
                    ctx.allocator.free(s.spec_json);
                    ctx.allocator.free(s.image);
                }
                ctx.allocator.free(req.skus);
            }
            const input = service.ProductInput{
                .category_id = req.category_id,
                .name = req.name,
                .image = req.image,
                .content = req.content,
                .price = req.price,
                .original_price = req.original_price,
                .stock = req.stock,
                .status = req.status,
                .skus = req.skus,
            };
            const id = self.svc.createProduct(tid, req.account_id, input) catch |err| {
                try ctx.sendErrorResponse(400, 400, @errorName(err));
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "shop.product.create", "shop_product", id, "创建商品", zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(201, .{ .code = 0, .msg = "已创建", .data = .{ .id = id } });
        }

        fn updateProduct(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的商品 ID");
                return;
            };
            const req = ctx.bindJson(ProductReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer {
                ctx.allocator.free(req.name);
                ctx.allocator.free(req.image);
                ctx.allocator.free(req.content);
                for (req.skus) |s| {
                    ctx.allocator.free(s.spec_json);
                    ctx.allocator.free(s.image);
                }
                ctx.allocator.free(req.skus);
            }
            const input = service.ProductInput{
                .category_id = req.category_id,
                .name = req.name,
                .image = req.image,
                .content = req.content,
                .price = req.price,
                .original_price = req.original_price,
                .stock = req.stock,
                .status = req.status,
                .skus = req.skus,
            };
            self.svc.updateProduct(tid, req.account_id, id, input) catch |err| {
                try ctx.sendErrorResponse(400, 400, @errorName(err));
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "shop.product.update", "shop_product", id, "更新商品", zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "已更新", .data = null });
        }

        fn deleteProduct(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的商品 ID");
                return;
            };
            self.svc.deleteProduct(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "shop.product.delete", "shop_product", id, "删除商品", zigmodu.http.RequestUtil.getRealIp(ctx), true, tenantScope(ctx, self));
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "已删除", .data = null });
        }

        /// 管理端商品列表（含下架，不要求 account_id）。
        fn adminProducts(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const category_id = ctx.queryInt(i64, "category_id", 0);
            const keyword = ctx.query.get("keyword") orelse "";
            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 100 });
            var result = self.svc.listProducts(params.page, params.page_size, tid, account_id, category_id, keyword, false) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer result.free(self.svc.allocator);
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, ProductDto, toProductDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }
        fn cartAdd(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = tenantScope(ctx, self);
            const req = ctx.bindJson(CartAddReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer ctx.allocator.free(req.openid);
            const id = self.svc.addCart(tid, 0, req.openid, req.product_id, req.sku_id, req.quantity) catch |err| {
                try ctx.sendErrorResponse(400, 400, @errorName(err));
                return;
            };
            try ctx.jsonStruct(201, .{ .code = 0, .msg = "已加入购物车", .data = .{ .id = id } });
        }

        fn cartList(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = tenantScope(ctx, self);
            const openid = ctx.query.get("openid") orelse {
                try ctx.sendErrorResponse(400, 400, "缺少 openid");
                return;
            };
            const rows = self.svc.listCarts(tid, openid) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer {
                for (rows) |r| r.free(self.svc.allocator);
                if (rows.len > 0) self.svc.allocator.free(rows);
            }
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, rows, CartDto, toCartDto);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = dtos });
        }

        fn cartUpdate(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的购物车 ID");
                return;
            };
            const qty = ctx.queryInt(i64, "quantity", 1);
            self.svc.updateCart(id, qty) catch |err| {
                try ctx.sendErrorResponse(400, 400, @errorName(err));
                return;
            };
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "已更新", .data = null });
        }

        fn cartDelete(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的购物车 ID");
                return;
            };
            self.svc.deleteCart(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "已删除", .data = null });
        }

        fn addressCreate(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = tenantScope(ctx, self);
            const req = ctx.bindJson(AddressReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer {
                ctx.allocator.free(req.openid);
                ctx.allocator.free(req.name);
                ctx.allocator.free(req.mobile);
                ctx.allocator.free(req.region);
                ctx.allocator.free(req.detail);
            }
            const id = self.svc.createAddress(tid, 0, .{ .openid = req.openid, .name = req.name, .mobile = req.mobile, .region = req.region, .detail = req.detail, .is_default = req.is_default }) catch |err| {
                try ctx.sendErrorResponse(400, 400, @errorName(err));
                return;
            };
            try ctx.jsonStruct(201, .{ .code = 0, .msg = "已创建", .data = .{ .id = id } });
        }

        fn addressList(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = tenantScope(ctx, self);
            const openid = ctx.query.get("openid") orelse {
                try ctx.sendErrorResponse(400, 400, "缺少 openid");
                return;
            };
            const rows = self.svc.listAddresses(tid, openid) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer {
                for (rows) |r| r.free(self.svc.allocator);
                if (rows.len > 0) self.svc.allocator.free(rows);
            }
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, rows, AddressDto, toAddressDto);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = dtos });
        }

        fn addressDelete(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的地址 ID");
                return;
            };
            self.svc.deleteAddress(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "已删除", .data = null });
        }

        fn orderCreate(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = tenantScope(ctx, self);
            const req = ctx.bindJson(OrderCreateReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer {
                ctx.allocator.free(req.openid);
                ctx.allocator.free(req.coupon_code);
                ctx.allocator.free(req.client_trade_no);
                ctx.allocator.free(req.pay_type);
                for (req.items) |it| _ = it;
            }
            // C 端 JWT 优先：带合法 C-token 时 openid 取自 token（忽略 body，防伪造）。
            const buyer_owned = cOpenid(ctx, self);
            defer if (buyer_owned) |b| self.svc.allocator.free(b);
            const buyer_openid = buyer_owned orelse req.openid;
            const order_id = self.svc.createOrder(tid, req.account_id, buyer_openid, req.address_id, req.items, req.coupon_code, req.client_trade_no, req.pay_type, req.pickup_store_id) catch |err| {
                const msg = switch (err) {
                    error.OutOfStock => "库存不足",
                    error.InsufficientBalance => "余额不足",
                    error.InvalidInput => "参数不合法",
                    error.NotFound => "商品不存在",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            // mock 支付：直接标记已支付（真实走 payment 模块）
            self.svc.markPaid(tid, req.account_id, order_id) catch {};
            try ctx.jsonStruct(201, .{ .code = 0, .msg = "下单成功", .data = .{ .id = order_id } });
        }

        fn orderList(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const openid = ctx.query.get("openid") orelse "";
            const status = ctx.queryInt(i64, "status", -1);
            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 50 });
            var result = self.svc.listOrders(params.page, params.page_size, tid, account_id, openid, status) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer result.free(self.svc.allocator);
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, OrderDto, toOrderDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }

        fn orderDetail(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的订单 ID");
                return;
            };
            const o_opt = self.svc.getOrder(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            const o = o_opt orelse {
                try ctx.sendErrorResponse(404, 404, "订单不存在");
                return;
            };
            defer o.free(self.svc.allocator);
            const ops = self.svc.listOrderProducts(id) catch &.{};
            defer {
                for (ops) |op| op.free(self.svc.allocator);
                if (ops.len > 0) self.svc.allocator.free(ops);
            }
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = .{ .order = toOrderDto(o), .items = ops } });
        }

        fn orderCancel(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的订单 ID");
                return;
            };
            self.svc.cancelOrder(id) catch |err| {
                try ctx.sendErrorResponse(400, 400, @errorName(err));
                return;
            };
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "已取消", .data = null });
        }

        fn orderConfirm(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的订单 ID");
                return;
            };
            self.svc.confirmOrder(id) catch |err| {
                try ctx.sendErrorResponse(400, 400, @errorName(err));
                return;
            };
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "已确认收货", .data = null });
        }

        fn adminOrders(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const status = ctx.queryInt(i64, "status", -1);
            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 100 });
            var result = self.svc.listOrders(params.page, params.page_size, tid, account_id, "", status) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer result.free(self.svc.allocator);
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, OrderDto, toOrderDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }

        fn adminShip(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的订单 ID");
                return;
            };
            const req = ctx.bindJson(ShipReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer {
                ctx.allocator.free(req.company);
                ctx.allocator.free(req.no);
            }
            self.svc.shipOrder(id, req.company, req.no) catch |err| {
                try ctx.sendErrorResponse(400, 400, @errorName(err));
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "shop.order.ship", "shop_order", id, "订单发货", zigmodu.http.RequestUtil.getRealIp(ctx), true, tenantScope(ctx, self));
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "已发货", .data = null });
        }

        fn refundApply(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = tenantScope(ctx, self);
            const req = ctx.bindJson(RefundApplyReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer {
                ctx.allocator.free(req.openid);
                ctx.allocator.free(req.reason);
            }
            _ = self.svc.applyRefund(tid, req.account_id, req.order_id, req.openid, req.reason) catch |err| {
                const msg = switch (err) {
                    error.OrderStateConflict => "当前订单状态不可退款",
                    error.Duplicate => "该订单已申请退款",
                    error.NotFound => "订单不存在",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            try ctx.jsonStruct(201, .{ .code = 0, .msg = "退款申请已提交", .data = null });
        }

        fn productComments(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const product_id = ctx.queryInt(i64, "product_id", 0);
            if (product_id <= 0) {
                try ctx.sendErrorResponse(400, 400, "缺少 product_id");
                return;
            }
            const rows = self.svc.listComments(product_id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer {
                for (rows) |r| r.free(self.svc.allocator);
                if (rows.len > 0) self.svc.allocator.free(rows);
            }
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, rows, CommentDto, toCommentDto);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = dtos });
        }

        fn commentCreate(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = tenantScope(ctx, self);
            const req = ctx.bindJson(CommentReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer {
                ctx.allocator.free(req.openid);
                ctx.allocator.free(req.content);
            }
            const id = self.svc.createComment(tid, req.account_id, .{
                .order_product_id = req.order_product_id,
                .product_id = req.product_id,
                .openid = req.openid,
                .star = req.star,
                .content = req.content,
            }) catch |err| {
                try ctx.sendErrorResponse(400, 400, @errorName(err));
                return;
            };
            try ctx.jsonStruct(201, .{ .code = 0, .msg = "评价成功", .data = .{ .id = id } });
        }

        fn adminRefunds(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const status = ctx.queryInt(i64, "status", -1);
            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 100 });
            var result = self.svc.listRefunds(params.page, params.page_size, tid, account_id, status) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer result.free(self.svc.allocator);
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, RefundDto, toRefundDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }

        fn adminRefundAudit(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的退款 ID");
                return;
            };
            const req = ctx.bindJson(RefundAuditReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            self.svc.auditRefund(req.order_id, id, req.approve) catch |err| {
                try ctx.sendErrorResponse(400, 400, @errorName(err));
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "shop.refund.audit", "shop_refund", id, if (req.approve) "同意退款" else "拒绝退款", zigmodu.http.RequestUtil.getRealIp(ctx), true, tenantScope(ctx, self));
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "已处理", .data = null });
        }

        fn favoriteAdd(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = tenantScope(ctx, self);
            const req = ctx.bindJson(FavoriteReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer ctx.allocator.free(req.openid);
            self.svc.favorite(tid, req.account_id, req.openid, req.product_id) catch |err| {
                try ctx.sendErrorResponse(400, 400, @errorName(err));
                return;
            };
            try ctx.jsonStruct(201, .{ .code = 0, .msg = "已收藏", .data = null });
        }

        fn favoriteList(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = tenantScope(ctx, self);
            const openid = ctx.query.get("openid") orelse {
                try ctx.sendErrorResponse(400, 400, "缺少 openid");
                return;
            };
            const rows = self.svc.listFavorites(tid, openid) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer {
                for (rows) |r| r.free(self.svc.allocator);
                if (rows.len > 0) self.svc.allocator.free(rows);
            }
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, rows, FavoriteDto, toFavoriteDto);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = dtos });
        }

        fn favoriteDelete(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的收藏 ID");
                return;
            };
            self.svc.unfavorite(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "已取消收藏", .data = null });
        }

        fn adminStats(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const stats = self.svc.orderStats(tid, account_id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = stats });
        }

        fn outletList(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const rows = self.svc.listOutlets(tid, account_id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer {
                for (rows) |r| r.free(self.svc.allocator);
                if (rows.len > 0) self.svc.allocator.free(rows);
            }
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, rows, OutletDto, toOutletDto);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = dtos });
        }

        fn outletCreate(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);
            const req = ctx.bindJson(OutletReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer {
                ctx.allocator.free(req.name);
                ctx.allocator.free(req.address);
                ctx.allocator.free(req.mobile);
            }
            const id = self.svc.createOutlet(tid, req.account_id, req.name, req.address, req.mobile) catch |err| {
                try ctx.sendErrorResponse(400, 400, @errorName(err));
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "shop.outlet.create", "shop_outlet", id, "创建门店", zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(201, .{ .code = 0, .msg = "已创建", .data = .{ .id = id } });
        }

        fn outletDelete(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的门店 ID");
                return;
            };
            self.svc.deleteOutlet(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "shop.outlet.delete", "shop_outlet", id, "删除门店", zigmodu.http.RequestUtil.getRealIp(ctx), true, tenantScope(ctx, self));
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "已删除", .data = null });
        }

        fn orderPickup(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的订单 ID");
                return;
            };
            const req = ctx.bindJson(PickupReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer ctx.allocator.free(req.code);
            self.svc.pickupOrder(id, req.code) catch |err| {
                const msg = switch (err) {
                    error.OrderStateConflict => "订单状态不可核销",
                    error.InvalidInput => "核销码不正确",
                    error.NotFound => "订单不存在",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "shop.order.pickup", "shop_order", id, "自提核销", zigmodu.http.RequestUtil.getRealIp(ctx), true, tenantScope(ctx, self));
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "核销成功", .data = null });
        }

        fn planList(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const rows = self.svc.listBalancePlans(tid, account_id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer {
                for (rows) |r| r.free(self.svc.allocator);
                if (rows.len > 0) self.svc.allocator.free(rows);
            }
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, rows, PlanDto, toPlanDto);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = dtos });
        }

        fn planRecharge(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = tenantScope(ctx, self);
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的套餐 ID");
                return;
            };
            const req = ctx.bindJson(RechargeReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer ctx.allocator.free(req.openid);
            self.svc.rechargePlan(tid, req.account_id, req.openid, id) catch |err| {
                const msg = switch (err) {
                    error.NotFound => "套餐不存在",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "充值成功", .data = null });
        }

        fn planCreate(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);
            const req = ctx.bindJson(PlanReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer ctx.allocator.free(req.name);
            const id = self.svc.createBalancePlan(tid, req.account_id, req.name, req.amount, req.bonus) catch |err| {
                try ctx.sendErrorResponse(400, 400, @errorName(err));
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "shop.plan.create", "shop_balance_plan", id, "创建储值套餐", zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(201, .{ .code = 0, .msg = "已创建", .data = .{ .id = id } });
        }

        fn planDelete(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的套餐 ID");
                return;
            };
            self.svc.deleteBalancePlan(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "shop.plan.delete", "shop_balance_plan", id, "删除套餐", zigmodu.http.RequestUtil.getRealIp(ctx), true, tenantScope(ctx, self));
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "已删除", .data = null });
        }

        fn grouponList(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const rows = self.svc.listGroupons(tid, account_id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer {
                for (rows) |r| _ = r;
                if (rows.len > 0) self.svc.allocator.free(rows);
            }
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, rows, GrouponDto, toGrouponDto);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = dtos });
        }

        fn grouponCreate(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);
            const req = ctx.bindJson(GrouponReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            const id = self.svc.createGroupon(tid, req.account_id, req.product_id, req.group_price, req.group_size, req.start_at, req.end_at) catch |err| {
                try ctx.sendErrorResponse(400, 400, @errorName(err));
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "shop.groupon.create", "shop_groupon", id, "创建拼团", zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(201, .{ .code = 0, .msg = "已创建", .data = .{ .id = id } });
        }

        fn grouponOpen(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = tenantScope(ctx, self);
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的拼团 ID");
                return;
            };
            const req = ctx.bindJson(GrouponOpenReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer ctx.allocator.free(req.openid);
            const team_id = self.svc.openGroupon(tid, req.account_id, req.openid, req.address_id, id, req.sku_id) catch |err| {
                const msg = switch (err) {
                    error.OutOfStock => "库存不足",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            try ctx.jsonStruct(201, .{ .code = 0, .msg = "开团成功", .data = .{ .team_id = team_id } });
        }

        fn grouponJoin(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = tenantScope(ctx, self);
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的团 ID");
                return;
            };
            const req = ctx.bindJson(GrouponJoinReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer ctx.allocator.free(req.openid);
            const order_id = self.svc.joinGroupon(tid, req.account_id, req.openid, req.address_id, id, req.sku_id) catch |err| {
                const msg = switch (err) {
                    error.OutOfStock => "库存不足",
                    error.InvalidInput => "拼团已结束",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            try ctx.jsonStruct(201, .{ .code = 0, .msg = "参团成功", .data = .{ .order_id = order_id } });
        }

        fn inviteGifts(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const rows = self.svc.listInviteGifts(tid, account_id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer {
                for (rows) |r| r.free(self.svc.allocator);
                if (rows.len > 0) self.svc.allocator.free(rows);
            }
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, rows, InviteGiftDto, toInviteGiftDto);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = dtos });
        }

        fn inviteBind(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = tenantScope(ctx, self);
            const req = ctx.bindJson(InviteBindReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer {
                ctx.allocator.free(req.inviter_openid);
                ctx.allocator.free(req.invitee_openid);
            }
            self.svc.bindInvite(tid, req.account_id, req.inviter_openid, req.invitee_openid) catch |err| {
                try ctx.sendErrorResponse(400, 400, @errorName(err));
                return;
            };
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "已绑定", .data = null });
        }

        fn inviteMy(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = tenantScope(ctx, self);
            const openid = ctx.query.get("openid") orelse {
                try ctx.sendErrorResponse(400, 400, "缺少 openid");
                return;
            };
            const invited = self.svc.store.countInvites(tid, openid) catch 0;
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = .{ .invited = invited, .invite_code = openid } });
        }

        fn inviteGiftCreate(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);
            const req = ctx.bindJson(InviteGiftReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer ctx.allocator.free(req.reward_type);
            const id = self.svc.createInviteGift(tid, req.account_id, req.target_count, req.reward_type, req.reward_value) catch |err| {
                try ctx.sendErrorResponse(400, 400, @errorName(err));
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "shop.invite_gift.create", "shop_invite_gift", id, "创建邀请奖励", zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(201, .{ .code = 0, .msg = "已创建", .data = .{ .id = id } });
        }

        fn inviteGiftDelete(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的奖励 ID");
                return;
            };
            self.svc.deleteInviteGift(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "shop.invite_gift.delete", "shop_invite_gift", id, "删除奖励", zigmodu.http.RequestUtil.getRealIp(ctx), true, tenantScope(ctx, self));
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "已删除", .data = null });
        }

        fn articleList(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 50 });
            var result = self.svc.listArticles(params.page, params.page_size, tid, account_id, true) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer result.free(self.svc.allocator);
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, ArticleDto, toArticleDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }

        fn articleDetail(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的文章 ID");
                return;
            };
            const a_opt = self.svc.getArticle(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            const a = a_opt orelse {
                try ctx.sendErrorResponse(404, 404, "文章不存在");
                return;
            };
            defer a.free(self.svc.allocator);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = toArticleDto(a) });
        }

        fn articleCreate(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);
            const req = ctx.bindJson(ArticleReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer {
                ctx.allocator.free(req.title);
                ctx.allocator.free(req.content);
            }
            const id = self.svc.createArticle(tid, req.account_id, req.title, req.content) catch |err| {
                try ctx.sendErrorResponse(400, 400, @errorName(err));
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "shop.article.create", "shop_article", id, "发布文章", zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(201, .{ .code = 0, .msg = "已发布", .data = .{ .id = id } });
        }

        fn articleDelete(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的文章 ID");
                return;
            };
            self.svc.deleteArticle(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "shop.article.delete", "shop_article", id, "删除文章", zigmodu.http.RequestUtil.getRealIp(ctx), true, tenantScope(ctx, self));
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "已删除", .data = null });
        }

        fn adminArticles(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 100 });
            var result = self.svc.listArticles(params.page, params.page_size, tid, account_id, false) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer result.free(self.svc.allocator);
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, ArticleDto, toArticleDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }

        fn aiAssistant(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = tenantScope(ctx, self);
            const req = ctx.bindJson(AssistantReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer {
                ctx.allocator.free(req.openid);
                ctx.allocator.free(req.question);
            }
            const reply = self.svc.assistant(ctx.allocator, tid, req.account_id, req.openid, req.question) catch |err| {
                try ctx.sendErrorResponse(400, 400, @errorName(err));
                return;
            };
            defer ctx.allocator.free(reply);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = .{ .reply = reply } });
        }

        fn webhookCreate(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);
            const req = ctx.bindJson(WebhookReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer {
                ctx.allocator.free(req.url);
                ctx.allocator.free(req.events);
            }
            const id = self.svc.createWebhook(tid, req.account_id, req.url, req.events) catch |err| {
                try ctx.sendErrorResponse(400, 400, @errorName(err));
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "shop.webhook.create", "shop_webhook", id, "创建 Webhook", zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(201, .{ .code = 0, .msg = "已创建", .data = .{ .id = id } });
        }

        fn webhookList(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const rows = self.svc.listWebhooks(tid, account_id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer {
                for (rows) |r| r.free(self.svc.allocator);
                if (rows.len > 0) self.svc.allocator.free(rows);
            }
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, rows, WebhookDto, toWebhookDto);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = dtos });
        }

        fn webhookDelete(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的 Webhook ID");
                return;
            };
            self.svc.deleteWebhook(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "shop.webhook.delete", "shop_webhook", id, "删除 Webhook", zigmodu.http.RequestUtil.getRealIp(ctx), true, tenantScope(ctx, self));
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "已删除", .data = null });
        }

        /// C 端登录：openid 必须是粉丝 → 签发 C-token（roles=["fan"]）。
        fn cLogin(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = tenantScope(ctx, self);
            const req = ctx.bindJson(CLoginReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer ctx.allocator.free(req.openid);
            // 校验 openid 是粉丝（防任意签发）。
            const fan_opt = self.fan_store.getByOpenid(tid, req.account_id, req.openid) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            const fan = fan_opt orelse {
                try ctx.sendErrorResponse(400, 400, "粉丝不存在，请先在公众号互动");
                return;
            };
            defer fan.free(self.svc.allocator);
            const token = self.user_svc.sec.module.generateTokenWithTenant(req.openid, &.{"fan"}, "0") catch {
                try ctx.sendErrorResponse(500, 500, "签发失败");
                return;
            };
            defer self.svc.allocator.free(token);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = .{ .token = token } });
        }

        /// 从 Authorization 头解析 C-token 的 openid（无/非法 → null）。
        /// 返回 owned sub（调用方负责 free）；payload 内部在此释放。
        fn cOpenid(ctx: *http.Context, self: *Self) ?[]const u8 {
            const header = ctx.headers.get("authorization") orelse return null;
            if (header.len < 7 or !std.mem.startsWith(u8, header, "Bearer ")) return null;
            const token = header[7..];
            const payload = self.user_svc.sec.module.verifyToken(token) catch return null;
            defer {
                self.svc.allocator.free(payload.sub);
                self.svc.allocator.free(payload.iss);
                self.svc.allocator.free(payload.aud);
                for (payload.roles) |r| self.svc.allocator.free(r);
                self.svc.allocator.free(payload.roles);
            }
            // roles 含 fan 才是 C 端 token。
            var is_fan = false;
            for (payload.roles) |r| {
                if (std.mem.eql(u8, r, "fan")) {
                    is_fan = true;
                    break;
                }
            }
            if (!is_fan) return null;
            return self.svc.allocator.dupe(u8, payload.sub) catch null;
        }

        /// 订单支付参数：站点配了微信支付 v3 → JSAPI prepay；未配 → mock。
        fn orderPayParams(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = tenantScope(ctx, self);
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的订单 ID");
                return;
            };
            const o_opt = self.svc.getOrder(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            const o = o_opt orelse {
                try ctx.sendErrorResponse(404, 404, "订单不存在");
                return;
            };
            defer o.free(self.svc.allocator);
            if (o.status != 0) {
                try ctx.sendErrorResponse(400, 400, "订单已支付或不可支付");
                return;
            }
            const openid_owned = cOpenid(ctx, self);
            defer if (openid_owned) |o_| self.svc.allocator.free(o_);
            const openid = openid_owned orelse o.openid;

            // v3 配置（站点设置）。
            var cfg = payment_service.PayConfig{};
            var has_mch = false;
            const keys = [_][]const u8{ "wechat_pay_mchid", "wechat_pay_appid", "wechat_pay_serial_no", "wechat_pay_private_key", "wechat_pay_notify_url", "wechat_pay_platform_cert" };
            for (keys) |key| {
                const row_opt = self.settings.get(tid, key) catch null;
                if (row_opt) |row| {
                    defer row.free(self.settings.allocator);
                    if (row.value.len == 0) continue;
                    const dup = ctx.allocator.dupe(u8, row.value) catch continue;
                    if (std.mem.eql(u8, key, "wechat_pay_mchid")) {
                        cfg.mch_id = dup;
                        has_mch = true;
                    } else if (std.mem.eql(u8, key, "wechat_pay_appid")) {
                        cfg.app_id = dup;
                    } else if (std.mem.eql(u8, key, "wechat_pay_serial_no")) {
                        cfg.serial_no = dup;
                    } else if (std.mem.eql(u8, key, "wechat_pay_private_key")) {
                        cfg.private_key_pem = dup;
                    } else if (std.mem.eql(u8, key, "wechat_pay_notify_url")) {
                        cfg.notify_url = dup;
                    } else if (std.mem.eql(u8, key, "wechat_pay_platform_cert")) {
                        cfg.platform_cert = dup;
                    }
                }
            }
            if (!has_mch) {
                try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = .{ .mode = "mock", .amount = o.pay_amount, .order_no = o.order_no } });
                return;
            }
            defer cfg.deinit(ctx.allocator);
            // 真实 v3：构建 JSAPI prepay（纯签名，无网络）。
            const pay_opt = self.svc.payment_svc orelse {
                try ctx.sendErrorResponse(400, 400, "支付服务未就绪");
                return;
            };
            const psvc: *payment_service.PaymentService = @ptrCast(@alignCast(pay_opt));
            const prepay = psvc.buildPrepayRequest(ctx.allocator, cfg, o.order_no, o.pay_amount, "商城订单", openid) catch {
                try ctx.sendErrorResponse(400, 400, "构建支付参数失败");
                return;
            };
            defer prepay.deinit(ctx.allocator);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = .{ .mode = "wxpay_v3", .prepay = prepay } });
        }

        /// mock 支付完成（v3 模式下由微信 notify 触发，本接口拒绝）。
        fn orderPayComplete(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = tenantScope(ctx, self);
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的订单 ID");
                return;
            };
            const o_opt = self.svc.getOrder(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            const o = o_opt orelse {
                try ctx.sendErrorResponse(404, 404, "订单不存在");
                return;
            };
            defer o.free(self.svc.allocator);
            if (o.status != 0) {
                try ctx.sendErrorResponse(400, 400, "订单已支付或不可支付");
                return;
            }
            // C 端身份校验：买家必须与订单一致（token 优先）。
            const buyer_owned = cOpenid(ctx, self) orelse {
                try ctx.sendErrorResponse(401, 401, "请先登录");
                return;
            };
            defer self.svc.allocator.free(buyer_owned);
            if (!std.mem.eql(u8, buyer_owned, o.openid)) {
                try ctx.sendErrorResponse(403, 403, "无权操作他人订单");
                return;
            }
            self.svc.markPaid(tid, o.account_id, id) catch |err| {
                try ctx.sendErrorResponse(400, 400, @errorName(err));
                return;
            };
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "支付成功", .data = null });
        }

    };
}


const RefundApplyReq = struct {
    account_id: i64,
    order_id: i64,
    openid: []const u8,
    reason: []const u8,
};

const CommentReq = struct {
    account_id: i64,
    order_product_id: i64,
    product_id: i64,
    openid: []const u8,
    star: i64 = 5,
    content: []const u8 = "",
};

const RefundAuditReq = struct {
    order_id: i64,
    approve: bool,
};

const RefundDto = struct {
    id: i64,
    account_id: i64,
    order_id: i64,
    openid: []const u8,
    reason: []const u8,
    amount: i64,
    status: i64,
    created_at: i64,
};

fn toRefundDto(row: service.ShopRefundRow) RefundDto {
    return .{ .id = row.id, .account_id = row.account_id, .order_id = row.order_id, .openid = row.openid, .reason = row.reason, .amount = row.amount, .status = row.status, .created_at = row.created_at };
}

const CommentDto = struct {
    id: i64,
    product_id: i64,
    openid: []const u8,
    star: i64,
    content: []const u8,
    created_at: i64,
};

fn toCommentDto(row: service.ShopCommentRow) CommentDto {
    return .{ .id = row.id, .product_id = row.product_id, .openid = row.openid, .star = row.star, .content = row.content, .created_at = row.created_at };
}



const FavoriteReq = struct {
    account_id: i64,
    openid: []const u8,
    product_id: i64,
};

const FavoriteDto = struct {
    id: i64,
    openid: []const u8,
    product_id: i64,
    created_at: i64,
};

fn toFavoriteDto(row: service.ShopFavoriteRow) FavoriteDto {
    return .{ .id = row.id, .openid = row.openid, .product_id = row.product_id, .created_at = row.created_at };
}



const OutletReq = struct {
    account_id: i64,
    name: []const u8,
    address: []const u8 = "",
    mobile: []const u8 = "",
};

const PickupReq = struct {
    code: []const u8,
};

const OutletDto = struct {
    id: i64,
    account_id: i64,
    name: []const u8,
    address: []const u8,
    mobile: []const u8,
    status: i64,
};

fn toOutletDto(row: service.ShopOutletRow) OutletDto {
    return .{ .id = row.id, .account_id = row.account_id, .name = row.name, .address = row.address, .mobile = row.mobile, .status = row.status };
}



const PlanReq = struct {
    account_id: i64,
    name: []const u8,
    amount: i64,
    bonus: i64 = 0,
};

const RechargeReq = struct {
    account_id: i64,
    openid: []const u8,
};

const PlanDto = struct {
    id: i64,
    account_id: i64,
    name: []const u8,
    amount: i64,
    bonus: i64,
    status: i64,
};

fn toPlanDto(row: service.ShopBalancePlanRow) PlanDto {
    return .{ .id = row.id, .account_id = row.account_id, .name = row.name, .amount = row.amount, .bonus = row.bonus, .status = row.status };
}



const GrouponReq = struct {
    account_id: i64,
    product_id: i64,
    group_price: i64,
    group_size: i64 = 2,
    start_at: i64 = 0,
    end_at: i64 = 0,
};

const GrouponOpenReq = struct {
    account_id: i64,
    openid: []const u8,
    address_id: i64,
    sku_id: i64,
};

const GrouponJoinReq = struct {
    account_id: i64,
    openid: []const u8,
    address_id: i64,
    sku_id: i64,
};

const GrouponDto = struct {
    id: i64,
    account_id: i64,
    product_id: i64,
    group_price: i64,
    group_size: i64,
    status: i64,
};

fn toGrouponDto(row: service.ShopGrouponRow) GrouponDto {
    return .{ .id = row.id, .account_id = row.account_id, .product_id = row.product_id, .group_price = row.group_price, .group_size = row.group_size, .status = row.status };
}



const InviteGiftReq = struct {
    account_id: i64,
    target_count: i64,
    reward_type: []const u8,
    reward_value: i64,
};

const InviteBindReq = struct {
    account_id: i64,
    inviter_openid: []const u8,
    invitee_openid: []const u8,
};

const InviteGiftDto = struct {
    id: i64,
    account_id: i64,
    target_count: i64,
    reward_type: []const u8,
    reward_value: i64,
};

fn toInviteGiftDto(row: service.ShopInviteGiftRow) InviteGiftDto {
    return .{ .id = row.id, .account_id = row.account_id, .target_count = row.target_count, .reward_type = row.reward_type, .reward_value = row.reward_value };
}



const ArticleReq = struct {
    account_id: i64,
    title: []const u8,
    content: []const u8 = "",
};

const ArticleDto = struct {
    id: i64,
    account_id: i64,
    title: []const u8,
    content: []const u8,
    status: i64,
    created_at: i64,
};

fn toArticleDto(row: service.ShopArticleRow) ArticleDto {
    return .{ .id = row.id, .account_id = row.account_id, .title = row.title, .content = row.content, .status = row.status, .created_at = row.created_at };
}



const AssistantReq = struct {
    account_id: i64,
    openid: []const u8,
    question: []const u8,
};



const WebhookReq = struct {
    account_id: i64,
    url: []const u8,
    events: []const u8 = "order.paid",
};

const WebhookDto = struct {
    id: i64,
    account_id: i64,
    url: []const u8,
    events: []const u8,
    status: i64,
};

fn toWebhookDto(row: service.ShopWebhookRow) WebhookDto {
    return .{ .id = row.id, .account_id = row.account_id, .url = row.url, .events = row.events, .status = row.status };
}



const CLoginReq = struct {
    account_id: i64,
    openid: []const u8,
};






pub const DefaultShopApi = ShopApi(service.ShopService, user_svc.UserService);

// ── 交易 handler（Phase 2）────────────────────────────────

const CartAddReq = struct {
    openid: []const u8,
    product_id: i64,
    sku_id: i64,
    quantity: i64 = 1,
};

const AddressReq = struct {
    openid: []const u8,
    name: []const u8,
    mobile: []const u8,
    region: []const u8,
    detail: []const u8,
    is_default: i64 = 0,
};

const OrderItemReq = service.OrderItemInput;

const OrderCreateReq = struct {
    account_id: i64,
    openid: []const u8,
    address_id: i64,
    items: []const OrderItemReq,
    coupon_code: []const u8 = "",
    client_trade_no: []const u8 = "",
    pay_type: []const u8 = "",
    pickup_store_id: i64 = 0,
};

const ShipReq = struct {
    company: []const u8,
    no: []const u8,
};

const CartDto = struct {
    id: i64,
    openid: []const u8,
    product_id: i64,
    sku_id: i64,
    quantity: i64,
    created_at: i64,
};

fn toCartDto(row: service.ShopCartRow) CartDto {
    return .{ .id = row.id, .openid = row.openid, .product_id = row.product_id, .sku_id = row.sku_id, .quantity = row.quantity, .created_at = row.created_at };
}

const AddressDto = struct {
    id: i64,
    openid: []const u8,
    name: []const u8,
    mobile: []const u8,
    region: []const u8,
    detail: []const u8,
    is_default: i64,
};

fn toAddressDto(row: service.ShopAddressRow) AddressDto {
    return .{ .id = row.id, .openid = row.openid, .name = row.name, .mobile = row.mobile, .region = row.region, .detail = row.detail, .is_default = row.is_default };
}

const OrderDto = struct {
    id: i64,
    account_id: i64,
    order_no: []const u8,
    openid: []const u8,
    total_amount: i64,
    pay_amount: i64,
    status: i64,
    express_company: []const u8,
    express_no: []const u8,
    paid_at: i64,
    created_at: i64,
};

fn toOrderDto(row: service.ShopOrderRow) OrderDto {
    return .{ .id = row.id, .account_id = row.account_id, .order_no = row.order_no, .openid = row.openid, .total_amount = row.total_amount, .pay_amount = row.pay_amount, .status = row.status, .express_company = row.express_company, .express_no = row.express_no, .paid_at = row.paid_at, .created_at = row.created_at };
}

