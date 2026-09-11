//! C 端场景 BFF — 签到/投票/秒杀/会员卡/分销（粉丝 JWT）。
//!
//! ── 端点契约（OpenAPI 注解说明）────────────────────────────────────────
//! 库限制：zigmodu `RouteMeta` 只有 `openapi_params` 能进入 openapi.json；
//! summary 由库硬编码为 permission 码（本模块无 permission → 模块名），
//! description 硬编码为 public/jwt，request_body 无注入通道。因此各端点的
//! 中文 summary 与 body 结构以本注释为权威契约，openapi.json 中可见的是
//! 经 openapi_params 注入的 query/path 参数注解。
//! 统一约定：粉丝 JWT 鉴权（Authorization: Bearer，handler 内 requireFanOpenid
//! 校验，catalog 标记 public 仅为跳过平台 JWT 中间件）；分页响应统一为
//! `{code:0, msg:"ok", data:{list, total, page, pageSize}}`（ruoyi 信封）。
//!
//!  1. POST /api/v1/app/checkin —— 执行每日签到
//!     body: {account_id: i64}
//!     resp: {points, fresh}（fresh=false 表示今日已签过）
//!  2. GET  /api/v1/app/checkin/records —— 分页查询我的签到记录
//!     query: account_id?, page?（默认 1）, page_size?（默认 20，最大 100）
//!     resp: data.{list: [{id, day, points, created_at}], total}
//!  3. GET  /api/v1/app/votes —— 分页查询投票活动列表
//!     query: account_id?, page?, page_size?（默认 20，最大 50）
//!  4. GET  /api/v1/app/votes/{id} —— 查询投票详情与计票结果
//!     path: id: i64（投票 ID）
//!     resp: {id, title, options_json, end_at, tally}
//!  5. POST /api/v1/app/votes/{id}/ballot —— 提交投票选票
//!     path: id: i64（投票 ID）
//!     body: {account_id: i64, option_index: i64}
//!     resp: null; 400: 您已投过票 / 投票已结束 / 选项无效
//!  6. GET  /api/v1/app/seckill/activities —— 分页查询秒杀活动列表（仅上架）
//!     query: account_id?, page?, page_size?（默认 20，最大 50）
//!  7. GET  /api/v1/app/seckill/orders —— 分页查询我的秒杀订单
//!     query: account_id?, page?, page_size?（默认 20，最大 50）
//!  8. POST /api/v1/app/seckill/activities/{id}/rush —— 参与秒杀下单
//!     path: id: i64（活动 ID）
//!     body: {account_id: i64, quantity?: i64（默认 1）}
//!     resp: {order_id}
//!  9. GET  /api/v1/app/member-card —— 查询我的会员卡
//!     query: account_id?
//!     resp: {openid, level_name, level, discount, points, total_points}（未开卡返回 null）
//! 10. POST /api/v1/app/member-card/open —— 开通会员卡
//!     body: {account_id: i64}
//!     resp: null
//! 11. GET  /api/v1/app/distribution —— 查询我的分销信息
//!     query: account_id?
//!     resp: {openid, parent_openid, commission_balance, total_commission}（未开通返回 null）
//! 12. POST /api/v1/app/distribution/join —— 申请成为分销员
//!     body: {account_id: i64, parent_openid?: string（默认 ""，上级 openid）}
//!     resp: null; 400: 您已是分销员 / 上级无效
//! 13. POST /api/v1/app/distribution/withdraw —— 申请分销佣金提现
//!     body: {account_id: i64, amount: i64}（amount 单位为分）
//!     resp: null; 400: 未开通分销 / 佣金不足 / 提现金额无效

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const fan_auth = @import("../../middleware/fan_auth.zig");
const user_svc = @import("../user/service.zig");
const checkin_svc = @import("../checkin/service.zig");
const vote_svc = @import("../vote/service.zig");
const seckill_svc = @import("../seckill/service.zig");
const member_card_svc = @import("../member_card/service.zig");
const distribution_svc = @import("../distribution/service.zig");
const module_svc = @import("../module/service.zig");

const AccountReq = struct { account_id: i64 };
const BallotReq = struct { account_id: i64, option_index: i64 };
const RushReq = struct { account_id: i64, quantity: i64 = 1 };
const JoinReq = struct { account_id: i64, parent_openid: []const u8 = "" };
const WithdrawReq = struct { account_id: i64, amount: i64 };

// ── OpenAPI query 参数注解（经 RouteMeta.openapi_params 进入 openapi.json）──
// 库限制：summary/description/body 结构无注入通道，契约见本文件顶部注释。

