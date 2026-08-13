//! Admin-facing menu API — 公众号自定义菜单的保存/读取/发布/删除。

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const mw = @import("../../middleware/auth.zig");
const user_svc = @import("../user/service.zig");
const audit_svc = @import("../audit/service.zig");

const service = @import("service.zig");

const SaveMenuReq = struct {
    menu_json: []const u8,
};

pub fn MenuApi(comptime Service: type, comptime UserService: type) type {
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
            try g.get("/accounts/{id}/menu", get, @ptrCast(@alignCast(self)));
            try g.put("/accounts/{id}/menu", save, @ptrCast(@alignCast(self)));
            try g.post("/accounts/{id}/menu/publish", publish, @ptrCast(@alignCast(self)));
            try g.get("/accounts/{id}/menu/fetch", fetchMenu, @ptrCast(@alignCast(self)));
            try g.delete("/accounts/{id}/menu", deleteRemote, @ptrCast(@alignCast(self)));
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

        fn accountId(ctx: *http.Context) ?i64 {
            return ctx.paramInt(i64, "id") catch null;
        }

        fn get(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);
            const account_id = accountId(ctx) orelse {
                try ctx.sendErrorResponse(400, 400, "无效的账号 ID");
                return;
            };

            const row_opt = self.svc.get(tid, account_id) catch |err| {
                try ctx.sendErrorResponse(500, 500, @errorName(err));
                return;
            };
            const row = row_opt orelse {
                try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = .{ .menu_json = "" } });
                return;
            };
            defer row.free(self.svc.allocator);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = .{ .menu_json = row.menu_json } });
        }

        fn save(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);
            const account_id = accountId(ctx) orelse {
                try ctx.sendErrorResponse(400, 400, "无效的账号 ID");
                return;
            };

            const req = ctx.bindJson(SaveMenuReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer ctx.allocator.free(req.menu_json);
            const id = self.svc.save(tid, account_id, req.menu_json) catch |err| {
                const msg = switch (err) {
                    error.InvalidJson => "菜单 JSON 格式错误",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            var d1: [96]u8 = undefined;
            const det1 = try std.fmt.bufPrint(&d1, "账号 #{d} 保存菜单", .{account_id});
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "menu.save", "menu", id, det1, zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = .{ .id = id } });
        }

        fn publish(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);
            const account_id = accountId(ctx) orelse {
                try ctx.sendErrorResponse(400, 400, "无效的账号 ID");
                return;
            };

            self.svc.publish(tid, account_id) catch |err| {
                const msg = switch (err) {
                    error.AccountNotFound => "账号不存在",
                    error.MenuNotConfigured => "尚未保存菜单",
                    error.WechatApiError => "微信接口调用失败",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            var d1: [96]u8 = undefined;
            const det1 = try std.fmt.bufPrint(&d1, "账号 #{d} 发布菜单", .{account_id});
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "menu.publish", "menu", account_id, det1, zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "已发布", .data = null });
        }

        fn deleteRemote(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);
            const account_id = accountId(ctx) orelse {
                try ctx.sendErrorResponse(400, 400, "无效的账号 ID");
                return;
            };

            self.svc.deleteRemote(account_id) catch |err| {
                const msg = switch (err) {
                    error.AccountNotFound => "账号不存在",
                    error.WechatApiError => "微信接口调用失败",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "menu.delete", "menu", account_id, "删除微信菜单", zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = null });
        }

        fn fetchMenu(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = (try requireAdmin(ctx, self)) orelse return;
            const account_id = accountId(ctx) orelse {
                try ctx.sendErrorResponse(400, 400, "无效的账号 ID");
                return;
            };
            const data = self.svc.fetchMenu(account_id) catch |err| {
                const msg = switch (err) {
                    error.AccountNotFound => "账号不存在",
                    error.WechatApiError => "微信接口调用失败",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            defer ctx.allocator.free(data);
            // 透传微信返回的原始 JSON（含 type 字段，绕过 Button.type_ 反射丢失）。
            try ctx.text(200, data);
        }
    };
}

pub const DefaultMenuApi = MenuApi(service.MenuService, user_svc.UserService);
