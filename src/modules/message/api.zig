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

const CustomerTextReq = struct {
    account_id: i64,
    openid: []const u8,
    content: []const u8,
};

const TemplateDataDto = struct {
    key: []const u8,
    value: []const u8,
    color: []const u8 = "",
};

const SendTemplateReq = struct {
    account_id: i64,
    openid: []const u8,
    template_id: []const u8,
    data: []TemplateDataDto,
};

const BroadcastTextReq = struct {
    account_id: i64,
    tag_id: i64 = 0,
    content: []const u8,
};

const DatacubeReq = struct {
    account_id: i64,
    api: []const u8,
    begin_date: []const u8,
    end_date: []const u8,
};

const MiniLoginReq = struct {
    account_id: i64,
    code: []const u8,
};

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
            try g.post("/messages/customer-text", sendCustomerText, @ptrCast(@alignCast(self)));
            try g.post("/messages/template", sendTemplate, @ptrCast(@alignCast(self)));
            try g.post("/messages/broadcast", sendBroadcast, @ptrCast(@alignCast(self)));
            try g.post("/statistics/datacube", getDatacube, @ptrCast(@alignCast(self)));
            try g.post("/miniprogram/login", miniLogin, @ptrCast(@alignCast(self)));
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
                    error.TimestampExpired => try ctx.sendErrorResponse(403, 403, "请求时间戳已过期"),
                    error.ReplayDetected => try ctx.sendErrorResponse(403, 403, "重复请求"),
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

        fn sendCustomerText(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = mw.authTenantId(ctx) orelse self.default_tenant_id;

            const req = ctx.bindJson(CustomerTextReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer {
                ctx.allocator.free(req.openid);
                ctx.allocator.free(req.content);
            }
            self.svc.sendCustomerText(req.account_id, req.openid, req.content) catch |err| {
                const msg = switch (err) {
                    error.TokenCacheUnavailable => "access_token 缓存未就绪",
                    error.AccountNotFound => "账号不存在",
                    error.WechatApiError => "微信接口调用失败",
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "message.customer.send", "message", req.account_id, "发送客服消息", zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "已发送", .data = null });
        }

        fn sendTemplate(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = mw.authTenantId(ctx) orelse self.default_tenant_id;

            const req = ctx.bindJson(SendTemplateReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer {
                ctx.allocator.free(req.openid);
                ctx.allocator.free(req.template_id);
                for (req.data) |d| {
                    ctx.allocator.free(d.key);
                    ctx.allocator.free(d.value);
                    if (d.color.len > 0) ctx.allocator.free(d.color);
                }
                ctx.allocator.free(req.data);
            }

            const items = ctx.allocator.alloc(service.TemplateDataItem, req.data.len) catch {
                try ctx.sendErrorResponse(500, 500, "内存不足");
                return;
            };
            defer ctx.allocator.free(items);
            for (req.data, 0..) |d, i| {
                items[i] = .{ .key = d.key, .value = d.value, .color = d.color };
            }

            const msgid = self.svc.sendTemplate(req.account_id, req.openid, req.template_id, items) catch |err| {
                const msg = switch (err) {
                    error.TokenCacheUnavailable => "access_token 缓存未就绪",
                    error.AccountNotFound => "账号不存在",
                    error.WechatApiError => "微信接口调用失败",
                    error.OutOfMemory => "内存不足",
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "message.template.send", "message", req.account_id, "发送模板消息", zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "已发送", .data = .{ .msgid = msgid } });
        }

        fn sendBroadcast(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = mw.authTenantId(ctx) orelse self.default_tenant_id;

            const req = ctx.bindJson(BroadcastTextReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer ctx.allocator.free(req.content);
            const msgid = self.svc.sendBroadcastText(req.account_id, req.tag_id, req.content) catch |err| {
                const msg = switch (err) {
                    error.TokenCacheUnavailable => "access_token 缓存未就绪",
                    error.AccountNotFound => "账号不存在",
                    error.WechatApiError => "微信接口调用失败",
                    error.WriteFailed => "请求构造失败",
                    error.OutOfMemory => "内存不足",
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "message.broadcast.send", "message", req.account_id, "群发文本消息", zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "已群发", .data = .{ .msgid = msgid } });
        }

        fn getDatacube(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = (try requireAdmin(ctx, self)) orelse return;

            const req = ctx.bindJson(DatacubeReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer {
                ctx.allocator.free(req.api);
                ctx.allocator.free(req.begin_date);
                ctx.allocator.free(req.end_date);
            }
            const data = self.svc.getDatacube(req.account_id, req.api, req.begin_date, req.end_date) catch |err| {
                const msg = switch (err) {
                    error.InvalidDatacubeApi => "不支持的统计接口",
                    error.InvalidDate => "日期不能为空",
                    error.TokenCacheUnavailable => "access_token 缓存未就绪",
                    error.AccountNotFound => "账号不存在",
                    error.WechatApiError => "微信接口调用失败",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            defer ctx.allocator.free(data);
            // 透传微信返回的原始 JSON。
            try ctx.text(200, data);
        }

        fn miniLogin(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = (try requireAdmin(ctx, self)) orelse return;

            const req = ctx.bindJson(MiniLoginReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer ctx.allocator.free(req.code);
            const openid = self.svc.miniLogin(req.account_id, req.code) catch |err| {
                const msg = switch (err) {
                    error.AccountNotFound => "账号不存在",
                    error.WechatApiError => "微信接口调用失败（code 无效或已过期）",
                    error.OutOfMemory => "内存不足",
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            defer ctx.allocator.free(openid);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = .{ .openid = openid } });
        }
    };
}

pub const DefaultMessageApi = MessageApi(service.WechatService, user_svc.UserService);