/// 可选 query：账号 ID（各端点 `account_id` 缺省按 0 处理）。
const q_acct = [_]http.ApiParam{
    .{ .name = "account_id", .location = .query, .param_type = "integer", .required = false, .description = "账号 ID，默认 0（默认账号）" },
};
/// 可选 query：分页参数（PageParams 解析，page 最小 1，page_size 钳制 1..100）。
const q_page100 = [_]http.ApiParam{
    .{ .name = "page", .location = .query, .param_type = "integer", .required = false, .description = "页码，默认 1" },
    .{ .name = "page_size", .location = .query, .param_type = "integer", .required = false, .description = "每页条数，默认 20，最大 100" },
};
/// 可选 query：分页参数（投票/秒杀端点，page_size 钳制 1..50）。
const q_page50 = [_]http.ApiParam{
    .{ .name = "page", .location = .query, .param_type = "integer", .required = false, .description = "页码，默认 1" },
    .{ .name = "page_size", .location = .query, .param_type = "integer", .required = false, .description = "每页条数，默认 20，最大 50" },
};
const q_acct_page100 = q_acct ++ q_page100;
const q_acct_page50 = q_acct ++ q_page50;

pub fn FanSceneApi(
    comptime UserService: type,
    comptime CheckinService: type,
    comptime VoteService: type,
    comptime SeckillService: type,
    comptime MemberCardService: type,
    comptime DistributionService: type,
    comptime ModuleService: type,
) type {
    return struct {
        const Self = @This();
        user_svc: *UserService,
        checkin_svc: *CheckinService,
        vote_svc: *VoteService,
        seckill_svc: *SeckillService,
        member_card_svc: *MemberCardService,
        distribution_svc: *DistributionService,
        module_svc: *ModuleService,
        default_tenant_id: i64,

        pub const module_name = "app_fan_scene";
        pub const nest: []const []const u8 = &.{};
        pub const State = Self;

        pub const routes: []const http.RouteSpec(Self) = &.{
            .{ .method = .POST, .path = "app/checkin", .handler = http.wrapHandler(Self, doCheckin), .meta = .{ .auth = .public } },
            .{ .method = .GET, .path = "app/checkin/records", .handler = http.wrapHandler(Self, checkinRecords), .meta = .{ .auth = .public, .openapi_params = &q_acct_page100 } },
            .{ .method = .GET, .path = "app/votes", .handler = http.wrapHandler(Self, listVotes), .meta = .{ .auth = .public, .openapi_params = &q_acct_page50 } },
            .{ .method = .GET, .path = "app/votes/{id}", .handler = http.wrapHandler(Self, voteDetail), .meta = .{ .auth = .public } },
            .{ .method = .POST, .path = "app/votes/{id}/ballot", .handler = http.wrapHandler(Self, voteBallot), .meta = .{ .auth = .public } },
            .{ .method = .GET, .path = "app/seckill/activities", .handler = http.wrapHandler(Self, listSeckill), .meta = .{ .auth = .public, .openapi_params = &q_acct_page50 } },
            .{ .method = .GET, .path = "app/seckill/orders", .handler = http.wrapHandler(Self, listSeckillOrders), .meta = .{ .auth = .public, .openapi_params = &q_acct_page50 } },
            .{ .method = .POST, .path = "app/seckill/activities/{id}/rush", .handler = http.wrapHandler(Self, seckillRush), .meta = .{ .auth = .public } },
            .{ .method = .GET, .path = "app/member-card", .handler = http.wrapHandler(Self, memberCardView), .meta = .{ .auth = .public, .openapi_params = &q_acct } },
            .{ .method = .POST, .path = "app/member-card/open", .handler = http.wrapHandler(Self, memberCardOpen), .meta = .{ .auth = .public } },
            .{ .method = .GET, .path = "app/distribution", .handler = http.wrapHandler(Self, distributionView), .meta = .{ .auth = .public, .openapi_params = &q_acct } },
            .{ .method = .POST, .path = "app/distribution/join", .handler = http.wrapHandler(Self, distributionJoin), .meta = .{ .auth = .public } },
            .{ .method = .POST, .path = "app/distribution/withdraw", .handler = http.wrapHandler(Self, distributionWithdraw), .meta = .{ .auth = .public } },
        };

        pub fn init(
            users: *UserService,
            checkin: *CheckinService,
            vote: *VoteService,
            seckill: *SeckillService,
            member_card: *MemberCardService,
            distribution: *DistributionService,
            mods: *ModuleService,
            default_tenant_id: i64,
        ) Self {
            return .{
                .user_svc = users,
                .checkin_svc = checkin,
                .vote_svc = vote,
                .seckill_svc = seckill,
                .member_card_svc = member_card,
                .distribution_svc = distribution,
                .module_svc = mods,
                .default_tenant_id = default_tenant_id,
            };
        }

        fn tenantScope(ctx: *http.Context, self: *Self) i64 {
            _ = ctx;
            return self.default_tenant_id;
        }

        fn doCheckin(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const openid = fan_auth.requireFanOpenid(ctx, self.user_svc) catch {
                try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                return;
            };
            defer ctx.allocator.free(openid);
            const tid = tenantScope(ctx, self);
            const req = ctx.bindJson(AccountReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            const cfg = self.module_svc.getConfig(ctx.allocator, tid, req.account_id, "checkin") catch null;
            defer if (cfg) |x| ctx.allocator.free(x);
            const points = std.fmt.parseInt(i64, std.mem.trim(u8, cfg orelse "", " \t"), 10) catch 0;
            const day = @divTrunc(zigmodu.time.wallClockSeconds(self.checkin_svc.io), 86400);
            const fresh = self.checkin_svc.checkin(tid, req.account_id, openid, day, points) catch {
                try ctx.sendErrorResponse(500, 500, "签到失败");
                return;
            };
            try ctx.okValue(.{ .points = points, .fresh = fresh });
        }

        fn checkinRecords(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const openid = fan_auth.requireFanOpenid(ctx, self.user_svc) catch {
                try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                return;
            };
            defer ctx.allocator.free(openid);
            const tid = tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 100 });
            var result = self.checkin_svc.list(params.page, params.page_size, tid, account_id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer result.free(self.checkin_svc.allocator);
            const CheckinDto = struct { id: i64, day: i64, points: i64, created_at: i64 };
            var out = std.ArrayList(CheckinDto).empty;
            defer out.deinit(ctx.allocator);
            for (result.items) |row| {
                if (!std.mem.eql(u8, row.openid, openid)) continue;
                try out.append(ctx.allocator, .{
                    .id = row.id,
                    .day = row.checkin_day,
                    .points = row.points,
                    .created_at = row.created_at,
                });
            }
            try ctx.okValue(.{ .list = out.items, .total = @as(i64, @intCast(out.items.len)) });
        }

        fn listVotes(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = fan_auth.requireFanOpenid(ctx, self.user_svc) catch {
                try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                return;
            };
            const tid = tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 50 });
            var result = self.vote_svc.listVotes(params.page, params.page_size, tid, account_id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer result.free(self.vote_svc.allocator);
            try zigmodu.http.sendPaged(ctx, result.items, @intCast(result.total), params, .ruoyi);
        }

        fn voteDetail(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = fan_auth.requireFanOpenid(ctx, self.user_svc) catch {
                try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                return;
            };
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效 ID");
                return;
            };
            const row_opt = self.vote_svc.getVote(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            const row = row_opt orelse {
                try ctx.sendErrorResponse(404, 404, "投票不存在");
                return;
            };
            defer row.free(self.vote_svc.allocator);
            const tally = self.vote_svc.tally(ctx.allocator, id) catch {
                try ctx.sendErrorResponse(500, 500, "计票失败");
                return;
            };
            defer ctx.allocator.free(tally);
            try ctx.okValue(.{
                .id = row.id,
                .title = row.title,
                .options_json = row.options_json,
                .end_at = row.end_at,
                .tally = tally,
            });
        }

        fn voteBallot(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const openid = fan_auth.requireFanOpenid(ctx, self.user_svc) catch {
                try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                return;
            };
            defer ctx.allocator.free(openid);
            const tid = tenantScope(ctx, self);
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效 ID");
                return;
            };
            const req = ctx.bindJson(BallotReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            self.vote_svc.vote(tid, req.account_id, openid, id, req.option_index) catch |err| {
                const msg = switch (err) {
                    error.AlreadyVoted => "您已投过票",
                    error.Ended => "投票已结束",
                    error.InvalidOption => "选项无效",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            try ctx.ok("null");
        }

        fn listSeckill(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = fan_auth.requireFanOpenid(ctx, self.user_svc) catch {
                try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                return;
            };
            const tid = tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 50 });
            // C 端只暴露上架活动（下架的由 latestActivity / rush 二次拦截）。
            var result = self.seckill_svc.listActivities(params.page, params.page_size, tid, account_id, "", 1) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer result.free(self.seckill_svc.allocator);
            try zigmodu.http.sendPaged(ctx, result.items, @intCast(result.total), params, .ruoyi);
        }

        fn listSeckillOrders(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const openid = fan_auth.requireFanOpenid(ctx, self.user_svc) catch {
                try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                return;
            };
            defer ctx.allocator.free(openid);
            const tid = tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 50 });
            var result = self.seckill_svc.listOrders(params.page, params.page_size, tid, account_id, openid, "") catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer result.free(self.seckill_svc.allocator);
            try zigmodu.http.sendPaged(ctx, result.items, @intCast(result.total), params, .ruoyi);
        }

        fn seckillRush(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const openid = fan_auth.requireFanOpenid(ctx, self.user_svc) catch {
                try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                return;
            };
            defer ctx.allocator.free(openid);
            const tid = tenantScope(ctx, self);
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效 ID");
                return;
            };
            const req = ctx.bindJson(RushReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            const order_id = self.seckill_svc.rush(tid, req.account_id, openid, id, req.quantity) catch |err| {
                try ctx.sendErrorResponse(400, 400, @errorName(err));
                return;
            };
            try ctx.okValue(.{ .order_id = order_id });
        }

        fn memberCardView(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const openid = fan_auth.requireFanOpenid(ctx, self.user_svc) catch {
                try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                return;
            };
            defer ctx.allocator.free(openid);
            const tid = tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const view_opt = self.member_card_svc.view(tid, account_id, openid) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            const view = view_opt orelse {
                try ctx.ok("null");
                return;
            };
            defer view.free(self.member_card_svc.allocator);
            try ctx.okValue(.{
                .openid = view.openid,
                .level_name = view.level_name,
                .level = view.level,
                .discount = view.discount,
                .points = view.points,
                .total_points = view.total_points,
            });
        }

        fn memberCardOpen(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const openid = fan_auth.requireFanOpenid(ctx, self.user_svc) catch {
                try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                return;
            };
            defer ctx.allocator.free(openid);
            const tid = tenantScope(ctx, self);
            const req = ctx.bindJson(AccountReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            self.member_card_svc.openCard(tid, req.account_id, openid) catch |err| {
                try ctx.sendErrorResponse(400, 400, @errorName(err));
                return;
            };
            try ctx.ok("null");
        }

        fn distributionView(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const openid = fan_auth.requireFanOpenid(ctx, self.user_svc) catch {
                try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                return;
            };
            defer ctx.allocator.free(openid);
            const tid = tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const row_opt = self.distribution_svc.getDistributor(tid, account_id, openid) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            const row = row_opt orelse {
                try ctx.ok("null");
                return;
            };
            defer row.free(self.distribution_svc.allocator);
            try ctx.okValue(.{
                .openid = row.openid,
                .parent_openid = row.parent_openid,
                .commission_balance = row.commission_balance,
                .total_commission = row.total_commission,
            });
        }

        fn distributionJoin(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const openid = fan_auth.requireFanOpenid(ctx, self.user_svc) catch {
                try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                return;
            };
            defer ctx.allocator.free(openid);
            const tid = tenantScope(ctx, self);
            const req = ctx.bindJson(JoinReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer if (req.parent_openid.len > 0) ctx.allocator.free(req.parent_openid);
            self.distribution_svc.becomeDistributor(tid, req.account_id, openid, req.parent_openid) catch |err| {
                const msg = switch (err) {
                    error.AlreadyDistributor => "您已是分销员",
                    error.InvalidParent => "上级无效",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            try ctx.ok("null");
        }

        fn distributionWithdraw(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const openid = fan_auth.requireFanOpenid(ctx, self.user_svc) catch {
                try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                return;
            };
            defer ctx.allocator.free(openid);
            const tid = tenantScope(ctx, self);
            const req = ctx.bindJson(WithdrawReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            self.distribution_svc.withdraw(tid, req.account_id, openid, req.amount) catch |err| {
                const msg = switch (err) {
                    error.NotFound => "未开通分销",
                    error.InsufficientBalance => "佣金不足",
                    error.InvalidInput => "提现金额无效",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            try ctx.ok("null");
        }
    };
}

pub const DefaultFanSceneApi = FanSceneApi(
    user_svc.UserService,
    checkin_svc.CheckinService,
    vote_svc.VoteService,
    seckill_svc.SeckillService,
    member_card_svc.MemberCardService,
    distribution_svc.DistributionService,
    module_svc.ModuleService,
);
