//! Admin-facing checkin API — 查看账号的签到记录。

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
    checkin_day: i64,
    points: i64,
    created_at: i64,
};

fn toDto(row: service.CheckinRecordRow) RecordDto {
    return .{
        .id = row.id,
        .account_id = row.account_id,
        .openid = row.openid,
        .checkin_day = row.checkin_day,
        .points = row.points,
        .created_at = row.created_at,
    };
}

pub fn CheckinApi(comptime Service: type, comptime UserService: type) type {
    return struct {
        const Self = @This();
        svc: *Service,
        user_svc: *UserService,
        audit: *audit_svc.AuditService,
        default_tenant_id: i64,

        pub const module_name = "checkin";
        pub const nest: []const []const u8 = &.{};
        pub const State = Self;

        pub const routes: []const http.RouteSpec(Self) = &.{
            .{ .method = .GET, .path = "checkin/records", .handler = http.wrapHandler(Self, list), .meta = .{ .permission = "checkin:read" } },
        };

        pub fn init(svc: *Service, users: *UserService, audit: *audit_svc.AuditService, default_tenant_id: i64) Self {
            return .{ .svc = svc, .user_svc = users, .audit = audit, .default_tenant_id = default_tenant_id };
        }

        pub fn registerRoutes(self: *Self, group: *http.RouteGroup) !void {
            var g = try group.use(zigmodu.http.http_middleware.jwtAuthWithSecurity(&self.user_svc.sec.module));
            g = try g.use(mw.tokenVersionGuard(self.user_svc.sec, self.user_svc.store));
            try g.get("/checkin/records", list, @ptrCast(@alignCast(self)));
        }

        /// Sets the `audit_actor` context attribute from the authenticated user.
        fn setAuditActor(ctx: *http.Context, self: *Self) !void {
            const uid = ctx.userIdInt(i64) orelse return;
            const row_opt = self.user_svc.getUserById(uid) catch return;
            const row = row_opt orelse return;
            defer row.free(self.user_svc.store.allocator);
            try ctx.setAttr("audit_actor", row.name);
        }

        fn list(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const tid = mw.authTenantId(ctx) orelse self.default_tenant_id;

            const account_raw = ctx.queryParam("account_id") orelse {
                try ctx.sendErrorResponse(400, 400, "缺少 account_id");
                return;
            };
            const account_id = std.fmt.parseInt(i64, account_raw, 10) catch {
                try ctx.sendErrorResponse(400, 400, "无效的 account_id");
                return;
            };
            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 100 });
            var result = self.svc.list(params.page, params.page_size, tid, account_id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer result.free(self.svc.allocator);

            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, RecordDto, toDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }
    };
}

pub const DefaultCheckinApi = CheckinApi(service.CheckinService, user_svc.UserService);
