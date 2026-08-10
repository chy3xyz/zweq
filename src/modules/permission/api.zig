//! Admin-facing RBAC API — roles, permission grants, user-role binding.

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const mw = @import("../../middleware/auth.zig");
const user_svc = @import("../user/service.zig");
const audit_svc = @import("../audit/service.zig");

const service = @import("service.zig");

const RoleDto = struct {
    id: i64,
    tenant_id: i64,
    name: []const u8,
    code: []const u8,
    description: []const u8,
    created_at: i64,
    updated_at: i64,
};

fn toRoleDto(row: service.RoleRow) RoleDto {
    return .{
        .id = row.id,
        .tenant_id = row.tenant_id,
        .name = row.name,
        .code = row.code,
        .description = row.description,
        .created_at = row.created_at,
        .updated_at = row.updated_at,
    };
}

const PermissionDto = struct {
    id: i64,
    tenant_id: i64,
    account_id: i64,
    module: []const u8,
    action: []const u8,
    created_at: i64,
    updated_at: i64,
};

fn toPermissionDto(row: service.PermissionRow) PermissionDto {
    return .{
        .id = row.id,
        .tenant_id = row.tenant_id,
        .account_id = row.account_id,
        .module = row.module,
        .action = row.action,
        .created_at = row.created_at,
        .updated_at = row.updated_at,
    };
}

const UserRoleDto = struct {
    user_id: i64,
    role_id: i64,
};

const CreateRoleReq = struct {
    name: []const u8,
    code: []const u8,
    description: ?[]const u8 = null,
};

const UpdateRoleReq = struct {
    name: ?[]const u8 = null,
    code: ?[]const u8 = null,
    description: ?[]const u8 = null,
};

const GrantPermissionReq = struct {
    account_id: i64,
    module: []const u8,
    action: []const u8,
};

const AssignRoleReq = struct {
    role_id: i64,
};

