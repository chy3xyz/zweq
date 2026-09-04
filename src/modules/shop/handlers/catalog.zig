//! 商品目录域处理器：分类/商品的 C 端浏览与管理端 CRUD（拆分自原 ShopApi 巨型单体，处理函数正文逐字搬运）
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

        pub fn publicCategories(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = ApiT.tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            var result = self.svc.listCategories(tid, account_id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer result.free(self.svc.allocator);
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, CategoryDto, toCategoryDto);
            try ctx.okValue(dtos);
        }

        pub fn publicProducts(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = ApiT.tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const category_id = ctx.queryInt(i64, "category_id", 0);
            const keyword = ctx.query.get("keyword") orelse "";
            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 50 });
            // C 端只暴露上架商品。
            var result = self.svc.listProducts(params.page, params.page_size, tid, account_id, category_id, keyword, 1) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer result.free(self.svc.allocator);
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, ProductDto, toProductDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }

        pub fn productDetail(ctx: *http.Context) !void {
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
            try ctx.okValue(.{ .product = toProductDto(p), .skus = sku_dtos });
        }

        // ── 管理端 ──────────────────────────────────────────

        pub fn createCategory(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try ApiT.setAuditActor(ctx, self);
            const admin_id = ctx.userIdInt(i64) orelse return;
            const tid = ApiT.tenantScope(ctx, self);
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
            try ctx.okValue(.{ .id = id });
        }

        pub fn deleteCategory(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try ApiT.setAuditActor(ctx, self);
            const admin_id = ctx.userIdInt(i64) orelse return;
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的分类 ID");
                return;
            };
            self.svc.deleteCategory(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "shop.category.delete", "shop_category", id, "删除分类", zigmodu.http.RequestUtil.getRealIp(ctx), true, ApiT.tenantScope(ctx, self));
            try ctx.ok("null");
        }

        pub fn createProduct(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try ApiT.setAuditActor(ctx, self);
            const admin_id = ctx.userIdInt(i64) orelse return;
            const tid = ApiT.tenantScope(ctx, self);
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
                .images = req.images,
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
            try ctx.okValue(.{ .id = id });
        }

        pub fn updateProduct(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try ApiT.setAuditActor(ctx, self);
            const admin_id = ctx.userIdInt(i64) orelse return;
            const tid = ApiT.tenantScope(ctx, self);
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
                .images = req.images,
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
            try ctx.ok("null");
        }

        pub fn deleteProduct(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try ApiT.setAuditActor(ctx, self);
            const admin_id = ctx.userIdInt(i64) orelse return;
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的商品 ID");
                return;
            };
            self.svc.deleteProduct(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "shop.product.delete", "shop_product", id, "删除商品", zigmodu.http.RequestUtil.getRealIp(ctx), true, ApiT.tenantScope(ctx, self));
            try ctx.ok("null");
        }

        /// 管理端商品列表（含下架，不要求 account_id）。
        pub fn adminProducts(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try ApiT.setAuditActor(ctx, self);
            const tid = ApiT.tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const category_id = ctx.queryInt(i64, "category_id", 0);
            const keyword = ctx.query.get("keyword") orelse "";
            // -1 = 全部，管理端可通过 status=0/1 按下架/上架筛选。
            const status = ctx.queryInt(i64, "status", -1);
            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 100 });
            var result = self.svc.listProducts(params.page, params.page_size, tid, account_id, category_id, keyword, status) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer result.free(self.svc.allocator);
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, ProductDto, toProductDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }
    };
}
