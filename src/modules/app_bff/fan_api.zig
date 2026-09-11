//! 小程序 C 端 BFF — 粉丝 JWT 鉴权，聚合积分/券/抽奖等场景接口。
//!
//! ── 端点契约（OpenAPI 注解说明）────────────────────────────────────────
//! 库限制：zigmodu `RouteMeta` 只有 `openapi_params` 能进入 openapi.json；
//! summary 由库硬编码为 permission 码（本模块无 permission → 模块名），
//! description 硬编码为 public/jwt，request_body 无注入通道。因此各端点的
//! 中文 summary 与 body 结构以本注释为权威契约，openapi.json 中可见的是
//! 经 openapi_params 注入的 query/path 参数注解。
//! 统一约定：粉丝 JWT 鉴权（Authorization: Bearer，handler 内 requireFanOpenid
//! 校验，catalog 标记 public 仅为跳过平台 JWT 中间件）；分页响应统一为
//! `{list, total, page, pageSize}`；金额/积分单位均为分。
//!
//!  1. GET  /api/v1/app/fan/profile —— 查询粉丝资料
//!     query: account_id?: i64（默认 0，默认账号）
//!     resp: {openid, nickname, avatar, points}
//!  2. GET  /api/v1/app/points/products —— 分页查询积分商品列表（仅上架）
//!     query: account_id?, page?（默认 1）, page_size?（默认 20，最大 100）
//!     resp: {list: [{id, account_id, name, points, stock}], total, page, pageSize}
//!  3. POST /api/v1/app/points/redeem —— 兑换积分商品
//!     body: {account_id: i64, product_id: i64}
//!     resp: {order_id}; 400: 库存不足 / 积分不足 / 商品不存在
//!  4. GET  /api/v1/app/points/orders —— 查询我的积分兑换订单
//!     query: account_id?
//!     resp: [{id, product_id, product_name, points_spent, status}]
//!  5. GET  /api/v1/app/coupons —— 分页查询可领取优惠券列表（仅上架）
//!     query: account_id?, page?, page_size?（默认 20，最大 100）
//!     resp: {list: [{id, account_id, title, amount, min_amount, total, per_user, start_at, end_at}], total, page, pageSize}
//!  6. POST /api/v1/app/coupons/{id}/claim —— 领取优惠券
//!     path: id: i64（券模板 ID）
//!     body: {account_id: i64}
//!     resp: {code}; 400: 券已领完 / 已达领取上限 / 活动未开始 / 活动已结束 / 券不存在
//!  7. GET  /api/v1/app/my-coupons —— 分页查询我的优惠券
//!     query: account_id?, page?, page_size?（默认 20，最大 100）
//!     resp: {list: [{id, coupon_id, code, status, created_at, title, amount, min_amount}], total, page, pageSize}
//!  8. GET  /api/v1/app/lucky-draw/records —— 分页查询我的抽奖记录
//!     query: account_id?, page?, page_size?（默认 20，最大 100）
//!     resp: {list: [{id, prize_name, points, created_at}], total, page, pageSize}
//!  9. GET  /api/v1/app/lucky-draw/config —— 查询抽奖配置
//!     query: account_id?
//!     resp: {cost, daily_limit, prize_count}
//! 10. POST /api/v1/app/lucky-draw/draw —— 执行抽奖
//!     body: {account_id: i64}
//!     resp: {prize_name, points}; 400: 今日抽奖次数已用完
//! 11. GET  /api/v1/app/wallet —— 查询 C 端钱包余额
//!     query: account_id?
//!     resp: {balance: i64}（分；无钱包记录时返回 0）

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const fan_auth = @import("../../middleware/fan_auth.zig");
const user_svc = @import("../user/service.zig");
const member_persist = @import("../member/persistence.zig");
const points_svc = @import("../points/service.zig");
const coupon_svc = @import("../coupon/service.zig");
const lucky_draw_svc = @import("../lucky_draw/service.zig");
const module_svc = @import("../module/service.zig");
const payment_service = @import("../payment/service.zig");

const FanProfileDto = struct {
    openid: []const u8,
    nickname: []const u8,
    avatar: []const u8,
    points: i64,
};

const PointsProductDto = struct {
    id: i64,
    account_id: i64,
    name: []const u8,
    points: i64,
    stock: i64,
};

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
};

