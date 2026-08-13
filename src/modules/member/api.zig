//! Admin-facing fan API — list/query WeChat fans of an account.

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const mw = @import("../../middleware/auth.zig");
const user_svc = @import("../user/service.zig");
const audit_svc = @import("../audit/service.zig");

const service = @import("service.zig");

const FanDto = struct {
    id: i64,
    account_id: i64,
    openid: []const u8,
    unionid: []const u8,
    nickname: []const u8,
    avatar: []const u8,
    subscribed: bool,
    subscribe_time: i64,
    created_at: i64,
};

fn toFanDto(row: service.FanRow) FanDto {
    return .{
        .id = row.id,
        .account_id = row.account_id,
        .openid = row.openid,
        .unionid = row.unionid,
        .nickname = row.nickname,
        .avatar = row.avatar,
        .subscribed = row.subscribed,
        .subscribe_time = row.subscribe_time,
        .created_at = row.created_at,
    };
}

pub fn MemberApi(comptime Service: type, comptime UserService: type) type {
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
            try g.get("/fans", list, @ptrCast(@alignCast(self)));
            try g.get("/fans/{id}", get, @ptrCast(@alignCast(self)));
            try g.get("/accounts/{id}/fans/tags", listTags, @ptrCast(@alignCast(self)));
            try g.post("/accounts/{id}/fans/tags", createTag, @ptrCast(@alignCast(self)));
            try g.post("/fans/tag", tagFan, @ptrCast(@alignCast(self)));
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

            const account_raw = ctx.queryParam("account_id") orelse {
                try ctx.sendErrorResponse(400, 400, "缺少 account_id");
                return;
            };
            const account_id = std.fmt.parseInt(i64, account_raw, 10) catch {
                try ctx.sendErrorResponse(400, 400, "无效的 account_id");
                return;
            };
            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 100 });
            const keyword = ctx.queryParam("keyword");
            var subscribed_only = false;
            if (ctx.queryParam("subscribed")) |s| {
                subscribed_only = std.mem.eql(u8, s, "1") or std.mem.eql(u8, s, "true");
            }
            var result = self.svc.list(params.page, params.page_size, tid, account_id, keyword, subscribed_only) catch |err| {
                try ctx.sendErrorResponse(500, 500, @errorName(err));
                return;
            };
            defer result.free(self.svc.allocator);

            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, FanDto, toFanDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }

        fn get(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = (try requireAdmin(ctx, self)) orelse return;

            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的粉丝 ID");
                return;
            };
            const row_opt = self.svc.get(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            const row = row_opt orelse {
                try ctx.sendErrorResponse(404, 404, "粉丝不存在");
                return;
            };
            defer row.free(self.svc.allocator);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = toFanDto(row) });
        }

        fn listTags(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = (try requireAdmin(ctx, self)) orelse return;
            const tid = mw.authTenantId(ctx) orelse self.default_tenant_id;
            const account_id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的账号 ID");
                return;
            };
            const rows = self.svc.listWxTags(tid, account_id) catch |err| {
                const msg = switch (err) {
                    error.TagStoreUnavailable => "标签服务未就绪",
                    error.TokenCacheUnavailable => "access_token 缓存未就绪",
                    error.NotFound => "账号不存在",
                    error.WechatApiError => "微信接口调用失败",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            defer {
                for (rows) |r| r.free(ctx.allocator);
                ctx.allocator.free(rows);
            }
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = .{ .items = rows } });
        }

        fn createTag(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = mw.authTenantId(ctx) orelse self.default_tenant_id;
            const account_id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的账号 ID");
                return;
            };
            const req = ctx.bindJson(struct { name: []const u8 }) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer ctx.allocator.free(req.name);
            const wx_tag_id = self.svc.createWxTag(tid, account_id, req.name) catch |err| {
                const msg = switch (err) {
                    error.InvalidName => "标签名不能为空",
                    error.TagStoreUnavailable => "标签服务未就绪",
                    error.TokenCacheUnavailable => "access_token 缓存未就绪",
                    error.NotFound => "账号不存在",
                    error.WechatApiError => "微信接口调用失败",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "member.tag.create", "member", account_id, "创建粉丝标签", zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(201, .{ .code = 0, .msg = "已创建", .data = .{ .wx_tag_id = wx_tag_id } });
        }

        fn tagFan(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = mw.authTenantId(ctx) orelse self.default_tenant_id;
            const req = ctx.bindJson(struct { account_id: i64, openid: []const u8, tag_id: i64 }) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer ctx.allocator.free(req.openid);
            self.svc.tagFan(req.account_id, req.openid, req.tag_id) catch |err| {
                const msg = switch (err) {
                    error.InvalidOpenid => "openid 不能为空",
                    error.TokenCacheUnavailable => "access_token 缓存未就绪",
                    error.NotFound => "账号不存在",
                    error.WechatApiError => "微信接口调用失败",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "member.tag.fan", "member", req.account_id, "粉丝打标签", zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "已打标签", .data = null });
        }
    };
}

pub const DefaultMemberApi = MemberApi(service.MemberService, user_svc.UserService);
