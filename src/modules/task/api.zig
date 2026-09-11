//! Admin-facing HTTP API for the background task queue. All routes require
//! a valid JWT and the `admin` role (checked against the DB).

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const mw = @import("../../middleware/auth.zig");
const user_svc = @import("../user/service.zig");
const service = @import("service.zig");
const audit_svc = @import("../audit/service.zig");

const TaskDto = struct {
    id: i64,
    name: []const u8,
    payload: []const u8,
    status: []const u8,
    tenant_id: i64,
    attempts: i64,
    max_attempts: i64,
    last_error: []const u8,
    available_at: i64,
    started_at: i64,
    finished_at: i64,
    created_at: i64,
    updated_at: i64,
};

fn toDto(row: service.TaskRow) TaskDto {
    return .{
        .id = row.id,
        .name = row.name,
        .payload = row.payload,
        .status = row.status,
        .tenant_id = row.tenant_id,
        .attempts = row.attempts,
        .max_attempts = row.max_attempts,
        .last_error = row.last_error,
        .available_at = row.available_at,
        .started_at = row.started_at,
        .finished_at = row.finished_at,
        .created_at = row.created_at,
        .updated_at = row.updated_at,
    };
}

pub fn TaskApi(comptime Service: type, comptime UserService: type) type {
    return struct {
        const Self = @This();
        svc: *Service,
        user_svc: *UserService,
        audit: *audit_svc.AuditService,

        pub const module_name = "task";
        pub const nest: []const []const u8 = &.{};
        pub const State = Self;

        pub const routes: []const http.RouteSpec(Self) = &.{
            .{ .method = .GET, .path = "tasks/stats", .handler = http.wrapHandler(Self, stats), .meta = .{ .permission = "task:read" } },
            .{ .method = .GET, .path = "tasks", .handler = http.wrapHandler(Self, list), .meta = .{ .permission = "task:read" } },
            .{ .method = .GET, .path = "tasks/{id}", .handler = http.wrapHandler(Self, get), .meta = .{ .permission = "task:read" } },
            .{ .method = .POST, .path = "tasks/{id}/retry", .handler = http.wrapHandler(Self, retry), .meta = .{ .permission = "task:write" } },
            .{ .method = .POST, .path = "tasks/{id}/cancel", .handler = http.wrapHandler(Self, cancel), .meta = .{ .permission = "task:write" } },
            .{ .method = .POST, .path = "tasks/purge", .handler = http.wrapHandler(Self, purge), .meta = .{ .permission = "task:write" } },
            .{ .method = .DELETE, .path = "tasks/{id}", .handler = http.wrapHandler(Self, delete), .meta = .{ .permission = "task:write" } },
        };

        pub fn init(svc: *Service, users: *UserService, audit: *audit_svc.AuditService) Self {
            return .{ .svc = svc, .user_svc = users, .audit = audit };
        }

        fn setAuditActor(ctx: *http.Context, self: *Self) !void {
            const uid = ctx.userIdInt(i64) orelse return;
            const row_opt = self.user_svc.getUserById(uid) catch return;
            const row = row_opt orelse return;
            defer row.free(self.user_svc.store.allocator);
            try ctx.setAttr("audit_actor", row.name);
        }

        fn stats(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const counts = self.svc.counts() catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            try ctx.okValue(counts);
        }

        fn list(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);

            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 100 });
            const status = ctx.queryParam("status");

            var result = self.svc.list(params.page, params.page_size, status) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer result.free(self.svc.store.allocator);

            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, TaskDto, toDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }

        fn get(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);

            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的任务 ID");
                return;
            };
            const row_opt = self.svc.get(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            const row = row_opt orelse {
                try ctx.sendErrorResponse(404, 404, "任务不存在");
                return;
            };
            defer row.free(self.svc.store.allocator);
            try ctx.okValue(toDto(row));
        }

        fn retry(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const admin_id = ctx.userIdInt(i64) orelse return;
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的任务 ID");
                return;
            };
            _ = self.svc.retry(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            var d1: [96]u8 = undefined;
            const det1 = try std.fmt.bufPrint(&d1, "重试任务 #{d}", .{id});
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "task.retry", "task", id, det1, zigmodu.http.RequestUtil.getRealIp(ctx), true, 0);
            try ctx.ok("null");
        }

        fn cancel(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const admin_id = ctx.userIdInt(i64) orelse return;
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的任务 ID");
                return;
            };
            _ = self.svc.cancel(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            var d2: [96]u8 = undefined;
            const det2 = try std.fmt.bufPrint(&d2, "取消任务 #{d}", .{id});
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "task.cancel", "task", id, det2, zigmodu.http.RequestUtil.getRealIp(ctx), true, 0);
            try ctx.ok("null");
        }

        fn purge(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const admin_id = ctx.userIdInt(i64) orelse return;
            _ = self.svc.purge() catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            const det3 = "清理已完成任务";
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "task.purge", "task", 0, det3, zigmodu.http.RequestUtil.getRealIp(ctx), true, 0);
            try ctx.ok("null");
        }

        fn delete(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const admin_id = ctx.userIdInt(i64) orelse return;
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的任务 ID");
                return;
            };
            self.svc.delete(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            var d4: [96]u8 = undefined;
            const det4 = try std.fmt.bufPrint(&d4, "删除任务 #{d}", .{id});
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "task.delete", "task", id, det4, zigmodu.http.RequestUtil.getRealIp(ctx), true, 0);
            try ctx.ok("null");
        }
    };
}

pub const DefaultTaskApi = TaskApi(service.TaskService, user_svc.UserService);