const CouponUserDto = struct {
    id: i64,
    coupon_id: i64,
    code: []const u8,
    status: []const u8,
    created_at: i64,
};

const CouponUserDtoEx = struct {
    id: i64,
    coupon_id: i64,
    code: []const u8,
    status: []const u8,
    created_at: i64,
    title: []const u8,
    amount: i64,
    min_amount: i64,
};

const DrawRecordDto = struct {
    id: i64,
    prize_name: []const u8,
    points: i64,
    created_at: i64,
};

const RedeemReq = struct {
    account_id: i64,
    product_id: i64,
};

const ClaimReq = struct {
    account_id: i64,
};

const DrawReq = struct {
    account_id: i64,
};

const DrawConfigDto = struct {
    cost: i64,
    daily_limit: i64,
    prize_count: i64,
};

// ── OpenAPI query 参数注解（经 RouteMeta.openapi_params 进入 openapi.json）──
// 库限制：summary/description/body 结构无注入通道，契约见本文件顶部注释。

/// 可选 query：账号 ID（各端点 `account_id` 缺省按 0 处理）。
const q_acct = [_]http.ApiParam{
    .{ .name = "account_id", .location = .query, .param_type = "integer", .required = false, .description = "账号 ID，默认 0（默认账号）" },
};
/// 可选 query：分页参数（PageParams 解析，page 最小 1，page_size 钳制 1..100）。
const q_page = [_]http.ApiParam{
    .{ .name = "page", .location = .query, .param_type = "integer", .required = false, .description = "页码，默认 1" },
    .{ .name = "page_size", .location = .query, .param_type = "integer", .required = false, .description = "每页条数，默认 20，最大 100" },
};
const q_acct_page = q_acct ++ q_page;

const PointsOrderDto = struct {
    id: i64,
    product_id: i64,
    product_name: []const u8,
    points_spent: i64,
    status: []const u8,
};

