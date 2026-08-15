//! Admin-facing coupon API — 券模板 CRUD + 领券记录 + 核销 + 手动领券。

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const mw = @import("../../middleware/auth.zig");
const user_svc = @import("../user/service.zig");
const audit_svc = @import("../audit/service.zig");

const service = @import("service.zig");

const CouponDto = struct {
    id: i64,
    account_id: i64,
    title: []const u8,
    amount: i64,
    min_amount: i64,
    total: i64,
    per_user: i64,
    start_at: i64,
    end_at: i64,
    created_at: i64,
};

fn toCouponDto(row: service.CouponRow) CouponDto {
    return .{
        .id = row.id,
        .account_id = row.account_id,
        .title = row.title,
        .amount = row.amount,
        .min_amount = row.min_amount,
        .total = row.total,
        .per_user = row.per_user,
        .start_at = row.start_at,
        .end_at = row.end_at,
        .created_at = row.created_at,
    };
}

const CouponUserDto = struct {
    id: i64,
    account_id: i64,
    openid: []const u8,
    coupon_id: i64,
    code: []const u8,
    status: []const u8,
    used_at: i64,
    created_at: i64,
};

fn toUserDto(row: service.CouponUserRow) CouponUserDto {
    return .{
        .id = row.id,
        .account_id = row.account_id,
        .openid = row.openid,
        .coupon_id = row.coupon_id,
        .code = row.code,
        .status = row.status,
        .used_at = row.used_at,
        .created_at = row.created_at,
    };
}

const CreateCouponReq = struct {
    account_id: i64,
    title: []const u8,
    amount: i64 = 0,
    min_amount: i64 = 0,
    total: i64 = 0,
    per_user: i64 = 1,
    start_at: i64 = 0,
    end_at: i64 = 0,
};

const ClaimReq = struct {
    openid: []const u8,
};

const UseReq = struct {
    code: []const u8,
};

pub fn CouponApi(comptime Service: type, comptime UserService: type) type {
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
            try g.get("/coupons", listCoupons, @ptrCast(@alignCast(self)));
            try g.post("/coupons", createCoupon, @ptrCast(@alignCast(self)));
            try g.delete("/coupons/{id}", deleteCoupon, @ptrCast(@alignCast(self)));
            try g.post("/coupons/{id}/claim", claim, @ptrCast(@alignCast(self)));
            try g.post("/coupons/use", useCoupon, @ptrCast(@alignCast(self)));
            try g.get("/coupon-users", listUsers, @ptrCast(@alignCast(self)));
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

        fn listCoupons(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 100 });
            var result = self.svc.listCoupons(params.page, params.page_size, tid, account_id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer result.free(self.svc.allocator);
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, CouponDto, toCouponDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }

        fn createCoupon(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);
            const req = ctx.bindJson(CreateCouponReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer ctx.allocator.free(req.title);
            const id = self.svc.createCoupon(tid, req.account_id, req.title, req.amount, req.min_amount, req.total, req.per_user, req.start_at, req.end_at) catch |err| {
                const msg = switch (err) {
                    error.InvalidInput => "参数非法",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            var d1: [128]u8 = undefined;
            const det1 = try std.fmt.bufPrint(&d1, "创建优惠券 {s}", .{req.title});
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "coupon.create", "coupon", id, det1, zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(201, .{ .code = 0, .msg = "已创建", .data = .{ .id = id } });
        }

        fn deleteCoupon(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的券 ID");
                return;
            };
            self.svc.deleteCoupon(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "coupon.delete", "coupon", id, "删除优惠券", zigmodu.http.RequestUtil.getRealIp(ctx), true, tenantScope(ctx, self));
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "已删除", .data = null });
        }

        fn claim(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的券 ID");
                return;
            };
            const req = ctx.bindJson(ClaimReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer ctx.allocator.free(req.openid);
            const code = self.svc.claimCoupon(ctx.allocator, tid, 0, req.openid, id) catch |err| {
                const msg = switch (err) {
                    error.OutOfStock => "已领完",
                    error.LimitReached => "已达每人限领",
                    error.Expired => "已过期",
                    error.NotStarted => "未开始",
                    error.NotFound => "券不存在",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            defer ctx.allocator.free(code);
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "coupon.claim", "coupon", id, "手动领券", zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "领取成功", .data = .{ .code = code } });
        }

        fn useCoupon(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const req = ctx.bindJson(UseReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer ctx.allocator.free(req.code);
            self.svc.useCoupon(req.code) catch |err| {
                const msg = switch (err) {
                    error.NotFound => "券码不存在",
                    error.AlreadyUsed => "已核销过",
                    error.Expired => "已过期",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "coupon.use", "coupon", 0, "核销优惠券", zigmodu.http.RequestUtil.getRealIp(ctx), true, tenantScope(ctx, self));
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "已核销", .data = null });
        }

        fn listUsers(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const openid = ctx.queryStr("openid", "");
            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 100 });
            var result = self.svc.listUserCoupons(params.page, params.page_size, tid, account_id, if (openid.len > 0) openid else null) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer result.free(self.svc.allocator);
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, CouponUserDto, toUserDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }
    };
}

pub const DefaultCouponApi = CouponApi(service.CouponService, user_svc.UserService);
