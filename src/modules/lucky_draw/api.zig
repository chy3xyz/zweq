//! Admin-facing lucky_draw API — 中奖记录 + 手动抽奖。
//! 奖品配置复用 module 模块的 per-account config API
//! （GET/PUT /api/v1/accounts/{id}/modules/lucky_draw/config）。

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const mw = @import("../../middleware/auth.zig");
const user_svc = @import("../user/service.zig");
const audit_svc = @import("../audit/service.zig");

const service = @import("service.zig");

const RecordDto = struct {
    id: i64,
    account_id: i64,
    openid: []const u8,
    prize_name: []const u8,
    points: i64,
    created_at: i64,
};

fn toDto(row: service.DrawRecordRow) RecordDto {
    return .{
        .id = row.id,
        .account_id = row.account_id,
        .openid = row.openid,
        .prize_name = row.prize_name,
        .points = row.points,
        .created_at = row.created_at,
    };
}

const DrawReq = struct {
    account_id: i64,
    openid: []const u8,
    config: []const u8 = "",
};

pub fn LuckyDrawApi(comptime Service: type, comptime UserService: type) type {
    return struct {
        const Self = @This();
        svc: *Service,
        user_svc: *UserService,
        audit: *audit_svc.AuditService,
        default_tenant_id: i64,

        pub const module_name = "lucky_draw";
        pub const nest: []const []const u8 = &.{};
        pub const State = Self;

        pub const routes: []const http.RouteSpec(Self) = &.{
            .{ .method = .GET, .path = "lucky-draw/records", .handler = http.wrapHandler(Self, list), .meta = .{ .permission = "lucky_draw:read" } },
            .{ .method = .POST, .path = "lucky-draw/draw", .handler = http.wrapHandler(Self, draw), .meta = .{ .permission = "lucky_draw:write" } },
        };

        pub fn init(svc: *Service, users: *UserService, audit: *audit_svc.AuditService, default_tenant_id: i64) Self {
            return .{ .svc = svc, .user_svc = users, .audit = audit, .default_tenant_id = default_tenant_id };
        }

        pub fn registerRoutes(self: *Self, group: *http.RouteGroup) !void {
            var g = try group.use(zigmodu.http.http_middleware.jwtAuthWithSecurity(&self.user_svc.sec.module));
            g = try g.use(mw.tokenVersionGuard(self.user_svc.sec, self.user_svc.store));
            try g.get("/lucky-draw/records", list, @ptrCast(@alignCast(self)));
            try g.post("/lucky-draw/draw", draw, @ptrCast(@alignCast(self)));
        }

        /// Sets the `audit_actor` context attribute from the authenticated user.
        fn setAuditActor(ctx: *http.Context, self: *Self) !void {
            const uid = ctx.userIdInt(i64) orelse return;
            const row_opt = self.user_svc.getUserById(uid) catch return;
            const row = row_opt orelse return;
            defer row.free(self.user_svc.store.allocator);
            try ctx.setAttr("audit_actor", row.name);
        }

        fn tenantScope(ctx: *http.Context, self: *Self) i64 {
            return mw.authTenantId(ctx) orelse self.default_tenant_id;
        }

        fn list(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const tid = tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 100 });
            var result = self.svc.list(params.page, params.page_size, tid, account_id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer result.free(self.svc.allocator);
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, RecordDto, toDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }

        fn draw(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const admin_id = ctx.userIdInt(i64) orelse return;
            const tid = tenantScope(ctx, self);
            const req = ctx.bindJson(DrawReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer {
                ctx.allocator.free(req.openid);
                if (req.config.len > 0) ctx.allocator.free(req.config);
            }
            const cfg = self.svc.parseConfig(ctx.allocator, req.config);
            defer cfg.free(ctx.allocator);
            const result = self.svc.draw(ctx.allocator, tid, req.account_id, req.openid, &cfg) catch |err| {
                const msg = switch (err) {
                    error.DailyLimit => "今日抽奖次数已用完",
                    else => "操作失败",
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            defer ctx.allocator.free(result.prize_name);
            var d1: [128]u8 = undefined;
            const det1 = try std.fmt.bufPrint(&d1, "手动抽奖：{s} 抽中 {s}", .{ req.openid, result.prize_name });
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "lucky_draw.draw", "lucky_draw", req.account_id, det1, zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.okValue(.{ .prize_name = result.prize_name, .points = result.points });
        }
    };
}

pub const DefaultLuckyDrawApi = LuckyDrawApi(service.DrawService, user_svc.UserService);
