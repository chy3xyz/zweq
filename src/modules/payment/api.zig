//! Admin-facing payment API — recharge orders, wallet, withdraws.

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const mw = @import("../../middleware/auth.zig");
const user_svc = @import("../user/service.zig");
const audit_svc = @import("../audit/service.zig");
const setting_store_mod = @import("../setting/persistence.zig");

const service = @import("service.zig");

const OrderDto = struct {
    id: i64,
    order_no: []const u8,
    fan_id: i64,
    amount: i64,
    channel: []const u8,
    status: []const u8,
    paid_at: i64,
    created_at: i64,
};

fn toOrderDto(row: service.RechargeOrderRow) OrderDto {
    return .{
        .id = row.id,
        .order_no = row.order_no,
        .fan_id = row.fan_id,
        .amount = row.amount,
        .channel = row.channel,
        .status = row.status,
        .paid_at = row.paid_at,
        .created_at = row.created_at,
    };
}

const WalletDto = struct {
    account_id: i64,
    fan_id: i64,
    balance: i64,
};

const WithdrawDto = struct {
    id: i64,
    fan_id: i64,
    amount: i64,
    status: []const u8,
    created_at: i64,
};

fn toWithdrawDto(row: service.WithdrawRow) WithdrawDto {
    return .{
        .id = row.id,
        .fan_id = row.fan_id,
        .amount = row.amount,
        .status = row.status,
        .created_at = row.created_at,
    };
}

const RechargeReq = struct {
    account_id: i64,
    fan_id: i64,
    amount: i64,
    /// WeChat openid — required for real v3 JSAPI prepay.
    openid: ?[]const u8 = null,
};

const WithdrawReq = struct {
    account_id: i64,
    fan_id: i64,
    amount: i64,
};

