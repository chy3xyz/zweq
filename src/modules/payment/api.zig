//! Admin-facing payment API — recharge orders, wallet, withdraws.
//!
//! ── 端点契约（OpenAPI 注解说明）────────────────────────────────────────
//! 库限制：zigmodu `RouteMeta` 只有 `openapi_params` 能进入 openapi.json；
//! summary 由库硬编码为 permission 码（如 payment:write），description 硬编码为
//! public/jwt，request_body 无注入通道。因此各端点的中文 summary 与 body 结构
//! 以本注释为权威契约，openapi.json 中可见的是经 openapi_params 注入的 query
//! 参数注解；端点级 permission 码即 openapi.json 中的 summary 值。
//! 统一约定：平台 JWT 鉴权（Authorization: Bearer + RBAC 权限码）；审计日志由
//! handler 自动写入；金额单位均为分；分页响应为 ruoyi 信封
//! `{code:0, msg:"ok", data:{list, total, page, pageSize}}`。
//!
//!  1. POST /api/v1/pay/recharge —— 创建充值订单（permission: payment:write）
//!     body: {account_id: i64, fan_id: i64, amount: i64, openid?: string}
//!     已配置微信支付 v3 时走 JSAPI 预下单（openid 必填），否则生成模拟订单。
//!     resp: OrderDto {id, order_no, fan_id, amount, channel, status, paid_at, created_at}
//!     400: 金额必须大于 0 / 支付配置不完整 / 微信支付下单失败
//!  2. POST /api/v1/pay/recharge/{order_no}/complete —— 完成充值订单（模拟支付回调）
//!     path: order_no: string（订单号）
//!     resp: null; 409: 订单不存在或已处理
//!  3. GET  /api/v1/pay/wallet —— 查询粉丝钱包余额（permission: payment:read）
//!     query: account_id: i64（必填）, fan_id?: i64（默认 0）
//!     resp: {account_id, fan_id, balance}（无钱包记录时 balance=0）
//!  4. GET  /api/v1/pay/orders —— 分页查询充值订单
//!     query: account_id: i64（必填）, page?（默认 1）, page_size?（默认 20，最大 100）
//!  5. POST /api/v1/pay/withdraws —— 申请提现（permission: payment:write）
//!     body: {account_id: i64, fan_id: i64, amount: i64}
//!     resp: {id}; 400: 金额必须大于 0 / 余额不足
//!  6. GET  /api/v1/pay/withdraws —— 分页查询提现记录
//!     query: account_id: i64（必填）, page?, page_size?（默认 20，最大 100）
//!  7. POST /api/v1/pay/refund —— 微信 V2 退款（permission: payment:write）
//!     body: {out_trade_no: string, out_refund_no: string, total_fee: string,
//!            refund_fee: string, refund_desc?: string（默认 ""）}
//!     需配置 wechat_pay_v2_mchid/key/cert_p12；金额字段为字符串（分）。
//!     resp: null; 400: 未配置 V2 / 微信退款失败
//!  8. POST /api/v1/pay/transfer —— 微信 V2 企业付款到零钱（permission: payment:write）
//!     body: {open_id: string, amount: i64, desc: string, partner_trade_no: string}
//!     resp: null; 400: 未配置 V2 / 企业付款失败
//!  9. POST /api/v1/pay/refund/v3 —— 微信 V3 退款（permission: payment:write）
//!     body: {out_trade_no: string, out_refund_no: string, refund_amount: i64, total_amount: i64}
//!     需配置 wechat_pay_mchid/appid/serial_no/private_key。
//!     resp: null; 400: 未配置 v3 / 微信 v3 退款失败
//! 10. POST /api/v1/pay/transfer/v3 —— 微信 V3 商家转账（permission: payment:write）
//!     body: {openid: string, amount: i64, out_batch_no: string, out_detail_no: string,
//!            remark?: string（默认 "转账"）}
//!     resp: null; 400: 未配置 v3 / 微信 v3 转账失败

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
        .amount = std.fmt.parseInt(i64, row.amount, 10) catch 0,
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
        .amount = std.fmt.parseInt(i64, row.amount, 10) catch 0,
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

// ── OpenAPI query 参数注解（经 RouteMeta.openapi_params 进入 openapi.json）──
// 库限制：summary 固定为 permission 码、description 固定为 jwt、body 无注入
// 通道，端点中文契约与 body 结构见本文件顶部注释。

