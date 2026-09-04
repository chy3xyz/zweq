//! 营销域处理器：余额套餐/拼团/邀请有礼（拆分自原 ShopApi 巨型单体，处理函数正文逐字搬运）
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

        pub fn planList(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = ApiT.tenantScope(ctx, self);
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
            try ctx.okValue(dtos);
        }

        pub fn planRecharge(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = ApiT.tenantScope(ctx, self);
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
            try ctx.ok("null");
        }

        pub fn planCreate(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try ApiT.setAuditActor(ctx, self);
            const admin_id = ctx.userIdInt(i64) orelse return;
            const tid = ApiT.tenantScope(ctx, self);
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
            try ctx.okValue(.{ .id = id });
        }

        pub fn planDelete(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try ApiT.setAuditActor(ctx, self);
            const admin_id = ctx.userIdInt(i64) orelse return;
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的套餐 ID");
                return;
            };
            self.svc.deleteBalancePlan(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "shop.plan.delete", "shop_balance_plan", id, "删除套餐", zigmodu.http.RequestUtil.getRealIp(ctx), true, ApiT.tenantScope(ctx, self));
            try ctx.ok("null");
        }

        pub fn grouponList(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = ApiT.tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const rows = self.svc.listGroupons(tid, account_id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer {
                for (rows) |r| r.free(self.svc.allocator);
                if (rows.len > 0) self.svc.allocator.free(rows);
            }
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, rows, GrouponDto, toGrouponDto);
            try ctx.okValue(dtos);
        }

        pub fn grouponCreate(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try ApiT.setAuditActor(ctx, self);
            const admin_id = ctx.userIdInt(i64) orelse return;
            const tid = ApiT.tenantScope(ctx, self);
            const req = ctx.bindJson(GrouponReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            const id = self.svc.createGroupon(tid, req.account_id, req.product_id, req.group_price, req.group_size, req.start_at, req.end_at) catch |err| {
                try ctx.sendErrorResponse(400, 400, @errorName(err));
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "shop.groupon.create", "shop_groupon", id, "创建拼团", zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.okValue(.{ .id = id });
        }

        pub fn grouponOpen(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = ApiT.tenantScope(ctx, self);
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
            try ctx.okValue(.{ .team_id = team_id });
        }

        pub fn grouponJoin(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = ApiT.tenantScope(ctx, self);
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
            try ctx.okValue(.{ .order_id = order_id });
        }

        pub fn inviteGifts(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = ApiT.tenantScope(ctx, self);
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
            try ctx.okValue(dtos);
        }

        pub fn inviteBind(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = ApiT.tenantScope(ctx, self);
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
            try ctx.ok("null");
        }

        pub fn inviteMy(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const tid = ApiT.tenantScope(ctx, self);
            const openid = ctx.query.get("openid") orelse {
                try ctx.sendErrorResponse(400, 400, "缺少 openid");
                return;
            };
            const invited = self.svc.store.marketing.countInvites(tid, openid) catch 0;
            try ctx.okValue(.{ .invited = invited, .invite_code = openid });
        }

        pub fn inviteGiftCreate(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try ApiT.setAuditActor(ctx, self);
            const admin_id = ctx.userIdInt(i64) orelse return;
            const tid = ApiT.tenantScope(ctx, self);
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
            try ctx.okValue(.{ .id = id });
        }

        pub fn inviteGiftDelete(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try ApiT.setAuditActor(ctx, self);
            const admin_id = ctx.userIdInt(i64) orelse return;
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的奖励 ID");
                return;
            };
            self.svc.deleteInviteGift(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "shop.invite_gift.delete", "shop_invite_gift", id, "删除奖励", zigmodu.http.RequestUtil.getRealIp(ctx), true, ApiT.tenantScope(ctx, self));
            try ctx.ok("null");
        }
    };
}
