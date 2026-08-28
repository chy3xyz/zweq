//! 交易域处理器：购物车/地址/订单/退款/评论/收藏/统计与支付参数链路（拆分自原 ShopApi 巨型单体，处理函数正文逐字搬运）
const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const mw = @import("../../../middleware/auth.zig");
const mw_rate = @import("../../../middleware/rate_limit.zig");
const user_svc = @import("../../user/service.zig");
const audit_svc = @import("../../audit/service.zig");
const member_persist = @import("../../member/persistence.zig");
const setting_store_mod = @import("../../setting/persistence.zig");
const payment_service = @import("../../payment/service.zig");
const service = @import("../service.zig");

// DTO / toXxxDto 映射器整体迁至 api_dto.zig，经 usingnamespace 并回同名作用域。
const dto = @import("../api_dto.zig");
const RefundApplyReq = dto.RefundApplyReq;
const CommentReq = dto.CommentReq;
const RefundAuditReq = dto.RefundAuditReq;
const RefundDto = dto.RefundDto;
const toRefundDto = dto.toRefundDto;
const CommentDto = dto.CommentDto;
const toCommentDto = dto.toCommentDto;
const FavoriteReq = dto.FavoriteReq;
const FavoriteDto = dto.FavoriteDto;
const toFavoriteDto = dto.toFavoriteDto;
const OutletReq = dto.OutletReq;
const PickupReq = dto.PickupReq;
const OutletDto = dto.OutletDto;
const toOutletDto = dto.toOutletDto;
const PlanReq = dto.PlanReq;
const RechargeReq = dto.RechargeReq;
const PlanDto = dto.PlanDto;
const toPlanDto = dto.toPlanDto;
const GrouponReq = dto.GrouponReq;
const GrouponOpenReq = dto.GrouponOpenReq;
const GrouponJoinReq = dto.GrouponJoinReq;
const GrouponDto = dto.GrouponDto;
const toGrouponDto = dto.toGrouponDto;
const InviteGiftReq = dto.InviteGiftReq;
const InviteBindReq = dto.InviteBindReq;
const InviteGiftDto = dto.InviteGiftDto;
const toInviteGiftDto = dto.toInviteGiftDto;
const ArticleReq = dto.ArticleReq;
const ArticleDto = dto.ArticleDto;
const toArticleDto = dto.toArticleDto;
const AssistantReq = dto.AssistantReq;
const WebhookReq = dto.WebhookReq;
const WebhookDto = dto.WebhookDto;
const toWebhookDto = dto.toWebhookDto;
const CLoginReq = dto.CLoginReq;
const CartAddReq = dto.CartAddReq;
const AddressReq = dto.AddressReq;
const OrderItemReq = dto.OrderItemReq;
const OrderCreateReq = dto.OrderCreateReq;
const ShipReq = dto.ShipReq;
const CartDto = dto.CartDto;
const toCartDto = dto.toCartDto;
const AddressDto = dto.AddressDto;
const toAddressDto = dto.toAddressDto;
const OrderDto = dto.OrderDto;
const toOrderDto = dto.toOrderDto;
const OrderProductDto = dto.OrderProductDto;
const toOrderProductDto = dto.toOrderProductDto;
const CategoryDto = dto.CategoryDto;
const toCategoryDto = dto.toCategoryDto;
const ProductDto = dto.ProductDto;
const toProductDto = dto.toProductDto;
const SkuDto = dto.SkuDto;
const toSkuDto = dto.toSkuDto;
const CreateCategoryReq = dto.CreateCategoryReq;
const SkuReq = dto.SkuReq;
const ProductReq = dto.ProductReq;