/// 必填 query：账号 ID（缺失时 handler 返回 400）。
const q_acct_req = [_]http.ApiParam{
    .{ .name = "account_id", .location = .query, .param_type = "integer", .required = true, .description = "账号 ID（必填）" },
};
/// 可选 query：钱包查询的粉丝 ID（缺省按 0 处理）。
const q_fan = [_]http.ApiParam{
    .{ .name = "fan_id", .location = .query, .param_type = "integer", .required = false, .description = "粉丝 ID，默认 0" },
};
/// 可选 query：分页参数（PageParams 解析，page 最小 1，page_size 钳制 1..100）。
const q_page = [_]http.ApiParam{
    .{ .name = "page", .location = .query, .param_type = "integer", .required = false, .description = "页码，默认 1" },
    .{ .name = "page_size", .location = .query, .param_type = "integer", .required = false, .description = "每页条数，默认 20，最大 100" },
};
const q_wallet = q_acct_req ++ q_fan;
const q_acct_page = q_acct_req ++ q_page;

pub fn PaymentApi(comptime Service: type, comptime UserService: type) type {
    return struct {
        const Self = @This();
        svc: *Service,
        user_svc: *UserService,
        audit: *audit_svc.AuditService,
        default_tenant_id: i64,
        settings: *setting_store_mod.SettingStore,

        pub const module_name = "payment";
        pub const nest: []const []const u8 = &.{};
        pub const State = Self;

        pub const routes: []const http.RouteSpec(Self) = &.{
            .{ .method = .POST, .path = "pay/recharge", .handler = http.wrapHandler(Self, recharge), .meta = .{ .permission = "payment:write" } },
            .{ .method = .POST, .path = "pay/recharge/{order_no}/complete", .handler = http.wrapHandler(Self, complete), .meta = .{ .permission = "payment:write" } },
            .{ .method = .GET, .path = "pay/wallet", .handler = http.wrapHandler(Self, wallet), .meta = .{ .permission = "payment:read", .openapi_params = &q_wallet } },
            .{ .method = .GET, .path = "pay/orders", .handler = http.wrapHandler(Self, orders), .meta = .{ .permission = "payment:read", .openapi_params = &q_acct_page } },
            .{ .method = .POST, .path = "pay/withdraws", .handler = http.wrapHandler(Self, withdraw), .meta = .{ .permission = "payment:write" } },
            .{ .method = .GET, .path = "pay/withdraws", .handler = http.wrapHandler(Self, withdraws), .meta = .{ .permission = "payment:read", .openapi_params = &q_acct_page } },
            .{ .method = .POST, .path = "pay/refund", .handler = http.wrapHandler(Self, refundV2), .meta = .{ .permission = "payment:write" } },
            .{ .method = .POST, .path = "pay/transfer", .handler = http.wrapHandler(Self, transferV2), .meta = .{ .permission = "payment:write" } },
            .{ .method = .POST, .path = "pay/refund/v3", .handler = http.wrapHandler(Self, refundV3), .meta = .{ .permission = "payment:write" } },
            .{ .method = .POST, .path = "pay/transfer/v3", .handler = http.wrapHandler(Self, transferV3), .meta = .{ .permission = "payment:write" } },
        };

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
            if (cfg.mch_id.len == 0) {
                cfg.deinit(ctx.allocator);
                return null;
            }
            return cfg;
        }

        /// Read V2 merchant config (refund/transfer mTLS) from site settings.
        fn readPayV2Config(ctx: *http.Context, self: *Self, tid: i64) ?service.PayV2Config {
            var cfg = service.PayV2Config{};
            const keys = [_][]const u8{ "wechat_pay_v2_mchid", "wechat_pay_v2_key", "wechat_pay_v2_cert_p12", "wechat_pay_appid", "wechat_pay_notify_url" };
            for (keys) |key| {
                const row_opt = self.settings.get(tid, key) catch null;
                if (row_opt) |row| {
                    defer row.free(self.settings.allocator);
                    if (row.value.len == 0) continue;
                    const dup = ctx.allocator.dupe(u8, row.value) catch continue;
                    if (std.mem.eql(u8, key, "wechat_pay_v2_mchid")) {
                        cfg.mch_id = dup;
                    } else if (std.mem.eql(u8, key, "wechat_pay_v2_key")) {
                        cfg.key = dup;
                    } else if (std.mem.eql(u8, key, "wechat_pay_v2_cert_p12")) {
                        cfg.root_ca = dup;
                    } else if (std.mem.eql(u8, key, "wechat_pay_appid")) {
                        cfg.app_id = dup;
                    } else if (std.mem.eql(u8, key, "wechat_pay_notify_url")) {
                        cfg.notify_url = dup;
                    }
                }
            }
            if (cfg.mch_id.len == 0 or cfg.key.len == 0) {
                cfg.deinit(ctx.allocator);
                return null;
            }
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
            try g.post("/pay/refund", refundV2, @ptrCast(@alignCast(self)));
            try g.post("/pay/transfer", transferV2, @ptrCast(@alignCast(self)));
            try g.post("/pay/refund/v3", refundV3, @ptrCast(@alignCast(self)));
            try g.post("/pay/transfer/v3", transferV3, @ptrCast(@alignCast(self)));
        }

        fn setAuditActor(ctx: *http.Context, self: *Self) !void {
            const uid = ctx.userIdInt(i64) orelse return;
            const row_opt = self.user_svc.getUserById(uid) catch return;
            const row = row_opt orelse return;
            defer row.free(self.svc.allocator);
            try ctx.setAttr("audit_actor", row.name);
        }

        fn tenantScope(ctx: *http.Context, self: *Self) i64 {
            return mw.authTenantId(ctx) orelse self.default_tenant_id;
        }

        fn recharge(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const admin_id = ctx.userIdInt(i64) orelse return;
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
                    else => "操作失败",
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            defer row.free(self.svc.allocator);
            var d1: [128]u8 = undefined;
            const det1 = try std.fmt.bufPrint(&d1, "创建充值订单 {s} {s}分", .{ row.order_no, row.amount });
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "pay.recharge", "payment", row.id, det1, zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.okValue(toOrderDto(row));
        }

        fn complete(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const admin_id = ctx.userIdInt(i64) orelse return;
            const tid = tenantScope(ctx, self);

            const order_no = ctx.param("order_no") orelse {
                try ctx.sendErrorResponse(400, 400, "缺少订单号");
                return;
            };
            const paid = self.svc.completeRecharge(tid, order_no) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            if (!paid) {
                try ctx.sendErrorResponse(409, 409, "订单不存在或已处理");
                return;
            }
            var d1: [128]u8 = undefined;
            const det1 = try std.fmt.bufPrint(&d1, "完成充值 {s}", .{order_no});
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "pay.complete", "payment", 0, det1, zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.ok("null");
        }

        fn wallet(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
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
            const row_opt = self.svc.walletBalance(tid, account_id, fan_id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer if (row_opt) |r| r.free(self.svc.allocator);
            const row = row_opt orelse {
                try ctx.okValue(WalletDto{ .account_id = account_id, .fan_id = fan_id, .balance = 0 });
                return;
            };
            try ctx.okValue(WalletDto{ .account_id = row.account_id, .fan_id = row.fan_id, .balance = std.fmt.parseInt(i64, row.balance, 10) catch 0 });
        }

        fn orders(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
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
            var result = self.svc.listOrders(params.page, params.page_size, tid, account_id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer result.free(self.svc.allocator);
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, OrderDto, toOrderDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }

        fn withdraw(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const admin_id = ctx.userIdInt(i64) orelse return;
            const tid = tenantScope(ctx, self);

            const req = ctx.bindJson(WithdrawReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            const id = self.svc.requestWithdraw(tid, req.account_id, req.fan_id, req.amount) catch |err| {
                const msg = switch (err) {
                    error.InvalidAmount => "金额必须大于 0",
                    error.WithdrawInsufficient => "余额不足",
                    else => "操作失败",
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            var d1: [128]u8 = undefined;
            const det1 = try std.fmt.bufPrint(&d1, "申请提现 {d}分", .{req.amount});
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "pay.withdraw", "payment", id, det1, zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.okValue(.{ .id = id });
        }

        fn withdraws(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
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
            var result = self.svc.listWithdraws(params.page, params.page_size, tid, account_id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer result.free(self.svc.allocator);
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, WithdrawDto, toWithdrawDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }

        const RefundV2Req = struct {
            out_trade_no: []const u8,
            out_refund_no: []const u8,
            total_fee: []const u8,
            refund_fee: []const u8,
            refund_desc: []const u8 = "",
        };

        const TransferV2Req = struct {
            open_id: []const u8,
            amount: i64,
            desc: []const u8,
            partner_trade_no: []const u8,
        };

        const RefundV3Req = struct {
            out_trade_no: []const u8,
            out_refund_no: []const u8,
            refund_amount: i64,
            total_amount: i64,
        };

        const TransferV3Req = struct {
            openid: []const u8,
            amount: i64,
            out_batch_no: []const u8,
            out_detail_no: []const u8,
            remark: []const u8 = "转账",
        };

        fn refundV2(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const admin_id = ctx.userIdInt(i64) orelse return;
            const tid = mw.authTenantId(ctx) orelse self.default_tenant_id;
            const cfg_opt = readPayV2Config(ctx, self, tid);
            const cfg = cfg_opt orelse {
                try ctx.sendErrorResponse(400, 400, "未配置微信支付 V2（wechat_pay_v2_mchid/key/cert_p12）");
                return;
            };
            defer cfg.deinit(ctx.allocator);

            const req = ctx.bindJson(RefundV2Req) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer {
                ctx.allocator.free(req.out_trade_no);
                ctx.allocator.free(req.out_refund_no);
                ctx.allocator.free(req.total_fee);
                ctx.allocator.free(req.refund_fee);
                if (req.refund_desc.len > 0) ctx.allocator.free(req.refund_desc);
            }
            self.svc.refundV2(ctx.allocator, cfg, req.out_trade_no, req.out_refund_no, req.total_fee, req.refund_fee, req.refund_desc) catch |err| {
                const msg = switch (err) {
                    error.RefundFailed => "微信退款失败",
                    else => "操作失败",
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "payment.refund", "payment", 0, "V2 退款", zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.ok("null");
        }

        fn transferV2(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const admin_id = ctx.userIdInt(i64) orelse return;
            const tid = mw.authTenantId(ctx) orelse self.default_tenant_id;
            const cfg_opt = readPayV2Config(ctx, self, tid);
            const cfg = cfg_opt orelse {
                try ctx.sendErrorResponse(400, 400, "未配置微信支付 V2（wechat_pay_v2_mchid/key/cert_p12）");
                return;
            };
            defer cfg.deinit(ctx.allocator);

            const req = ctx.bindJson(TransferV2Req) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer {
                ctx.allocator.free(req.open_id);
                ctx.allocator.free(req.desc);
                ctx.allocator.free(req.partner_trade_no);
            }
            self.svc.transferToWallet(ctx.allocator, cfg, req.open_id, req.amount, req.desc, req.partner_trade_no) catch |err| {
                const msg = switch (err) {
                    error.TransferFailed => "企业付款失败",
                    else => "操作失败",
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "payment.transfer", "payment", 0, "企业付款到零钱", zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.ok("null");
        }

        fn refundV3(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const admin_id = ctx.userIdInt(i64) orelse return;
            const tid = mw.authTenantId(ctx) orelse self.default_tenant_id;
            const cfg_opt = readPayConfig(ctx, self, tid);
            const cfg = cfg_opt orelse {
                try ctx.sendErrorResponse(400, 400, "未配置微信支付 v3（wechat_pay_mchid/appid/serial_no/private_key）");
                return;
            };
            defer cfg.deinit(ctx.allocator);

            const req = ctx.bindJson(RefundV3Req) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer {
                ctx.allocator.free(req.out_trade_no);
                ctx.allocator.free(req.out_refund_no);
            }
            self.svc.refundV3(ctx.allocator, cfg, req.out_trade_no, req.out_refund_no, req.refund_amount, req.total_amount) catch |err| {
                const msg = switch (err) {
                    error.InvalidPayConfig => "支付配置不完整",
                    error.PrepayFailed => "微信 v3 退款失败",
                    else => "操作失败",
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "payment.refund.v3", "payment", 0, "v3 退款", zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.ok("null");
        }

        fn transferV3(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const admin_id = ctx.userIdInt(i64) orelse return;
            const tid = mw.authTenantId(ctx) orelse self.default_tenant_id;
            const cfg_opt = readPayConfig(ctx, self, tid);
            const cfg = cfg_opt orelse {
                try ctx.sendErrorResponse(400, 400, "未配置微信支付 v3（wechat_pay_mchid/appid/serial_no/private_key）");
                return;
            };
            defer cfg.deinit(ctx.allocator);

            const req = ctx.bindJson(TransferV3Req) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer {
                ctx.allocator.free(req.openid);
                ctx.allocator.free(req.out_batch_no);
                ctx.allocator.free(req.out_detail_no);
                if (req.remark.len > 0) ctx.allocator.free(req.remark);
            }
            self.svc.transferV3(ctx.allocator, cfg, req.openid, req.amount, req.out_batch_no, req.out_detail_no, req.remark) catch |err| {
                const msg = switch (err) {
                    error.InvalidPayConfig => "支付配置不完整",
                    error.PrepayFailed => "微信 v3 转账失败",
                    else => "操作失败",
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "payment.transfer.v3", "payment", 0, "v3 商家转账", zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.ok("null");
        }
    };
}

pub const DefaultPaymentApi = PaymentApi(service.PaymentService, user_svc.UserService);
