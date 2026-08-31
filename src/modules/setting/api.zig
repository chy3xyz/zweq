//! Site settings API — tenant-scoped key-value. Read: any authenticated
//! user of the tenant; write: admin.

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const mw = @import("../../middleware/auth.zig");
const user_svc = @import("../user/service.zig");
const audit_svc = @import("../audit/service.zig");

const service = @import("service.zig");

const SettingDto = struct {
    key: []const u8,
    value: []const u8,
    updated_at: i64,
};

fn toDto(row: service.SettingRow) SettingDto {
    return .{
        .key = row.key,
        .value = row.value,
        .updated_at = row.updated_at,
    };
}

const SetSettingReq = struct {
    value: []const u8,
};

pub fn SettingApi(comptime Service: type, comptime UserService: type) type {
    return struct {
        const Self = @This();
        svc: *Service,
        user_svc: *UserService,
        audit: *audit_svc.AuditService,
        default_tenant_id: i64,

        pub const module_name = "setting";
        pub const nest: []const []const u8 = &.{};
        pub const State = Self;

        pub const routes: []const http.RouteSpec(Self) = &.{
            .{ .method = .GET, .path = "settings", .handler = http.wrapHandler(Self, list), .meta = .{ .auth = .jwt } },
            .{ .method = .GET, .path = "settings/{key}", .handler = http.wrapHandler(Self, get), .meta = .{ .auth = .jwt } },
            .{ .method = .PUT, .path = "settings/{key}", .handler = http.wrapHandler(Self, set), .meta = .{ .permission = "setting:write" } },
            .{ .method = .DELETE, .path = "settings/{key}", .handler = http.wrapHandler(Self, delete), .meta = .{ .permission = "setting:write" } },
        };

        pub fn init(svc: *Service, users: *UserService, audit: *audit_svc.AuditService, default_tenant_id: i64) Self {
            return .{ .svc = svc, .user_svc = users, .audit = audit, .default_tenant_id = default_tenant_id };
        }

        pub fn registerRoutes(self: *Self, group: *http.RouteGroup) !void {
            var g = try group.use(zigmodu.http.http_middleware.jwtAuthWithSecurity(&self.user_svc.sec.module));
            g = try g.use(mw.tokenVersionGuard(self.user_svc.sec, self.user_svc.store));
            try g.get("/settings", list, @ptrCast(@alignCast(self)));
            try g.get("/settings/{key}", get, @ptrCast(@alignCast(self)));
            var admin_g = try g.use(mw.adminGuard(self.user_svc.store));
            try admin_g.put("/settings/{key}", set, @ptrCast(@alignCast(self)));
            try admin_g.delete("/settings/{key}", delete, @ptrCast(@alignCast(self)));
        }

        /// Authenticated user id (any role).
        fn requireAuth(ctx: *http.Context) !?i64 {
            const uid = mw.authUserId(ctx) orelse {
                try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                return null;
            };
            return uid;
        }

        fn setAuditActor(ctx: *http.Context, self: *Self) !void {
            const uid = mw.authUserId(ctx) orelse return;
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
            _ = (try requireAuth(ctx)) orelse return;
            const tid = tenantScope(ctx, self);

            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 200 });
            var result = self.svc.list(params.page, params.page_size, tid) catch |err| {
                try ctx.sendErrorResponse(500, 500, @errorName(err));
                return;
            };
            defer result.free(self.svc.allocator);

            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, SettingDto, toDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }

        fn get(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = (try requireAuth(ctx)) orelse return;
            const tid = tenantScope(ctx, self);

            const key = ctx.param("key") orelse {
                try ctx.sendErrorResponse(400, 400, "缺少配置键");
                return;
            };
            const row_opt = self.svc.get(tid, key) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            const row = row_opt orelse {
                try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = null });
                return;
            };
            defer row.free(self.svc.allocator);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = toDto(row) });
        }

        fn set(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const admin_id = mw.authUserId(ctx) orelse return;
            const tid = tenantScope(ctx, self);

            const key = ctx.param("key") orelse {
                try ctx.sendErrorResponse(400, 400, "缺少配置键");
                return;
            };
            const req = ctx.bindJson(SetSettingReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer ctx.allocator.free(req.value);
            const id = self.svc.set(tid, key, req.value) catch |err| {
                const msg = switch (err) {
                    error.InvalidKey => "配置键不能为空",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            var d1: [128]u8 = undefined;
            const det1 = try std.fmt.bufPrint(&d1, "设置 {s}", .{key});
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "setting.set", "setting", id, det1, zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = .{ .id = id } });
        }

        fn delete(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const admin_id = mw.authUserId(ctx) orelse return;
            const tid = tenantScope(ctx, self);

            const key = ctx.param("key") orelse {
                try ctx.sendErrorResponse(400, 400, "缺少配置键");
                return;
            };
            self.svc.delete(tid, key) catch |err| {
                try ctx.sendErrorResponse(500, 500, @errorName(err));
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "setting.delete", "setting", 0, "删除配置", zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = null });
        }
    };
}

pub const DefaultSettingApi = SettingApi(service.SettingService, user_svc.UserService);
