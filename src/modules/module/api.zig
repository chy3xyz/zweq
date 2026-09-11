//! Admin-facing module API — registry + per-account bindings.

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const mw = @import("../../middleware/auth.zig");
const user_svc = @import("../user/service.zig");
const audit_svc = @import("../audit/service.zig");

const service = @import("service.zig");
const admin_nav = @import("../../nav/admin.zig");

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

/// 整体更新：字段同注册去 name（name 为注册表键，不可变）。
const UpdateModuleReq = struct {
    title: []const u8,
    version: []const u8,
    status: []const u8,
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

        pub const module_name = "module";
        pub const nest: []const []const u8 = &.{};
        pub const State = Self;

        pub const routes: []const http.RouteSpec(Self) = &.{
            .{ .method = .GET, .path = "modules", .handler = http.wrapHandler(Self, list), .meta = .{ .permission = "module:read" } },
            .{ .method = .POST, .path = "modules", .handler = http.wrapHandler(Self, register), .meta = .{ .permission = "module:write" } },
            .{ .method = .PUT, .path = "modules/{id}", .handler = http.wrapHandler(Self, update), .meta = .{ .permission = "module:write" } },
            .{ .method = .GET, .path = "accounts/{id}/modules", .handler = http.wrapHandler(Self, listBindings), .meta = .{ .permission = "module:read" } },
            .{ .method = .PUT, .path = "accounts/{id}/modules", .handler = http.wrapHandler(Self, bind), .meta = .{ .permission = "module:write" } },
            .{ .method = .DELETE, .path = "accounts/{id}/modules/{module}", .handler = http.wrapHandler(Self, unbind), .meta = .{ .permission = "module:write" } },
            .{ .method = .GET, .path = "accounts/{id}/modules/{module}/config", .handler = http.wrapHandler(Self, getConfig), .meta = .{ .permission = "module:read" } },
            .{ .method = .PUT, .path = "accounts/{id}/modules/{module}/config", .handler = http.wrapHandler(Self, setConfig), .meta = .{ .permission = "module:write" } },
            .{ .method = .GET, .path = "admin/nav", .handler = http.wrapHandler(Self, adminNav), .meta = .{ .permission = "module:read" } },
        };

        pub fn init(svc: *Service, users: *UserService, audit: *audit_svc.AuditService, default_tenant_id: i64) Self {
            return .{ .svc = svc, .user_svc = users, .audit = audit, .default_tenant_id = default_tenant_id };
        }

        pub fn registerRoutes(self: *Self, group: *http.RouteGroup) !void {
            var g = try group.use(zigmodu.http.http_middleware.jwtAuthWithSecurity(&self.user_svc.sec.module));
            g = try g.use(mw.tokenVersionGuard(self.user_svc.sec, self.user_svc.store));
            try g.get("/modules", list, @ptrCast(@alignCast(self)));
            try g.post("/modules", register, @ptrCast(@alignCast(self)));
            try g.put("/modules/{id}", update, @ptrCast(@alignCast(self)));
            try g.get("/accounts/{id}/modules", listBindings, @ptrCast(@alignCast(self)));
            try g.put("/accounts/{id}/modules", bind, @ptrCast(@alignCast(self)));
            try g.delete("/accounts/{id}/modules/{module}", unbind, @ptrCast(@alignCast(self)));
            try g.get("/accounts/{id}/modules/{module}/config", getConfig, @ptrCast(@alignCast(self)));
            try g.put("/accounts/{id}/modules/{module}/config", setConfig, @ptrCast(@alignCast(self)));
            try g.get("/admin/nav", adminNav, @ptrCast(@alignCast(self)));
        }

        fn adminNav(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            try admin_nav.handleAdminNav(ctx, self.svc, self.default_tenant_id, self.user_svc);
        }

        fn tenantScope(ctx: *http.Context, self: *Self) i64 {
            return mw.authTenantId(ctx) orelse self.default_tenant_id;
        }

        fn setAuditActor(ctx: *http.Context, self: *Self) !void {
            const uid = ctx.userIdInt(i64) orelse return;
            const row_opt = self.user_svc.getUserById(uid) catch return;
            const row = row_opt orelse return;
            defer row.free(self.svc.allocator);
            try ctx.setAttr("audit_actor", row.name);
        }

        fn list(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const tid = tenantScope(ctx, self);

            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 100 });
            var result = self.svc.list(params.page, params.page_size, tid) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer result.free(self.svc.allocator);

            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, ModuleDto, toModuleDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }

        fn register(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const admin_id = ctx.userIdInt(i64) orelse return;
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
                const msg = switch (err) {
                    error.InvalidName => "模块名不能为空",
                    else => "操作失败",
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            var d1: [128]u8 = undefined;
            const det1 = try std.fmt.bufPrint(&d1, "注册模块 {s} v{s}", .{ req.name, req.version });
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "module.register", "module", id, det1, zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.okValue(.{ .id = id });
        }

        /// 整体更新模块（title/version/status）。status 仅接受 active/disabled。
        fn update(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const admin_id = ctx.userIdInt(i64) orelse return;
            const tid = tenantScope(ctx, self);

            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的模块 ID");
                return;
            };
            const req = ctx.bindJson(UpdateModuleReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer {
                ctx.allocator.free(req.title);
                ctx.allocator.free(req.version);
                ctx.allocator.free(req.status);
            }
            self.svc.updateModule(tid, id, req.title, req.version, req.status) catch |err| switch (err) {
                error.NotFound => {
                    try ctx.sendErrorResponse(404, 404, "模块不存在");
                    return;
                },
                error.InvalidInput => {
                    try ctx.sendErrorResponse(400, 400, "状态仅支持 active/disabled");
                    return;
                },
                else => {
                    try ctx.sendErrorResponse(500, 500, "服务器错误");
                    return;
                },
            };
            var d1: [128]u8 = undefined;
            const det1 = try std.fmt.bufPrint(&d1, "更新模块 #{d}", .{id});
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "module.update", "module", id, det1, zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.okValue(.{ .id = id });
        }

        fn listBindings(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const tid = tenantScope(ctx, self);

            const account_id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的账号 ID");
                return;
            };
            const rows = self.svc.accountModules(tid, account_id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
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
            try ctx.okValue(.{ .items = dtos });
        }

        fn bind(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const admin_id = ctx.userIdInt(i64) orelse return;
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
                const msg = switch (err) {
                    error.InvalidName => "模块名不能为空",
                    error.InvalidStatus => "状态仅支持 active/disabled",
                    else => "操作失败",
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            var d1: [128]u8 = undefined;
            const det1 = try std.fmt.bufPrint(&d1, "账号 #{d} 绑定模块 {s}", .{ account_id, req.module });
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "module.bind", "module", id, det1, zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.okValue(.{ .id = id });
        }

        fn unbind(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const admin_id = ctx.userIdInt(i64) orelse return;
            const tid = tenantScope(ctx, self);

            const account_id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的账号 ID");
                return;
            };
            const module = ctx.param("module") orelse {
                try ctx.sendErrorResponse(400, 400, "缺少模块名");
                return;
            };
            self.svc.unbind(tid, account_id, module) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "module.unbind", "module", account_id, "解绑模块", zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.ok("null");
        }

        fn getConfig(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const tid = tenantScope(ctx, self);

            const account_id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的账号 ID");
                return;
            };
            const module = ctx.param("module") orelse {
                try ctx.sendErrorResponse(400, 400, "缺少模块名");
                return;
            };
            const cfg = self.svc.getConfig(ctx.allocator, tid, account_id, module) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer if (cfg) |c| ctx.allocator.free(c);
            try ctx.okValue(.{ .config = cfg orelse "" });
        }

        fn setConfig(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const admin_id = ctx.userIdInt(i64) orelse return;
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
            const id = self.svc.setConfig(tid, account_id, module, req.config) catch {
                try ctx.sendErrorResponse(400, 400, "操作失败");
                return;
            };
            var d1: [128]u8 = undefined;
            const det1 = try std.fmt.bufPrint(&d1, "账号 #{d} 模块 {s} 更新配置", .{ account_id, module });
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "module.config", "module", id, det1, zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.okValue(.{ .id = id });
        }
    };
}

pub const DefaultModuleApi = ModuleApi(service.ModuleService, user_svc.UserService);