pub fn PaymentApi(comptime Service: type, comptime UserService: type) type {
    return struct {
        const Self = @This();
        svc: *Service,
        user_svc: *UserService,
        audit: *audit_svc.AuditService,
        default_tenant_id: i64,
        settings: *setting_store_mod.SettingStore,

        pub fn init(svc: *Service, users: *UserService, audit: *audit_svc.AuditService, default_tenant_id: i64, settings: *setting_store_mod.SettingStore) Self {
            return .{ .svc = svc, .user_svc = users, .audit = audit, .default_tenant_id = default_tenant_id, .settings = settings };
        }

        /// Read WeChat Pay v3 merchant config from site settings (empty = mock).
        fn readPayConfig(ctx: *http.Context, self: *Self, tid: i64) ?service.PayConfig {
            var cfg = service.PayConfig{};
            const keys = [_][]const u8{ "wechat_pay_mchid", "wechat_pay_appid", "wechat_pay_serial_no", "wechat_pay_private_key", "wechat_pay_notify_url", "wechat_pay_platform_cert" };
            for (keys) |key| {
                const row_opt = self.settings.get(tid, key) catch null;
                if (row_opt) |row| {
                    defer row.free(self.settings.allocator);
                    if (row.value.len == 0) continue;
                    const dup = ctx.allocator.dupe(u8, row.value) catch continue;
                    if (std.mem.eql(u8, key, "wechat_pay_mchid")) {
                        cfg.mch_id = dup;
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
            if (cfg.mch_id.len == 0) return null;
            return cfg;
        }

        pub fn registerRoutes(self: *Self, group: *http.RouteGroup) !void {
            var g = try group.use(zigmodu.http.http_middleware.jwtAuthWithSecurity(&self.user_svc.sec.module));
            g = try g.use(mw.tokenVersionGuard(self.user_svc.sec, self.user_svc.store));
            try g.post("/pay/recharge", recharge, @ptrCast(@alignCast(self)));
            try g.post("/pay/recharge/{order_no}/complete", complete, @ptrCast(@alignCast(self)));
            try g.get("/pay/wallet", wallet, @ptrCast(@alignCast(self)));
            try g.get("/pay/orders", orders, @ptrCast(@alignCast(self)));
            try g.post("/pay/withdraws", withdraw, @ptrCast(@alignCast(self)));
            try g.get("/pay/withdraws", withdraws, @ptrCast(@alignCast(self)));
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

        fn recharge(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);

            const req = ctx.bindJson(RechargeReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer if (req.openid) |o| ctx.allocator.free(o);
            const pay_cfg = readPayConfig(ctx, self, tid);
            const result = if (pay_cfg) |cfg|
                self.svc.createV3RechargeOrder(ctx.allocator, tid, req.account_id, req.fan_id, req.amount, req.openid orelse "", cfg)
            else
                self.svc.createRechargeOrder(ctx.allocator, tid, req.account_id, req.fan_id, req.amount);
            const row = result catch |err| {
                const msg = switch (err) {
                    error.InvalidAmount => "金额必须大于 0",
                    error.InvalidPayConfig => "支付配置不完整（缺 mchid/appid/serial_no/私钥）",
                    error.PrepayFailed => "微信支付下单失败",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            defer row.free(self.svc.allocator);
            var d1: [128]u8 = undefined;
            const det1 = try std.fmt.bufPrint(&d1, "创建充值订单 {s} {d}分", .{ row.order_no, row.amount });
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "pay.recharge", "payment", row.id, det1, zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(201, .{ .code = 0, .msg = "订单已创建", .data = toOrderDto(row) });
        }

        fn complete(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);

            const order_no = ctx.param("order_no") orelse {
                try ctx.sendErrorResponse(400, 400, "缺少订单号");
                return;
            };
            const paid = self.svc.completeRecharge(tid, order_no) catch |err| {
                try ctx.sendErrorResponse(500, 500, @errorName(err));
                return;
            };
            if (!paid) {
                try ctx.sendErrorResponse(409, 409, "订单不存在或已处理");
                return;
            }
            var d1: [128]u8 = undefined;
            const det1 = try std.fmt.bufPrint(&d1, "完成充值 {s}", .{order_no});
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "pay.complete", "payment", 0, det1, zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "已入账", .data = null });
        }

        fn wallet(ctx: *http.Context) !void {
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
            const fan_raw = ctx.queryParam("fan_id") orelse "0";
            const fan_id = std.fmt.parseInt(i64, fan_raw, 10) catch 0;
            const row_opt = self.svc.walletBalance(tid, account_id, fan_id) catch |err| {
                try ctx.sendErrorResponse(500, 500, @errorName(err));
                return;
            };
            const row = row_opt orelse {
                try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = WalletDto{ .account_id = account_id, .fan_id = fan_id, .balance = 0 } });
                return;
            };
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = WalletDto{ .account_id = row.account_id, .fan_id = row.fan_id, .balance = row.balance } });
        }

        fn orders(ctx: *http.Context) !void {
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
            var result = self.svc.listOrders(params.page, params.page_size, tid, account_id) catch |err| {
                try ctx.sendErrorResponse(500, 500, @errorName(err));
                return;
            };
            defer result.free(self.svc.allocator);
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, OrderDto, toOrderDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }

        fn withdraw(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);

            const req = ctx.bindJson(WithdrawReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            const id = self.svc.requestWithdraw(tid, req.account_id, req.fan_id, req.amount) catch |err| {
                const msg = switch (err) {
                    error.InvalidAmount => "金额必须大于 0",
                    error.WithdrawInsufficient => "余额不足",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            var d1: [128]u8 = undefined;
            const det1 = try std.fmt.bufPrint(&d1, "申请提现 {d}分", .{req.amount});
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "pay.withdraw", "payment", id, det1, zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(201, .{ .code = 0, .msg = "提现申请已提交", .data = .{ .id = id } });
        }

        fn withdraws(ctx: *http.Context) !void {
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
            var result = self.svc.listWithdraws(params.page, params.page_size, tid, account_id) catch |err| {
                try ctx.sendErrorResponse(500, 500, @errorName(err));
                return;
            };
            defer result.free(self.svc.allocator);
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, WithdrawDto, toWithdrawDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }
    };
}

pub const DefaultPaymentApi = PaymentApi(service.PaymentService, user_svc.UserService);
