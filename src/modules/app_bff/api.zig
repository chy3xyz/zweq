//! H5 mobile BFF — thin routing layer for the storefront app. No own tables;
//! calls domain services (account, module) only.

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const mw = @import("../../middleware/auth.zig");
const account_svc = @import("../account/service.zig");
const module_svc = @import("../module/service.zig");
const user_svc = @import("../user/service.zig");

const AccountInfoDto = struct {
    id: i64,
    name: []const u8,
    kind: []const u8,
    status: []const u8,
};

const AccountModuleDto = struct {
    module: []const u8,
    status: []const u8,
};

pub fn AppBffApi(comptime AccountService: type, comptime ModuleService: type, comptime UserService: type) type {
    return struct {
        const Self = @This();
        account_svc: *AccountService,
        module_svc: *ModuleService,
        user_svc: *UserService,
        default_tenant_id: i64,

        pub fn init(accounts: *AccountService, mods: *ModuleService, users: *UserService, default_tenant_id: i64) Self {
            return .{ .account_svc = accounts, .module_svc = mods, .user_svc = users, .default_tenant_id = default_tenant_id };
        }

        pub fn registerRoutes(self: *Self, group: *http.RouteGroup) !void {
            var g = try group.use(zigmodu.http.http_middleware.jwtAuthWithSecurity(&self.user_svc.sec.module));
            g = try g.use(mw.tokenVersionGuard(self.user_svc.sec, self.user_svc.store));
            try g.get("/app/accounts/{id}", accountInfo, @ptrCast(@alignCast(self)));
            try g.get("/app/accounts/{id}/modules", modules, @ptrCast(@alignCast(self)));
        }

        fn requireAuth(ctx: *http.Context) ?i64 {
            return mw.authUserId(ctx);
        }

        fn tenantScope(ctx: *http.Context, self: *Self) i64 {
            return mw.authTenantId(ctx) orelse self.default_tenant_id;
        }

        fn accountInfo(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            if ((requireAuth(ctx)) == null) {
                try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                return;
            }
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的账号 ID");
                return;
            };
            const row_opt = self.account_svc.get(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            const row = row_opt orelse {
                try ctx.sendErrorResponse(404, 404, "账号不存在");
                return;
            };
            defer row.free(self.account_svc.allocator);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = AccountInfoDto{
                .id = row.id,
                .name = row.name,
                .kind = row.kind,
                .status = row.status,
            } });
        }

        fn modules(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            if ((requireAuth(ctx)) == null) {
                try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                return;
            }
            const tid = tenantScope(ctx, self);
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的账号 ID");
                return;
            };
            const rows = self.module_svc.accountModules(tid, id) catch |err| {
                try ctx.sendErrorResponse(500, 500, @errorName(err));
                return;
            };
            defer {
                for (rows) |r| r.free(self.module_svc.allocator);
                self.module_svc.allocator.free(rows);
            }
            const dtos = try ctx.allocator.alloc(AccountModuleDto, rows.len);
            var n: usize = 0;
            for (rows) |r| {
                // 只暴露启用的模块入口
                if (!std.mem.eql(u8, r.status, "active")) continue;
                dtos[n] = .{ .module = r.module, .status = r.status };
                n += 1;
            }
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = .{ .items = dtos[0..n] } });
        }
    };
}

pub const DefaultAppBffApi = AppBffApi(account_svc.AccountService, module_svc.ModuleService, user_svc.UserService);
