//! Admin-facing points API — 积分商品 CRUD + 兑换 + 积分调整。

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const mw = @import("../../middleware/auth.zig");
const user_svc = @import("../user/service.zig");
const audit_svc = @import("../audit/service.zig");

const service = @import("service.zig");

const ProductDto = struct {
    id: i64,
    account_id: i64,
    name: []const u8,
    points: i64,
    stock: i64,
};

fn toProductDto(row: service.PointsProductRow) ProductDto {
    return .{ .id = row.id, .account_id = row.account_id, .name = row.name, .points = row.points, .stock = row.stock };
}

const ProductReq = struct {
    account_id: i64,
    name: []const u8,
    points: i64,
    stock: i64,
};

const RedeemReq = struct {
    account_id: i64,
    openid: []const u8,
    product_id: i64,
};

const AdjustReq = struct {
    account_id: i64,
    openid: []const u8,
    delta: i64,
};

pub fn PointsApi(comptime Service: type, comptime UserService: type) type {
    return struct {
        const Self = @This();
        svc: *Service,
        user_svc: *UserService,
        audit: *audit_svc.AuditService,
        default_tenant_id: i64,

        pub fn init(svc: *Service, users: *UserService, audit: *audit_svc.AuditService, default_tenant_id: i64) Self {
            return .{ .svc = svc, .user_svc = users, .audit = audit, .default_tenant_id = default_tenant_id };
        }

        pub fn registerRoutes(self: *Self, group: *http.RouteGroup) !void {
            var g = try group.use(zigmodu.http.http_middleware.jwtAuthWithSecurity(&self.user_svc.sec.module));
            g = try g.use(mw.tokenVersionGuard(self.user_svc.sec, self.user_svc.store));
            try g.get("/points/products", listProducts, @ptrCast(@alignCast(self)));
            try g.post("/points/products", createProduct, @ptrCast(@alignCast(self)));
            try g.get("/points/products/{id}", getProduct, @ptrCast(@alignCast(self)));
            try g.put("/points/products/{id}", updateProduct, @ptrCast(@alignCast(self)));
            try g.delete("/points/products/{id}", deleteProduct, @ptrCast(@alignCast(self)));
            try g.post("/points/redeem", redeem, @ptrCast(@alignCast(self)));
            try g.post("/points/adjust", adjust, @ptrCast(@alignCast(self)));
            try g.get("/points/orders", listOrders, @ptrCast(@alignCast(self)));
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

        fn listProducts(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);
            const account_raw = ctx.queryParam("account_id") orelse {
                try ctx.sendErrorResponse(400, 400, "缺少 account_id");
                return;
            };
            const account_id = std.fmt.parseInt(i64, account_raw, 10) catch {
                try ctx.sendErrorResponse(400, 400, "无效的 account_id");
                return;
            };
            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 100 });
            var result = self.svc.listProducts(params.page, params.page_size, tid, account_id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer result.free(self.svc.allocator);
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, ProductDto, toProductDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }

        fn createProduct(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);
            const req = ctx.bindJson(ProductReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer ctx.allocator.free(req.name);
            const id = self.svc.createProduct(tid, req.account_id, req.name, req.points, req.stock) catch |err| {
                const msg = switch (err) {
                    error.InvalidName => "商品名不能为空",
                    error.InvalidPoints => "积分须大于 0",
                    error.InvalidStock => "库存不能为负",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "points.product.create", "points", id, "创建积分商品", zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(201, .{ .code = 0, .msg = "已创建", .data = .{ .id = id } });
        }

        fn getProduct(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = (try requireAdmin(ctx, self)) orelse return;
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的商品 ID");
                return;
            };
            const row_opt = self.svc.getProduct(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            const row = row_opt orelse {
                try ctx.sendErrorResponse(404, 404, "商品不存在");
                return;
            };
            defer row.free(self.svc.allocator);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = toProductDto(row) });
        }

        fn updateProduct(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的商品 ID");
                return;
            };
            const req = ctx.bindJson(struct { name: []const u8, points: i64, stock: i64 }) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer ctx.allocator.free(req.name);
            self.svc.updateProduct(id, req.name, req.points, req.stock) catch |err| {
                const msg = switch (err) {
                    error.InvalidName => "商品名不能为空",
                    error.InvalidPoints => "积分须大于 0",
                    error.InvalidStock => "库存不能为负",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "points.product.update", "points", id, "更新积分商品", zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = null });
        }

        fn deleteProduct(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的商品 ID");
                return;
            };
            self.svc.deleteProduct(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "points.product.delete", "points", id, "删除积分商品", zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = null });
        }

        fn redeem(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);
            const req = ctx.bindJson(RedeemReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer ctx.allocator.free(req.openid);
            const order_id = self.svc.redeem(tid, req.account_id, req.openid, req.product_id) catch |err| {
                const msg = switch (err) {
                    error.ProductNotFound => "商品不存在",
                    error.OutOfStock => "库存不足",
                    error.FanNotFound => "粉丝不存在",
                    error.InsufficientPoints => "积分不足",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "兑换成功", .data = .{ .order_id = order_id } });
        }

        fn adjust(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);
            const req = ctx.bindJson(AdjustReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer ctx.allocator.free(req.openid);
            const points = self.svc.adjustPoints(tid, req.account_id, req.openid, req.delta) catch |err| {
                const msg = switch (err) {
                    error.FanNotFound => "粉丝不存在",
                    error.InsufficientPoints => "积分不足",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "points.adjust", "points", req.account_id, "调整粉丝积分", zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = .{ .points = points } });
        }

        fn listOrders(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);
            const account_raw = ctx.queryParam("account_id") orelse {
                try ctx.sendErrorResponse(400, 400, "缺少 account_id");
                return;
            };
            const account_id = std.fmt.parseInt(i64, account_raw, 10) catch {
                try ctx.sendErrorResponse(400, 400, "无效的 account_id");
                return;
            };
            const openid = ctx.queryParam("openid");
            const rows = self.svc.listOrders(tid, account_id, openid) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer {
                for (rows) |r| r.free(ctx.allocator);
                ctx.allocator.free(rows);
            }
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = .{ .items = rows } });
        }
    };
}

pub const DefaultPointsApi = PointsApi(service.PointsService, user_svc.UserService);
