//! Admin-facing distribution API — 分销员列表 + 佣金记录 + 加盟/分佣/提现。

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const mw = @import("../../middleware/auth.zig");
const user_svc = @import("../user/service.zig");
const audit_svc = @import("../audit/service.zig");

const service = @import("service.zig");

const DistributorDto = struct {
    id: i64,
    account_id: i64,
    openid: []const u8,
    parent_openid: []const u8,
    commission_balance: i64,
    total_commission: i64,
    status: i64,
    created_at: i64,
};

fn toDto(row: service.DistributorRow) DistributorDto {
    return .{
        .id = row.id,
        .account_id = row.account_id,
        .openid = row.openid,
        .parent_openid = row.parent_openid,
        .commission_balance = std.fmt.parseInt(i64, row.commission_balance, 10) catch 0,
        .total_commission = std.fmt.parseInt(i64, row.total_commission, 10) catch 0,
        .status = row.status,
        .created_at = row.created_at,
    };
}

const JoinReq = struct {
    openid: []const u8,
    parent_openid: []const u8 = "",
};

const DistributeReq = struct {
    buyer_openid: []const u8,
    order_amount: i64,
};

const WithdrawReq = struct {
    openid: []const u8,
    amount: i64,
};

const CommissionDto = struct {
    id: i64,
    account_id: i64,
    openid: []const u8,
    source_openid: []const u8,
    level: i64,
    amount: i64,
    status: i64,
    created_at: i64,
};

fn toCommissionDto(row: service.CommissionRow) CommissionDto {
    return .{
        .id = row.id,
        .account_id = row.account_id,
        .openid = row.openid,
        .source_openid = row.source_openid,
        .level = row.level,
        .amount = std.fmt.parseInt(i64, row.amount, 10) catch 0,
        .status = row.status,
        .created_at = row.created_at,
    };
}

pub fn DistributionApi(comptime Service: type, comptime UserService: type) type {
    return struct {
        const Self = @This();
        svc: *Service,
        user_svc: *UserService,
        audit: *audit_svc.AuditService,
        default_tenant_id: i64,

        pub const module_name = "distribution";
        pub const nest: []const []const u8 = &.{};
        pub const State = Self;

        pub const routes: []const http.RouteSpec(Self) = &.{
            .{ .method = .GET, .path = "distributions", .handler = http.wrapHandler(Self, list), .meta = .{ .permission = "distribution:read" } },
            .{ .method = .GET, .path = "distributions/commissions", .handler = http.wrapHandler(Self, commissions), .meta = .{ .permission = "distribution:read" } },
            .{ .method = .POST, .path = "distributions/join", .handler = http.wrapHandler(Self, join), .meta = .{ .permission = "distribution:write" } },
            .{ .method = .POST, .path = "distributions/distribute", .handler = http.wrapHandler(Self, distribute), .meta = .{ .permission = "distribution:write" } },
            .{ .method = .POST, .path = "distributions/withdraw", .handler = http.wrapHandler(Self, withdraw), .meta = .{ .permission = "distribution:write" } },
        };

        pub fn init(svc: *Service, users: *UserService, audit: *audit_svc.AuditService, default_tenant_id: i64) Self {
            return .{ .svc = svc, .user_svc = users, .audit = audit, .default_tenant_id = default_tenant_id };
        }

        pub fn registerRoutes(self: *Self, group: *http.RouteGroup) !void {
            var g = try group.use(zigmodu.http.http_middleware.jwtAuthWithSecurity(&self.user_svc.sec.module));
            g = try g.use(mw.tokenVersionGuard(self.user_svc.sec, self.user_svc.store));
            try g.get("/distributions", list, @ptrCast(@alignCast(self)));
            try g.get("/distributions/commissions", commissions, @ptrCast(@alignCast(self)));
            try g.post("/distributions/join", join, @ptrCast(@alignCast(self)));
            try g.post("/distributions/distribute", distribute, @ptrCast(@alignCast(self)));
            try g.post("/distributions/withdraw", withdraw, @ptrCast(@alignCast(self)));
        }

        fn setAuditActor(ctx: *http.Context, self: *Self) !void {
            const uid = mw.authUserId(ctx) orelse return;
            const row_opt = self.user_svc.getUserById(uid) catch return;
            const row = row_opt orelse return;
            defer row.free(self.user_svc.store.allocator);
            try ctx.setAttr("audit_actor", row.name);
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

        fn list(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const tid = tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const keyword = ctx.queryStr("keyword", "");
            const status = ctx.queryInt(i64, "status", -1);
            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 100 });
            var result = self.svc.listDistributors(params.page, params.page_size, tid, account_id, keyword, status) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer result.free(self.svc.allocator);
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, DistributorDto, toDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }

        fn commissions(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const tid = tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const keyword = ctx.queryStr("keyword", "");
            const level = ctx.queryInt(i64, "level", -1);
            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 100 });
            var result = self.svc.listCommissions(params.page, params.page_size, tid, account_id, keyword, level) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer result.free(ctx.allocator);
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, CommissionDto, toCommissionDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }

        fn join(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const admin_id = mw.authUserId(ctx) orelse return;
            const tid = tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const req = ctx.bindJson(JoinReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer {
                ctx.allocator.free(req.openid);
                ctx.allocator.free(req.parent_openid);
            }
            self.svc.becomeDistributor(tid, account_id, req.openid, req.parent_openid) catch |err| {
                const msg = switch (err) {
                    error.AlreadyDistributor => "已是分销员",
                    error.InvalidParent => "上级分销员无效",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "distribution.join", "distributor", 0, "手动开通分销", zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(201, .{ .code = 0, .msg = "已开通", .data = null });
        }

        fn distribute(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const admin_id = mw.authUserId(ctx) orelse return;
            const tid = tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const req = ctx.bindJson(DistributeReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer ctx.allocator.free(req.buyer_openid);
            const count = self.svc.distribute(tid, account_id, req.buyer_openid, req.order_amount) catch |err| {
                try ctx.sendErrorResponse(400, 400, @errorName(err));
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "distribution.distribute", "commission_record", 0, "订单分佣", zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = .{ .count = count } });
        }

        fn withdraw(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const admin_id = mw.authUserId(ctx) orelse return;
            const tid = tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const req = ctx.bindJson(WithdrawReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer ctx.allocator.free(req.openid);
            self.svc.withdraw(tid, account_id, req.openid, req.amount) catch |err| {
                const msg = switch (err) {
                    error.NotFound => "未开通分销",
                    error.InsufficientBalance => "佣金不足",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "distribution.withdraw", "commission_record", 0, "佣金提现", zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "提现申请已提交", .data = null });
        }
    };
}

pub const DefaultDistributionApi = DistributionApi(service.DistributionService, user_svc.UserService);