pub fn PermissionApi(comptime Service: type, comptime UserService: type) type {
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
            try g.get("/roles", listRoles, @ptrCast(@alignCast(self)));
            try g.post("/roles", createRole, @ptrCast(@alignCast(self)));
            try g.put("/roles/{id}", updateRole, @ptrCast(@alignCast(self)));
            try g.delete("/roles/{id}", deleteRole, @ptrCast(@alignCast(self)));
            try g.get("/permissions", listPermissions, @ptrCast(@alignCast(self)));
            try g.post("/permissions", grantPermission, @ptrCast(@alignCast(self)));
            try g.delete("/permissions/{id}", revokePermission, @ptrCast(@alignCast(self)));
            try g.get("/users/{id}/roles", listUserRoles, @ptrCast(@alignCast(self)));
            try g.put("/users/{id}/roles", assignUserRole, @ptrCast(@alignCast(self)));
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

        fn listRoles(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);

            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 100 });
            var result = self.svc.list(params.page, params.page_size, tid) catch |err| {
                try ctx.sendErrorResponse(500, 500, @errorName(err));
                return;
            };
            defer result.free(self.svc.allocator);

            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, RoleDto, toRoleDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }

        fn createRole(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);

            const req = ctx.bindJson(CreateRoleReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer {
                ctx.allocator.free(req.name);
                ctx.allocator.free(req.code);
                if (req.description) |d| ctx.allocator.free(d);
            }
            const description = req.description orelse "";
            const id = self.svc.create(tid, req.name, req.code, description) catch |err| {
                const msg = switch (err) {
                    error.InvalidName => "角色名称不能为空",
                    error.InvalidCode => "角色编码仅支持 founder/admin/operator",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            var d1: [128]u8 = undefined;
            const det1 = try std.fmt.bufPrint(&d1, "创建角色 {s} ({s})", .{ req.name, req.code });
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "role.create", "role", id, det1, zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(201, .{ .code = 0, .msg = "角色已创建", .data = .{ .id = id } });
        }

        fn updateRole(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;

            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的角色 ID");
                return;
            };
            const req = ctx.bindJson(UpdateRoleReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer {
                if (req.name) |n| ctx.allocator.free(n);
                if (req.code) |c| ctx.allocator.free(c);
                if (req.description) |d| ctx.allocator.free(d);
            }
            const cur_opt = self.svc.get(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            const cur = cur_opt orelse {
                try ctx.sendErrorResponse(404, 404, "角色不存在");
                return;
            };
            defer cur.free(self.svc.allocator);

            const name = req.name orelse cur.name;
            const code = req.code orelse cur.code;
            const description = req.description orelse cur.description;
            _ = self.svc.update(id, name, code, description) catch |err| {
                const msg = switch (err) {
                    error.InvalidName => "角色名称不能为空",
                    error.InvalidCode => "角色编码仅支持 founder/admin/operator",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            var d2: [128]u8 = undefined;
            const det2 = try std.fmt.bufPrint(&d2, "更新角色 #{d} → {s}", .{ id, code });
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "role.update", "role", id, det2, zigmodu.http.RequestUtil.getRealIp(ctx), true, tenantScope(ctx, self));
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = null });
        }

        fn deleteRole(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;

            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的角色 ID");
                return;
            };
            self.svc.delete(id) catch |err| {
                try ctx.sendErrorResponse(500, 500, @errorName(err));
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "role.delete", "role", id, "删除角色", zigmodu.http.RequestUtil.getRealIp(ctx), true, tenantScope(ctx, self));
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = null });
        }

        fn listPermissions(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);

            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 100 });
            const account_raw = ctx.queryParam("account_id");
            var account_id: ?i64 = null;
            if (account_raw) |raw| {
                account_id = std.fmt.parseInt(i64, raw, 10) catch null;
            }
            var result = self.svc.listPermissions(params.page, params.page_size, tid, account_id) catch |err| {
                try ctx.sendErrorResponse(500, 500, @errorName(err));
                return;
            };
            defer result.free(self.svc.allocator);

            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, PermissionDto, toPermissionDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }

        fn grantPermission(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);

            const req = ctx.bindJson(GrantPermissionReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer {
                ctx.allocator.free(req.module);
                ctx.allocator.free(req.action);
            }
            const id = self.svc.grant(tid, req.account_id, req.module, req.action) catch |err| {
                try ctx.sendErrorResponse(400, 400, @errorName(err));
                return;
            };
            var d1: [128]u8 = undefined;
            const det1 = try std.fmt.bufPrint(&d1, "授权 {s}:{s} @ account {d}", .{ req.module, req.action, req.account_id });
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "permission.grant", "permission", id, det1, zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(201, .{ .code = 0, .msg = "已授权", .data = .{ .id = id } });
        }

        fn revokePermission(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;

            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的权限 ID");
                return;
            };
            self.svc.revoke(id) catch |err| {
                try ctx.sendErrorResponse(500, 500, @errorName(err));
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "permission.revoke", "permission", id, "撤销授权", zigmodu.http.RequestUtil.getRealIp(ctx), true, tenantScope(ctx, self));
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = null });
        }

        fn listUserRoles(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = (try requireAdmin(ctx, self)) orelse return;

            const user_id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的用户 ID");
                return;
            };
            const rows = self.svc.listRolesForUser(user_id) catch |err| {
                try ctx.sendErrorResponse(500, 500, @errorName(err));
                return;
            };
            defer ctx.allocator.free(rows);
            const dtos = try ctx.allocator.alloc(UserRoleDto, rows.len);
            for (rows, 0..) |r, i| {
                dtos[i] = .{ .user_id = r.user_id, .role_id = r.role_id };
            }
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = .{ .items = dtos } });
        }

        fn assignUserRole(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);

            const user_id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的用户 ID");
                return;
            };
            const req = ctx.bindJson(AssignRoleReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            const id = self.svc.assignRole(tid, user_id, req.role_id) catch |err| {
                try ctx.sendErrorResponse(500, 500, @errorName(err));
                return;
            };
            var d1: [128]u8 = undefined;
            const det1 = try std.fmt.bufPrint(&d1, "用户 #{d} 绑定角色 #{d}", .{ user_id, req.role_id });
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "user_role.assign", "user", user_id, det1, zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = .{ .id = id } });
        }
    };
}

pub const DefaultPermissionApi = PermissionApi(service.RoleService, user_svc.UserService);