/// 混入宿主：对宿主成员（setAuditActor / requireAdmin / tenantScope /
/// cOpenid）的跨文件调用已改写为 ApiT.xxx 形式。
pub fn Mixin(comptime ApiT: type) type {
    return struct {
        const Self = ApiT;

        pub fn cartAdd(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = ApiT.tenantScope(ctx, self);
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

        pub fn cartList(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = ApiT.tenantScope(ctx, self);
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

        pub fn cartUpdate(ctx: *http.Context) !void {
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

        pub fn cartDelete(ctx: *http.Context) !void {
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

        pub fn addressCreate(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = ApiT.tenantScope(ctx, self);
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

        pub fn addressList(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = ApiT.tenantScope(ctx, self);
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

        pub fn addressDelete(ctx: *http.Context) !void {
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

        pub fn orderCreate(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = ApiT.tenantScope(ctx, self);
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
            const buyer_owned = ApiT.cOpenid(ctx, self);
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

        pub fn orderList(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = ApiT.tenantScope(ctx, self);
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

        pub fn orderDetail(ctx: *http.Context) !void {
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
            const item_dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, ops, OrderProductDto, toOrderProductDto);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = .{ .order = toOrderDto(o), .items = item_dtos } });
        }

        pub fn orderCancel(ctx: *http.Context) !void {
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

        pub fn orderConfirm(ctx: *http.Context) !void {
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

        pub fn adminOrders(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try ApiT.setAuditActor(ctx, self);
            const tid = ApiT.tenantScope(ctx, self);
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

        pub fn adminShip(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try ApiT.setAuditActor(ctx, self);
            const admin_id = mw.authUserId(ctx) orelse return;
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
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "shop.order.ship", "shop_order", id, "订单发货", zigmodu.http.RequestUtil.getRealIp(ctx), true, ApiT.tenantScope(ctx, self));
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "已发货", .data = null });
        }

        pub fn refundApply(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = ApiT.tenantScope(ctx, self);
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

        pub fn productComments(ctx: *http.Context) !void {
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

        pub fn commentCreate(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = ApiT.tenantScope(ctx, self);
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

        pub fn adminRefunds(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try ApiT.setAuditActor(ctx, self);
            const tid = ApiT.tenantScope(ctx, self);
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

        pub fn adminRefundAudit(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try ApiT.setAuditActor(ctx, self);
            const admin_id = mw.authUserId(ctx) orelse return;
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
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "shop.refund.audit", "shop_refund", id, if (req.approve) "同意退款" else "拒绝退款", zigmodu.http.RequestUtil.getRealIp(ctx), true, ApiT.tenantScope(ctx, self));
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "已处理", .data = null });
        }

        pub fn favoriteAdd(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = ApiT.tenantScope(ctx, self);
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

        pub fn favoriteList(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = ApiT.tenantScope(ctx, self);
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

        pub fn favoriteDelete(ctx: *http.Context) !void {
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

        pub fn adminStats(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try ApiT.setAuditActor(ctx, self);
            const tid = ApiT.tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const stats = self.svc.orderStats(tid, account_id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = stats });
        }

        pub fn orderPickup(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try ApiT.setAuditActor(ctx, self);
            const admin_id = mw.authUserId(ctx) orelse return;
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
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "shop.order.pickup", "shop_order", id, "自提核销", zigmodu.http.RequestUtil.getRealIp(ctx), true, ApiT.tenantScope(ctx, self));
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "核销成功", .data = null });
        }

        /// 订单支付参数：站点配了微信支付 v3 → JSAPI prepay；未配 → mock。
        pub fn orderPayParams(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = ApiT.tenantScope(ctx, self);
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
            const openid_owned = ApiT.cOpenid(ctx, self);
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
            const pay_amount = std.fmt.parseInt(i64, o.pay_amount, 10) catch 0;
            if (!has_mch) {
                try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = .{ .mode = "mock", .amount = pay_amount, .order_no = o.order_no } });
                return;
            }
            defer cfg.deinit(ctx.allocator);
            // 真实 v3：构建 JSAPI prepay（纯签名，无网络）。
            const pay_opt = self.svc.payment_svc orelse {
                try ctx.sendErrorResponse(400, 400, "支付服务未就绪");
                return;
            };
            const psvc: *payment_service.PaymentService = @ptrCast(@alignCast(pay_opt));
            const prepay = psvc.buildPrepayRequest(ctx.allocator, cfg, o.order_no, pay_amount, "商城订单", openid) catch {
                try ctx.sendErrorResponse(400, 400, "构建支付参数失败");
                return;
            };
            defer prepay.deinit(ctx.allocator);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = .{ .mode = "wxpay_v3", .prepay = prepay } });
        }

        /// mock 支付完成（v3 模式下由微信 notify 触发，本接口拒绝）。
        pub fn orderPayComplete(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = ApiT.tenantScope(ctx, self);
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
            const buyer_owned = ApiT.cOpenid(ctx, self) orelse {
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