pub fn FanAppApi(
    comptime UserService: type,
    comptime FanStore: type,
    comptime PointsService: type,
    comptime CouponService: type,
    comptime LuckyDrawService: type,
    comptime ModuleService: type,
    comptime PaymentService: type,
) type {
    return struct {
        const Self = @This();
        user_svc: *UserService,
        fan_store: *FanStore,
        points_svc: *PointsService,
        coupon_svc: *CouponService,
        lucky_draw_svc: *LuckyDrawService,
        module_svc: *ModuleService,
        payment_svc: *PaymentService,
        default_tenant_id: i64,

        pub const module_name = "app_fan";
        pub const nest: []const []const u8 = &.{};
        pub const State = Self;

        pub const routes: []const http.RouteSpec(Self) = &.{
            .{ .method = .GET, .path = "app/fan/profile", .handler = http.wrapHandler(Self, fanProfile), .meta = .{ .auth = .public, .openapi_params = &q_acct } },
            .{ .method = .GET, .path = "app/points/products", .handler = http.wrapHandler(Self, listPointsProducts), .meta = .{ .auth = .public, .openapi_params = &q_acct_page } },
            .{ .method = .POST, .path = "app/points/redeem", .handler = http.wrapHandler(Self, redeemPoints), .meta = .{ .auth = .public } },
            .{ .method = .GET, .path = "app/points/orders", .handler = http.wrapHandler(Self, listPointsOrders), .meta = .{ .auth = .public, .openapi_params = &q_acct } },
            .{ .method = .GET, .path = "app/coupons", .handler = http.wrapHandler(Self, listCoupons), .meta = .{ .auth = .public, .openapi_params = &q_acct_page } },
            .{ .method = .POST, .path = "app/coupons/{id}/claim", .handler = http.wrapHandler(Self, claimCoupon), .meta = .{ .auth = .public } },
            .{ .method = .GET, .path = "app/my-coupons", .handler = http.wrapHandler(Self, myCoupons), .meta = .{ .auth = .public, .openapi_params = &q_acct_page } },
            .{ .method = .GET, .path = "app/lucky-draw/records", .handler = http.wrapHandler(Self, listDrawRecords), .meta = .{ .auth = .public, .openapi_params = &q_acct_page } },
            .{ .method = .GET, .path = "app/lucky-draw/config", .handler = http.wrapHandler(Self, luckyDrawConfig), .meta = .{ .auth = .public, .openapi_params = &q_acct } },
            .{ .method = .POST, .path = "app/lucky-draw/draw", .handler = http.wrapHandler(Self, draw), .meta = .{ .auth = .public } },
            .{ .method = .GET, .path = "app/wallet", .handler = http.wrapHandler(Self, walletBalance), .meta = .{ .auth = .public, .openapi_params = &q_acct } },
        };

        pub fn init(
            users: *UserService,
            fans: *FanStore,
            points: *PointsService,
            coupons: *CouponService,
            lucky: *LuckyDrawService,
            mods: *ModuleService,
            payments: *PaymentService,
            default_tenant_id: i64,
        ) Self {
            return .{
                .user_svc = users,
                .fan_store = fans,
                .points_svc = points,
                .coupon_svc = coupons,
                .lucky_draw_svc = lucky,
                .module_svc = mods,
                .payment_svc = payments,
                .default_tenant_id = default_tenant_id,
            };
        }

        pub fn registerRoutes(self: *Self, group: *http.RouteGroup) !void {
            try group.get("/app/fan/profile", fanProfile, @ptrCast(@alignCast(self)));
            try group.get("/app/points/products", listPointsProducts, @ptrCast(@alignCast(self)));
            try group.post("/app/points/redeem", redeemPoints, @ptrCast(@alignCast(self)));
            try group.get("/app/points/orders", listPointsOrders, @ptrCast(@alignCast(self)));
            try group.get("/app/coupons", listCoupons, @ptrCast(@alignCast(self)));
            try group.post("/app/coupons/{id}/claim", claimCoupon, @ptrCast(@alignCast(self)));
            try group.get("/app/my-coupons", myCoupons, @ptrCast(@alignCast(self)));
            try group.get("/app/lucky-draw/records", listDrawRecords, @ptrCast(@alignCast(self)));
            try group.get("/app/lucky-draw/config", luckyDrawConfig, @ptrCast(@alignCast(self)));
            try group.post("/app/lucky-draw/draw", draw, @ptrCast(@alignCast(self)));
        }

        fn tenantScope(ctx: *http.Context, self: *Self) i64 {
            _ = ctx;
            return self.default_tenant_id;
        }

        fn fanProfile(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const openid_owned = fan_auth.requireFanOpenid(ctx, self.user_svc) catch {
                try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                return;
            };
            defer ctx.allocator.free(openid_owned);
            const tid = tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const fan_opt = self.fan_store.getByOpenid(tid, account_id, openid_owned) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            const fan = fan_opt orelse {
                try ctx.sendErrorResponse(404, 404, "粉丝不存在");
                return;
            };
            defer fan.free(self.fan_store.allocator);
            try ctx.okValue(FanProfileDto{
                .openid = fan.openid,
                .nickname = fan.nickname,
                .avatar = fan.avatar,
                .points = fan.points,
            });
        }

        fn listPointsProducts(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = fan_auth.requireFanOpenid(ctx, self.user_svc) catch {
                try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                return;
            };
            const tid = tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 100 });
            // C 端只暴露上架商品。
            var result = self.points_svc.listProducts(params.page, params.page_size, tid, account_id, "", 1) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer result.free(self.points_svc.allocator);
            const dtos = try ctx.allocator.alloc(PointsProductDto, result.items.len);
            defer ctx.allocator.free(dtos);
            for (result.items, 0..) |row, i| {
                dtos[i] = .{
                    .id = row.id,
                    .account_id = row.account_id,
                    .name = row.name,
                    .points = row.points,
                    .stock = row.stock,
                };
            }
            try ctx.okValue(.{
                .list = dtos,
                .total = result.total,
                .page = params.page,
                .pageSize = params.page_size,
            });
        }

        fn redeemPoints(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const openid_owned = fan_auth.requireFanOpenid(ctx, self.user_svc) catch {
                try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                return;
            };
            defer ctx.allocator.free(openid_owned);
            const tid = tenantScope(ctx, self);
            const req = ctx.bindJson(RedeemReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            const order_id = self.points_svc.redeem(tid, req.account_id, openid_owned, req.product_id) catch |err| {
                const msg = switch (err) {
                    error.OutOfStock => "库存不足",
                    error.InsufficientPoints => "积分不足",
                    error.ProductNotFound => "商品不存在",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            try ctx.okValue(.{ .order_id = order_id });
        }

        fn listPointsOrders(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const openid_owned = fan_auth.requireFanOpenid(ctx, self.user_svc) catch {
                try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                return;
            };
            defer ctx.allocator.free(openid_owned);
            const tid = tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const rows = self.points_svc.listOrders(tid, account_id, openid_owned) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer {
                for (rows) |r| r.free(ctx.allocator);
                ctx.allocator.free(rows);
            }
            const dtos = try ctx.allocator.alloc(PointsOrderDto, rows.len);
            defer ctx.allocator.free(dtos);
            for (rows, 0..) |row, i| {
                dtos[i] = .{
                    .id = row.id,
                    .product_id = row.product_id,
                    .product_name = row.product_name,
                    .points_spent = row.points_spent,
                    .status = row.status,
                };
            }
            try ctx.okValue(dtos);
        }

        fn listCoupons(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = fan_auth.requireFanOpenid(ctx, self.user_svc) catch {
                try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                return;
            };
            const tid = tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 100 });
            // C 端只暴露上架券。
            var result = self.coupon_svc.listCoupons(params.page, params.page_size, tid, account_id, "", 1) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer result.free(self.coupon_svc.allocator);
            const dtos = try ctx.allocator.alloc(CouponDto, result.items.len);
            defer ctx.allocator.free(dtos);
            for (result.items, 0..) |row, i| {
                dtos[i] = .{
                    .id = row.id,
                    .account_id = row.account_id,
                    .title = row.title,
                    .amount = std.fmt.parseInt(i64, row.amount, 10) catch 0,
                    .min_amount = std.fmt.parseInt(i64, row.min_amount, 10) catch 0,
                    .total = row.total,
                    .per_user = row.per_user,
                    .start_at = row.start_at,
                    .end_at = row.end_at,
                };
            }
            try ctx.okValue(.{
                .list = dtos,
                .total = result.total,
                .page = params.page,
                .pageSize = params.page_size,
            });
        }

        fn claimCoupon(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const openid_owned = fan_auth.requireFanOpenid(ctx, self.user_svc) catch {
                try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                return;
            };
            defer ctx.allocator.free(openid_owned);
            const tid = tenantScope(ctx, self);
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的券 ID");
                return;
            };
            const req = ctx.bindJson(ClaimReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            const code = self.coupon_svc.claimCoupon(ctx.allocator, tid, req.account_id, openid_owned, id) catch |err| {
                const msg = switch (err) {
                    error.OutOfStock => "券已领完",
                    error.LimitReached => "已达领取上限",
                    error.NotStarted => "活动未开始",
                    error.Expired => "活动已结束",
                    error.NotFound => "券不存在",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            defer ctx.allocator.free(code);
            try ctx.okValue(.{ .code = code });
        }

        fn myCoupons(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const openid_owned = fan_auth.requireFanOpenid(ctx, self.user_svc) catch {
                try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                return;
            };
            defer ctx.allocator.free(openid_owned);
            const tid = tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 100 });
            var result = self.coupon_svc.listUserCoupons(params.page, params.page_size, tid, account_id, openid_owned, "", "") catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer result.free(self.coupon_svc.allocator);
            var tmp_coupons = std.ArrayList(coupon_svc.CouponRow).empty;
            defer tmp_coupons.deinit(ctx.allocator);
            const dtos = try ctx.allocator.alloc(CouponUserDtoEx, result.items.len);
            defer ctx.allocator.free(dtos);
            for (result.items, 0..) |row, i| {
                var title: []const u8 = "";
                var amount: i64 = 0;
                var min_amount: i64 = 0;
                const c_opt = self.coupon_svc.getCoupon(row.coupon_id) catch null;
                if (c_opt) |c| {
                    try tmp_coupons.append(ctx.allocator, c);
                    title = c.title;
                    amount = std.fmt.parseInt(i64, c.amount, 10) catch 0;
                    min_amount = std.fmt.parseInt(i64, c.min_amount, 10) catch 0;
                }
                dtos[i] = .{
                    .id = row.id,
                    .coupon_id = row.coupon_id,
                    .code = row.code,
                    .status = row.status,
                    .created_at = row.created_at,
                    .title = title,
                    .amount = amount,
                    .min_amount = min_amount,
                };
            }
            try ctx.okValue(.{
                .list = dtos,
                .total = result.total,
                .page = params.page,
                .pageSize = params.page_size,
            });
            // jsonStruct 已完成，释放关联的券模板行（内部 owned 字符串）
            for (tmp_coupons.items) |c| c.free(self.coupon_svc.allocator);
        }

        fn luckyDrawConfig(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = fan_auth.requireFanOpenid(ctx, self.user_svc) catch {
                try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                return;
            };
            const tid = tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const cfg_json = self.module_svc.getConfig(ctx.allocator, tid, account_id, "lucky_draw") catch null;
            const cfg = self.lucky_draw_svc.parseConfig(ctx.allocator, cfg_json orelse "");
            defer cfg.free(ctx.allocator);
            try ctx.okValue(DrawConfigDto{
                .cost = cfg.cost,
                .daily_limit = cfg.daily_limit,
                .prize_count = @intCast(cfg.prizes.len),
            });
        }

        fn listDrawRecords(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const openid_owned = fan_auth.requireFanOpenid(ctx, self.user_svc) catch {
                try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                return;
            };
            defer ctx.allocator.free(openid_owned);
            const tid = tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 100 });
            var result = self.lucky_draw_svc.list(params.page, params.page_size, tid, account_id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer result.free(self.lucky_draw_svc.allocator);
            var dtos = std.ArrayList(DrawRecordDto).empty;
            defer dtos.deinit(ctx.allocator);
            for (result.items) |row| {
                if (!std.mem.eql(u8, row.openid, openid_owned)) continue;
                try dtos.append(ctx.allocator, .{
                    .id = row.id,
                    .prize_name = row.prize_name,
                    .points = row.points,
                    .created_at = row.created_at,
                });
            }
            try ctx.okValue(.{
                .list = try dtos.toOwnedSlice(ctx.allocator),
                .total = @as(i64, @intCast(dtos.items.len)),
                .page = params.page,
                .pageSize = params.page_size,
            });
        }

        fn draw(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const openid_owned = fan_auth.requireFanOpenid(ctx, self.user_svc) catch {
                try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                return;
            };
            defer ctx.allocator.free(openid_owned);
            const tid = tenantScope(ctx, self);
            const req = ctx.bindJson(DrawReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            const cfg_json = self.module_svc.getConfig(ctx.allocator, tid, req.account_id, "lucky_draw") catch null;
            const cfg = self.lucky_draw_svc.parseConfig(ctx.allocator, cfg_json orelse "");
            defer cfg.free(ctx.allocator);
            const result = self.lucky_draw_svc.draw(ctx.allocator, tid, req.account_id, openid_owned, &cfg) catch |err| {
                const msg = switch (err) {
                    error.DailyLimit => "今日抽奖次数已用完",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            defer ctx.allocator.free(result.prize_name);
            try ctx.okValue(.{
                .prize_name = result.prize_name,
                .points = result.points,
            });
        }

        /// C 端钱包余额查询（粉丝 JWT，openid → fan_id → wallet）。
        fn walletBalance(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const openid_owned = fan_auth.requireFanOpenid(ctx, self.user_svc) catch {
                try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                return;
            };
            defer ctx.allocator.free(openid_owned);
            const tid = tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const fan_opt = self.fan_store.getByOpenid(tid, account_id, openid_owned) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            const fan = fan_opt orelse {
                try ctx.sendErrorResponse(404, 404, "粉丝不存在");
                return;
            };
            defer fan.free(self.fan_store.allocator);
            const wallet_opt = self.payment_svc.walletBalance(tid, account_id, fan.id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            const wallet = wallet_opt orelse {
                try ctx.okValue(.{ .balance = 0 });
                return;
            };
            defer wallet.free(self.payment_svc.allocator);
            const balance = std.fmt.parseInt(i64, wallet.balance, 10) catch 0;
            try ctx.okValue(.{ .balance = balance });
        }
    };
}

pub const DefaultFanAppApi = FanAppApi(
    user_svc.UserService,
    member_persist.FanStore,
    points_svc.PointsService,
    coupon_svc.CouponService,
    lucky_draw_svc.DrawService,
    module_svc.ModuleService,
    payment_service.PaymentService,
);
