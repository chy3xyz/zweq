//! Admin-facing tenant API — platform administrators manage tenants.

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const mw = @import("../../middleware/auth.zig");
const user_svc = @import("../user/service.zig");
const audit_svc = @import("../audit/service.zig");

const service = @import("service.zig");

const TenantDto = struct {
    id: i64,
    name: []const u8,
    status: []const u8,
    created_at: i64,
    updated_at: i64,
};

fn toDto(row: service.TenantRow) TenantDto {
    return .{
        .id = row.id,
        .name = row.name,
        .status = row.status,
        .created_at = row.created_at,
        .updated_at = row.updated_at,
    };
}

const CreateTenantReq = struct {
    name: []const u8,
};

const UpdateTenantReq = struct {
    name: ?[]const u8 = null,
    status: ?[]const u8 = null,
};

pub fn TenantApi(comptime Service: type, comptime UserService: type) type {
    return struct {
        const Self = @This();
        svc: *Service,
        user_svc: *UserService,
        audit: *audit_svc.AuditService,

        pub const module_name = "tenant";
        pub const nest: []const []const u8 = &.{};
        pub const State = Self;

        pub const routes: []const http.RouteSpec(Self) = &.{
            .{ .method = .GET, .path = "tenants", .handler = http.wrapHandler(Self, list), .meta = .{ .permission = "tenant:read" } },
            .{ .method = .POST, .path = "tenants", .handler = http.wrapHandler(Self, create), .meta = .{ .permission = "tenant:write" } },
            .{ .method = .PUT, .path = "tenants/{id}", .handler = http.wrapHandler(Self, update), .meta = .{ .permission = "tenant:write" } },
        };

        pub fn init(svc: *Service, users: *UserService, audit: *audit_svc.AuditService) Self {
            return .{ .svc = svc, .user_svc = users, .audit = audit };
        }

        fn setAuditActor(ctx: *http.Context, self: *Self) !void {
            const uid = mw.authUserId(ctx) orelse return;
            const row_opt = self.user_svc.getUserById(uid) catch return;
            const row = row_opt orelse return;
            defer row.free(self.user_svc.store.allocator);
            try ctx.setAttr("audit_actor", row.name);
        }

        fn list(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);

            const keyword = ctx.queryStr("keyword", "");
            const status = ctx.queryStr("status", "");
            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 100 });
            var result = self.svc.list(params.page, params.page_size, keyword, status) catch |err| {
                try ctx.sendErrorResponse(500, 500, @errorName(err));
                return;
            };
            defer result.free(self.svc.allocator);

            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, TenantDto, toDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }

        fn create(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const admin_id = mw.authUserId(ctx) orelse return;

            const req = ctx.bindJson(CreateTenantReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer ctx.allocator.free(req.name);
            if (std.mem.trim(u8, req.name, " \t").len == 0) {
                try ctx.sendErrorResponse(400, 400, "租户名称不能为空");
                return;
            }
            const id = self.svc.create(req.name) catch |err| {
                try ctx.sendErrorResponse(500, 500, @errorName(err));
                return;
            };
            var d1: [128]u8 = undefined;
            const det1 = try std.fmt.bufPrint(&d1, "创建租户 {s}", .{req.name});
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "tenant.create", "tenant", id, det1, zigmodu.http.RequestUtil.getRealIp(ctx), true, id);
            try ctx.jsonStruct(201, .{ .code = 0, .msg = "租户已创建", .data = .{ .id = id } });
        }

        fn update(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const admin_id = mw.authUserId(ctx) orelse return;

            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的租户 ID");
                return;
            };
            const req = ctx.bindJson(UpdateTenantReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer {
                if (req.name) |n| ctx.allocator.free(n);
                if (req.status) |s| ctx.allocator.free(s);
            }
            const cur_opt = self.svc.get(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            const cur = cur_opt orelse {
                try ctx.sendErrorResponse(404, 404, "租户不存在");
                return;
            };
            defer cur.free(self.svc.allocator);

            const name = req.name orelse cur.name;
            const status = req.status orelse cur.status;
            if (!std.mem.eql(u8, status, "active") and !std.mem.eql(u8, status, "disabled")) {
                try ctx.sendErrorResponse(400, 400, "状态仅支持 active/disabled");
                return;
            }
            _ = self.svc.update(id, name, status) catch |err| {
                try ctx.sendErrorResponse(500, 500, @errorName(err));
                return;
            };
            var d2: [128]u8 = undefined;
            const det2 = try std.fmt.bufPrint(&d2, "更新租户 #{d} → {s}", .{ id, status });
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "tenant.update", "tenant", id, det2, zigmodu.http.RequestUtil.getRealIp(ctx), true, id);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = null });
        }
    };
}

pub const DefaultTenantApi = TenantApi(service.TenantService, user_svc.UserService);
