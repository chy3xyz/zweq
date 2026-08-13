//! License API — 管理端（Bearer token）发行/撤销/列表 + 站点端校验。

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;

const service = @import("service.zig");

const LicenseDto = struct {
    id: i64,
    license_key: []const u8,
    status: []const u8,
    expires_at: i64,
    created_at: i64,
};

fn toDto(row: service.LicenseRow) LicenseDto {
    return .{ .id = row.id, .license_key = row.license_key, .status = row.status, .expires_at = row.expires_at, .created_at = row.created_at };
}

const GenerateReq = struct {
    days: i64,
};

const VerifyReq = struct {
    key: []const u8,
};

const RevokeReq = struct {
    id: i64,
};

pub fn LicenseApi(comptime Service: type) type {
    return struct {
        const Self = @This();
        svc: *Service,
        admin_token: []const u8,

        pub fn init(svc: *Service, admin_token: []const u8) Self {
            return .{ .svc = svc, .admin_token = admin_token };
        }

        pub fn registerRoutes(self: *Self, group: *http.RouteGroup) !void {
            // 管理接口（Bearer token）。
            var admin = try group.use(http_mw.bearerAuth(self.admin_token));
            try admin.post("/cloud/licenses", generate, @ptrCast(@alignCast(self)));
            try admin.get("/cloud/licenses", list, @ptrCast(@alignCast(self)));
            try admin.post("/cloud/licenses/revoke", revoke, @ptrCast(@alignCast(self)));
            // 站点端校验（公开，无鉴权——授权码本身是凭据）。
            try group.post("/cloud/licenses/verify", verify, @ptrCast(@alignCast(self)));
        }

        fn generate(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const req = ctx.bindJson(GenerateReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            var row = self.svc.generate(ctx.allocator, req.days) catch |err| {
                const msg = switch (err) {
                    error.InvalidDays => "天数必须大于 0",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            defer row.free(ctx.allocator);
            try ctx.jsonStruct(201, .{ .code = 0, .msg = "已生成", .data = toDto(row) });
        }

        fn list(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 100 });
            var result = self.svc.list(params.page, params.page_size) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer result.free(ctx.allocator);
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, LicenseDto, toDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }

        fn revoke(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const req = ctx.bindJson(RevokeReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            self.svc.revoke(req.id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "已撤销", .data = null });
        }

        fn verify(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const req = ctx.bindJson(VerifyReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer ctx.allocator.free(req.key);
            const valid = self.svc.verify(req.key) catch |err| {
                const reason = switch (err) {
                    error.InvalidLicense => "invalid",
                    error.LicenseExpired => "expired",
                    else => "error",
                };
                try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = .{ .valid = false, .reason = reason } });
                return;
            };
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = .{ .valid = valid, .reason = "ok" } });
        }
    };
}

/// 简单的 Bearer token 鉴权中间件。
pub const http_mw = struct {
    const Stored = struct { token: []const u8 };

    pub fn bearerAuth(token: []const u8) http.Middleware {
        const stored = std.heap.page_allocator.create(Stored) catch unreachable;
        stored.* = .{ .token = token };
        return .{
            .func = struct {
                fn handle(ctx: *http.Context, next: http.HandlerFn, user_data: ?*anyopaque) anyerror!void {
                    const s: *const Stored = @ptrCast(@alignCast(user_data.?));
                    const hdr = ctx.header("authorization") orelse {
                        try ctx.sendErrorResponse(401, 401, "未授权");
                        return;
                    };
                    const prefix = "Bearer ";
                    if (hdr.len <= prefix.len or !std.mem.eql(u8, hdr[0..prefix.len], prefix) or !std.mem.eql(u8, hdr[prefix.len..], s.token)) {
                        try ctx.sendErrorResponse(401, 401, "未授权");
                        return;
                    }
                    try next(ctx);
                }
            }.handle,
            .user_data = stored,
        };
    }
};
