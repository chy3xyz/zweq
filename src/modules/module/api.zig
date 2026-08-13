//! Admin-facing module API — registry + per-account bindings.

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const mw = @import("../../middleware/auth.zig");
const user_svc = @import("../user/service.zig");
const audit_svc = @import("../audit/service.zig");

const service = @import("service.zig");

const ModuleDto = struct {
    id: i64,
    name: []const u8,
    title: []const u8,
    version: []const u8,
    status: []const u8,
    created_at: i64,
    updated_at: i64,
};

fn toModuleDto(row: service.AppModuleRow) ModuleDto {
    return .{
        .id = row.id,
        .name = row.name,
        .title = row.title,
        .version = row.version,
        .status = row.status,
        .created_at = row.created_at,
        .updated_at = row.updated_at,
    };
}

const BindingDto = struct {
    id: i64,
    account_id: i64,
    module: []const u8,
    status: []const u8,
    config: []const u8,
};

const RegisterModuleReq = struct {
    name: []const u8,
    title: []const u8,
    version: []const u8,
};

const BindModuleReq = struct {
    module: []const u8,
    status: ?[]const u8 = null,
};

pub fn ModuleApi(comptime Service: type, comptime UserService: type) type {
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
            try g.get("/modules", list, @ptrCast(@alignCast(self)));
            try g.post("/modules", register, @ptrCast(@alignCast(self)));
            try g.get("/accounts/{id}/modules", listBindings, @ptrCast(@alignCast(self)));
            try g.put("/accounts/{id}/modules", bind, @ptrCast(@alignCast(self)));
            try g.delete("/accounts/{id}/modules/{module}", unbind, @ptrCast(@alignCast(self)));
            try g.get("/accounts/{id}/modules/{module}/config", getConfig, @ptrCast(@alignCast(self)));
            try g.put("/accounts/{id}/modules/{module}/config", setConfig, @ptrCast(@alignCast(self)));
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
            _ = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);

            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 100 });
            var result = self.svc.list(params.page, params.page_size, tid) catch |err| {
                try ctx.sendErrorResponse(500, 500, @errorName(err));
                return;
            };
            defer result.free(self.svc.allocator);

            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, ModuleDto, toModuleDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }

        fn register(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);

            const req = ctx.bindJson(RegisterModuleReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer {
                ctx.allocator.free(req.name);
                ctx.allocator.free(req.title);
                ctx.allocator.free(req.version);
            }
            const id = self.svc.register(tid, req.name, req.title, req.version) catch |err| {
                try ctx.sendErrorResponse(400, 400, @errorName(err));
                return;
            };
            var d1: [128]u8 = undefined;
            const det1 = try std.fmt.bufPrint(&d1, "注册模块 {s} v{s}", .{ req.name, req.version });
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "module.register", "module", id, det1, zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(201, .{ .code = 0, .msg = "模块已注册", .data = .{ .id = id } });
        }

        fn listBindings(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);

            const account_id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的账号 ID");
                return;
            };
            const rows = self.svc.accountModules(tid, account_id) catch |err| {
                try ctx.sendErrorResponse(500, 500, @errorName(err));
                return;
            };
            defer {
                for (rows) |r| r.free(ctx.allocator);
                ctx.allocator.free(rows);
            }
            const dtos = try ctx.allocator.alloc(BindingDto, rows.len);
            for (rows, 0..) |r, i| {
                dtos[i] = .{ .id = r.id, .account_id = r.account_id, .module = r.module, .status = r.status, .config = r.config };
            }
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = .{ .items = dtos } });
        }

        fn bind(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);

            const account_id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的账号 ID");
                return;
            };
            const req = ctx.bindJson(BindModuleReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer {
                ctx.allocator.free(req.module);
                if (req.status) |s| ctx.allocator.free(s);
            }
            const status = req.status orelse "active";
            const id = self.svc.bind(tid, account_id, req.module, status) catch |err| {
                try ctx.sendErrorResponse(400, 400, @errorName(err));
                return;
            };
            var d1: [128]u8 = undefined;
            const det1 = try std.fmt.bufPrint(&d1, "账号 #{d} 绑定模块 {s}", .{ account_id, req.module });
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "module.bind", "module", id, det1, zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = .{ .id = id } });
        }

        fn unbind(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);

            const account_id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的账号 ID");
                return;
            };
            const module = ctx.param("module") orelse {
                try ctx.sendErrorResponse(400, 400, "缺少模块名");
                return;
            };
            self.svc.unbind(tid, account_id, module) catch |err| {
                try ctx.sendErrorResponse(500, 500, @errorName(err));
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "module.unbind", "module", account_id, "解绑模块", zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = null });
        }

        fn getConfig(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);

            const account_id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的账号 ID");
                return;
            };
            const module = ctx.param("module") orelse {
                try ctx.sendErrorResponse(400, 400, "缺少模块名");
                return;
            };
            const cfg = self.svc.getConfig(ctx.allocator, tid, account_id, module) catch |err| {
                try ctx.sendErrorResponse(500, 500, @errorName(err));
                return;
            };
            defer if (cfg) |c| ctx.allocator.free(c);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = .{ .config = cfg orelse "" } });
        }

        fn setConfig(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);

            const account_id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的账号 ID");
                return;
            };
            const module = ctx.param("module") orelse {
                try ctx.sendErrorResponse(400, 400, "缺少模块名");
                return;
            };
            const req = ctx.bindJson(struct { config: []const u8 }) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer ctx.allocator.free(req.config);
            const id = self.svc.setConfig(tid, account_id, module, req.config) catch |err| {
                try ctx.sendErrorResponse(400, 400, @errorName(err));
                return;
            };
            var d1: [128]u8 = undefined;
            const det1 = try std.fmt.bufPrint(&d1, "账号 #{d} 模块 {s} 更新配置", .{ account_id, module });
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "module.config", "module", id, det1, zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = .{ .id = id } });
        }
    };
}

pub const DefaultModuleApi = ModuleApi(service.ModuleService, user_svc.UserService);
