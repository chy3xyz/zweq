//! Notification HTTP API — any authenticated user manages their own inbox.

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const mw = @import("../../middleware/auth.zig");
const user_svc = @import("../user/service.zig");
const service = @import("service.zig");

const NotificationDto = struct {
    id: i64,
    title: []const u8,
    body: []const u8,
    read: bool,
    kind: []const u8,
    created_at: i64,
};

fn toDto(row: service.NotificationRow) NotificationDto {
    return .{
        .id = row.id,
        .title = row.title,
        .body = row.body,
        .read = row.read,
        .kind = row.kind,
        .created_at = row.created_at,
    };
}

pub fn NotificationApi(comptime Service: type, comptime UserService: type) type {
    return struct {
        const Self = @This();
        svc: *Service,
        user_svc: *UserService,

        pub const module_name = "notify";
        pub const nest: []const []const u8 = &.{};
        pub const State = Self;

        pub const routes: []const http.RouteSpec(Self) = &.{
            .{ .method = .GET, .path = "notifications/unread-count", .handler = http.wrapHandler(Self, unreadCount), .meta = .{ .auth = .jwt } },
            .{ .method = .GET, .path = "notifications", .handler = http.wrapHandler(Self, list), .meta = .{ .auth = .jwt } },
            .{ .method = .POST, .path = "notifications/read-all", .handler = http.wrapHandler(Self, markAllRead), .meta = .{ .auth = .jwt } },
            .{ .method = .POST, .path = "notifications/{id}/read", .handler = http.wrapHandler(Self, markRead), .meta = .{ .auth = .jwt } },
            .{ .method = .DELETE, .path = "notifications/{id}", .handler = http.wrapHandler(Self, delete), .meta = .{ .auth = .jwt } },
        };

        pub fn init(svc: *Service, users: *UserService) Self {
            return .{ .svc = svc, .user_svc = users };
        }

        fn authUserId(ctx: *http.Context) ?i64 {
            return ctx.userIdInt(i64);
        }

        fn list(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const uid = authUserId(ctx) orelse {
                try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                return;
            };
            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 100 });
            const unread = ctx.queryInt(usize, "unread", 0) == 1;

            var result = self.svc.list(uid, params.page, params.page_size, unread) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer result.free(self.svc.allocator);

            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, NotificationDto, toDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }

        fn unreadCount(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const uid = authUserId(ctx) orelse {
                try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                return;
            };
            const count = self.svc.unreadCount(uid) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            try ctx.okValue(.{ .unread = count });
        }

        fn markRead(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const uid = authUserId(ctx) orelse {
                try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                return;
            };
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的通知 ID");
                return;
            };
            _ = self.svc.markRead(id, uid) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            try ctx.ok("null");
        }

        fn markAllRead(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const uid = authUserId(ctx) orelse {
                try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                return;
            };
            self.svc.markAllRead(uid) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            try ctx.ok("null");
        }

        fn delete(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const uid = authUserId(ctx) orelse {
                try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                return;
            };
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的通知 ID");
                return;
            };
            _ = self.svc.delete(id, uid) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            try ctx.ok("null");
        }
    };
}

pub const DefaultNotificationApi = NotificationApi(service.NotificationService, user_svc.UserService);
