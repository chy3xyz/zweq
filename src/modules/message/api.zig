//! WeChat server callback API — PUBLIC routes on `/wx/{token}` (no JWT,
//! signature-verified) plus an admin log view under `/api/v1/message-logs`.

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const mw = @import("../../middleware/auth.zig");
const user_svc = @import("../user/service.zig");
const audit_svc = @import("../audit/service.zig");

const service = @import("service.zig");

const LogDto = struct {
    id: i64,
    account_id: i64,
    msg_id: []const u8,
    openid: []const u8,
    msg_type: []const u8,
    event: []const u8,
    content: []const u8,
    reply_type: []const u8,
    reply_content: []const u8,
    created_at: i64,
};

fn toLogDto(row: service.MessageLogRow) LogDto {
    return .{
        .id = row.id,
        .account_id = row.account_id,
        .msg_id = row.msg_id,
        .openid = row.openid,
        .msg_type = row.msg_type,
        .event = row.event,
        .content = row.content,
        .reply_type = row.reply_type,
        .reply_content = row.reply_content,
        .created_at = row.created_at,
    };
}

pub fn MessageApi(comptime Service: type, comptime UserService: type) type {
    return struct {
        const Self = @This();
        svc: *Service,
        user_svc: *UserService,
        audit: *audit_svc.AuditService,
        default_tenant_id: i64,

        pub fn init(svc: *Service, users: *UserService, audit: *audit_svc.AuditService, default_tenant_id: i64) Self {
            return .{ .svc = svc, .user_svc = users, .audit = audit, .default_tenant_id = default_tenant_id };
        }

        /// WeChat push endpoint — public, signature-verified inside the service.
        pub fn registerPublicRoutes(self: *Self, group: *http.RouteGroup) !void {
            try group.get("/{token}", handle, @ptrCast(@alignCast(self)));
            try group.post("/{token}", handle, @ptrCast(@alignCast(self)));
        }

        /// Admin message-log view (JWT).
        pub fn registerAdminRoutes(self: *Self, group: *http.RouteGroup) !void {
            var g = try group.use(zigmodu.http.http_middleware.jwtAuthWithSecurity(&self.user_svc.sec.module));
            g = try g.use(mw.tokenVersionGuard(self.user_svc.sec, self.user_svc.store));
            try g.get("/message-logs", listLogs, @ptrCast(@alignCast(self)));
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

        fn handle(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const token = ctx.param("token") orelse {
                try ctx.sendErrorResponse(400, 400, "缺少 token");
                return;
            };
            const q = service.CallbackQuery{
                .signature = ctx.queryParam("signature") orelse "",
                .timestamp = ctx.queryParam("timestamp") orelse "",
                .nonce = ctx.queryParam("nonce") orelse "",
                .echostr = ctx.queryParam("echostr") orelse "",
                .msg_signature = ctx.queryParam("msg_signature") orelse "",
                .encrypt_type = ctx.queryParam("encrypt_type") orelse "",
            };
            const body = ctx.body orelse "";
            const reply = self.svc.handleCallback(ctx.allocator, token, q, body) catch |err| {
                switch (err) {
                    error.SignatureMismatch => try ctx.sendErrorResponse(403, 403, "签名校验失败"),
                    error.AccountNotFound => try ctx.sendErrorResponse(404, 404, "账号不存在"),
                    else => try ctx.sendErrorResponse(500, 500, @errorName(err)),
                }
                return;
            };
            defer ctx.allocator.free(reply);
            try ctx.text(200, reply);
        }

        fn listLogs(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = (try requireAdmin(ctx, self)) orelse return;
            const tid = mw.authTenantId(ctx) orelse self.default_tenant_id;

            const account_raw = ctx.queryParam("account_id") orelse {
                try ctx.sendErrorResponse(400, 400, "缺少 account_id");
                return;
            };
            const account_id = std.fmt.parseInt(i64, account_raw, 10) catch {
                try ctx.sendErrorResponse(400, 400, "无效的 account_id");
                return;
            };
            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 100 });
            var result = self.svc.listLogs(params.page, params.page_size, tid, account_id) catch |err| {
                try ctx.sendErrorResponse(500, 500, @errorName(err));
                return;
            };
            defer result.free(self.svc.allocator);

            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, LogDto, toLogDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }
    };
}

pub const DefaultMessageApi = MessageApi(service.WechatService, user_svc.UserService);
