//! Admin-facing account API — platform console manages site accounts
//! (公众号/小程序/APP) and their WeChat config.

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const mw = @import("../../middleware/auth.zig");
const user_svc = @import("../user/service.zig");
const audit_svc = @import("../audit/service.zig");

const service = @import("service.zig");

const AccountDto = struct {
    id: i64,
    tenant_id: i64,
    name: []const u8,
    kind: []const u8,
    status: []const u8,
    created_at: i64,
    updated_at: i64,
};

fn toAccountDto(row: service.AccountRow) AccountDto {
    return .{
        .id = row.id,
        .tenant_id = row.tenant_id,
        .name = row.name,
        .kind = row.kind,
        .status = row.status,
        .created_at = row.created_at,
        .updated_at = row.updated_at,
    };
}

/// Secrets are never returned by the API — only appid/token/verified.
const WechatDto = struct {
    account_id: i64,
    appid: []const u8,
    token: []const u8,
    verified: bool,
};

const CreateAccountReq = struct {
    name: []const u8,
    kind: []const u8,
};

const UpdateAccountReq = struct {
    name: ?[]const u8 = null,
    kind: ?[]const u8 = null,
    status: ?[]const u8 = null,
};

const SetWechatReq = struct {
    appid: []const u8,
    token: []const u8,
    secret: ?[]const u8 = null,
    encoding_aes_key: ?[]const u8 = null,
    verified: ?bool = null,
};

pub fn AccountApi(comptime Service: type, comptime UserService: type) type {
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
            try g.get("/accounts", list, @ptrCast(@alignCast(self)));
            try g.post("/accounts", create, @ptrCast(@alignCast(self)));
            try g.get("/accounts/{id}", get, @ptrCast(@alignCast(self)));
            try g.put("/accounts/{id}", update, @ptrCast(@alignCast(self)));
            try g.delete("/accounts/{id}", delete, @ptrCast(@alignCast(self)));
            try g.get("/accounts/{id}/wechat", getWechat, @ptrCast(@alignCast(self)));
            try g.put("/accounts/{id}/wechat", setWechat, @ptrCast(@alignCast(self)));
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
            const kind_raw = ctx.queryParam("kind");
            var result = self.svc.list(params.page, params.page_size, tid, kind_raw) catch |err| {
                try ctx.sendErrorResponse(500, 500, @errorName(err));
                return;
            };
            defer result.free(self.svc.allocator);

            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, AccountDto, toAccountDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }

        fn create(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);

            const req = ctx.bindJson(CreateAccountReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer {
                ctx.allocator.free(req.name);
                ctx.allocator.free(req.kind);
            }
            const id = self.svc.create(tid, req.name, req.kind) catch |err| {
                const msg = switch (err) {
                    error.InvalidName => "账号名称不能为空",
                    error.InvalidKind => "账号类型仅支持 wechat/wxapp/app",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            var d1: [128]u8 = undefined;
            const det1 = try std.fmt.bufPrint(&d1, "创建账号 {s} ({s})", .{ req.name, req.kind });
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "account.create", "account", id, det1, zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(201, .{ .code = 0, .msg = "账号已创建", .data = .{ .id = id } });
        }

        fn get(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = (try requireAdmin(ctx, self)) orelse return;

            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的账号 ID");
                return;
            };
            const row_opt = self.svc.get(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            const row = row_opt orelse {
                try ctx.sendErrorResponse(404, 404, "账号不存在");
                return;
            };
            defer row.free(self.svc.allocator);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = toAccountDto(row) });
        }

        fn update(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;

            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的账号 ID");
                return;
            };
            const req = ctx.bindJson(UpdateAccountReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer {
                if (req.name) |n| ctx.allocator.free(n);
                if (req.kind) |k| ctx.allocator.free(k);
                if (req.status) |s| ctx.allocator.free(s);
            }
            const cur_opt = self.svc.get(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            const cur = cur_opt orelse {
                try ctx.sendErrorResponse(404, 404, "账号不存在");
                return;
            };
            defer cur.free(self.svc.allocator);

            const name = req.name orelse cur.name;
            const kind = req.kind orelse cur.kind;
            const status = req.status orelse cur.status;
            _ = self.svc.update(id, name, kind, status) catch |err| {
                const msg = switch (err) {
                    error.InvalidName => "账号名称不能为空",
                    error.InvalidKind => "账号类型仅支持 wechat/wxapp/app",
                    error.InvalidStatus => "状态仅支持 active/disabled",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            var d2: [128]u8 = undefined;
            const det2 = try std.fmt.bufPrint(&d2, "更新账号 #{d} → {s}", .{ id, status });
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "account.update", "account", id, det2, zigmodu.http.RequestUtil.getRealIp(ctx), true, mw.authTenantId(ctx) orelse self.default_tenant_id);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = null });
        }

        fn delete(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;

            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的账号 ID");
                return;
            };
            self.svc.delete(id) catch |err| {
                try ctx.sendErrorResponse(500, 500, @errorName(err));
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "account.delete", "account", id, "删除账号", zigmodu.http.RequestUtil.getRealIp(ctx), true, mw.authTenantId(ctx) orelse self.default_tenant_id);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = null });
        }

        fn getWechat(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = (try requireAdmin(ctx, self)) orelse return;

            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的账号 ID");
                return;
            };
            const row_opt = self.svc.getWechat(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            const row = row_opt orelse {
                try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = null });
                return;
            };
            defer row.free(self.svc.allocator);
            const dto = WechatDto{ .account_id = row.account_id, .appid = row.appid, .token = row.token, .verified = row.verified };
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = dto });
        }

        fn setWechat(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);

            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的账号 ID");
                return;
            };
            const req = ctx.bindJson(SetWechatReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer {
                ctx.allocator.free(req.appid);
                ctx.allocator.free(req.token);
                if (req.secret) |s| ctx.allocator.free(s);
                if (req.encoding_aes_key) |e| ctx.allocator.free(e);
            }
            if (std.mem.trim(u8, req.appid, " \t").len == 0 or std.mem.trim(u8, req.token, " \t").len == 0) {
                try ctx.sendErrorResponse(400, 400, "appid 和 token 不能为空");
                return;
            }

            // Merge: omitted secret/encoding_aes_key keep the stored value.
            var secret_buf: []const u8 = req.secret orelse "";
            var key_buf: []const u8 = req.encoding_aes_key orelse "";
            var verified = req.verified orelse false;
            if (req.secret == null or req.encoding_aes_key == null) {
                if (try self.svc.getWechatConfig(id)) |cfg| {
                    defer cfg.deinit(self.svc.allocator);
                    if (req.secret == null and cfg.secret.len > 0) secret_buf = cfg.secret;
                    if (req.encoding_aes_key == null and cfg.encoding_aes_key.len > 0) key_buf = cfg.encoding_aes_key;
                    verified = req.verified orelse cfg.verified;
                }
            }

            const cfg = service.WechatConfig{
                .appid = req.appid,
                .secret = secret_buf,
                .token = req.token,
                .encoding_aes_key = key_buf,
                .verified = verified,
            };
            _ = self.svc.upsertWechat(tid, id, cfg) catch |err| {
                try ctx.sendErrorResponse(500, 500, @errorName(err));
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "account.wechat", "account", id, "更新微信配置", zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = null });
        }
    };
}

pub const DefaultAccountApi = AccountApi(service.AccountService, user_svc.UserService);
