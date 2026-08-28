//! 内容与门店域处理器：门店自提/文章/webhook/AI 助手/C 端登录（拆分自原 ShopApi 巨型单体，处理函数正文逐字搬运）
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

        pub fn outletList(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = ApiT.tenantScope(ctx, self);
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

        pub fn outletCreate(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try ApiT.setAuditActor(ctx, self);
            const admin_id = mw.authUserId(ctx) orelse return;
            const tid = ApiT.tenantScope(ctx, self);
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

        pub fn outletDelete(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try ApiT.setAuditActor(ctx, self);
            const admin_id = mw.authUserId(ctx) orelse return;
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的门店 ID");
                return;
            };
            self.svc.deleteOutlet(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "shop.outlet.delete", "shop_outlet", id, "删除门店", zigmodu.http.RequestUtil.getRealIp(ctx), true, ApiT.tenantScope(ctx, self));
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "已删除", .data = null });
        }

        pub fn articleList(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = ApiT.tenantScope(ctx, self);
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

        pub fn articleDetail(ctx: *http.Context) !void {
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

        pub fn articleCreate(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try ApiT.setAuditActor(ctx, self);
            const admin_id = mw.authUserId(ctx) orelse return;
            const tid = ApiT.tenantScope(ctx, self);
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

        pub fn articleDelete(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try ApiT.setAuditActor(ctx, self);
            const admin_id = mw.authUserId(ctx) orelse return;
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的文章 ID");
                return;
            };
            self.svc.deleteArticle(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "shop.article.delete", "shop_article", id, "删除文章", zigmodu.http.RequestUtil.getRealIp(ctx), true, ApiT.tenantScope(ctx, self));
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "已删除", .data = null });
        }

        pub fn adminArticles(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try ApiT.setAuditActor(ctx, self);
            const tid = ApiT.tenantScope(ctx, self);
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

        pub fn aiAssistant(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = ApiT.tenantScope(ctx, self);
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

        pub fn webhookCreate(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try ApiT.setAuditActor(ctx, self);
            const admin_id = mw.authUserId(ctx) orelse return;
            const tid = ApiT.tenantScope(ctx, self);
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

        pub fn webhookList(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try ApiT.setAuditActor(ctx, self);
            const tid = ApiT.tenantScope(ctx, self);
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

        pub fn webhookDelete(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try ApiT.setAuditActor(ctx, self);
            const admin_id = mw.authUserId(ctx) orelse return;
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的 Webhook ID");
                return;
            };
            self.svc.deleteWebhook(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "shop.webhook.delete", "shop_webhook", id, "删除 Webhook", zigmodu.http.RequestUtil.getRealIp(ctx), true, ApiT.tenantScope(ctx, self));
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "已删除", .data = null });
        }

        /// C 端登录：openid 必须是粉丝 → 签发 C-token（roles=["fan"]）。
        pub fn cLogin(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = ApiT.tenantScope(ctx, self);
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
        pub fn cOpenid(ctx: *http.Context, self: *Self) ?[]const u8 {
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
    };
}
