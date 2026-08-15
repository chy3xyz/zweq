//! Admin-facing member_card API — 卡等级 CRUD + 会员列表 + 开卡/查卡/积分调整。

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const mw = @import("../../middleware/auth.zig");
const user_svc = @import("../user/service.zig");
const audit_svc = @import("../audit/service.zig");

const service = @import("service.zig");

const LevelDto = struct {
    id: i64,
    account_id: i64,
    name: []const u8,
    level: i64,
    discount: i64,
    points_ratio: i64,
    threshold: i64,
    created_at: i64,
};

fn toDto(row: service.MemberCardLevelRow) LevelDto {
    return .{
        .id = row.id,
        .account_id = row.account_id,
        .name = row.name,
        .level = row.level,
        .discount = row.discount,
        .points_ratio = row.points_ratio,
        .threshold = row.threshold,
        .created_at = row.created_at,
    };
}

const CreateLevelReq = struct {
    account_id: i64,
    name: []const u8,
    level: i64 = 1,
    discount: i64 = 1000,
    points_ratio: i64 = 100,
    threshold: i64 = 0,
};

const OpenReq = struct {
    openid: []const u8,
};

const AdjustReq = struct {
    openid: []const u8,
    delta: i64,
};

pub fn MemberCardApi(comptime Service: type, comptime UserService: type) type {
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
            try g.get("/member-cards", listLevels, @ptrCast(@alignCast(self)));
            try g.post("/member-cards", createLevel, @ptrCast(@alignCast(self)));
            try g.get("/member-cards/members", listMembers, @ptrCast(@alignCast(self)));
            try g.get("/member-cards/view", view, @ptrCast(@alignCast(self)));
            try g.post("/member-cards/open", open, @ptrCast(@alignCast(self)));
            try g.post("/member-cards/adjust", adjust, @ptrCast(@alignCast(self)));
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

        fn listLevels(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 100 });
            var result = self.svc.listLevels(params.page, params.page_size, tid, account_id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer result.free(self.svc.allocator);
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, LevelDto, toDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }

        fn createLevel(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);
            const req = ctx.bindJson(CreateLevelReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer ctx.allocator.free(req.name);
            const id = self.svc.createLevel(tid, req.account_id, req.name, req.level, req.discount, req.points_ratio, req.threshold) catch |err| {
                try ctx.sendErrorResponse(400, 400, @errorName(err));
                return;
            };
            var d1: [128]u8 = undefined;
            const det1 = try std.fmt.bufPrint(&d1, "创建会员等级 {s}", .{req.name});
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "member_card.create_level", "member_card_level", id, det1, zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(201, .{ .code = 0, .msg = "已创建", .data = .{ .id = id } });
        }

        fn listMembers(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 100 });
            const result = self.svc.listAccounts(params.page, params.page_size, tid, account_id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer {
                for (result.items) |r| r.free(ctx.allocator);
                ctx.allocator.free(result.items);
            }
            try zigmodu.http.sendPaged(ctx, result.items, @intCast(result.total), params, .ruoyi);
        }

        fn view(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const openid = ctx.query.get("openid") orelse {
                try ctx.sendErrorResponse(400, 400, "缺少 openid");
                return;
            };
            const v_opt = self.svc.view(tid, account_id, openid) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            var v = v_opt orelse {
                try ctx.jsonStruct(200, .{ .code = 0, .msg = "未办卡", .data = null });
                return;
            };
            defer v.free(ctx.allocator);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = v });
        }

        fn open(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const req = ctx.bindJson(OpenReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer ctx.allocator.free(req.openid);
            self.svc.openCard(tid, account_id, req.openid) catch |err| switch (err) {
                error.AlreadyOpened => {
                    try ctx.sendErrorResponse(400, 400, "已办卡");
                    return;
                },
                else => {
                    try ctx.sendErrorResponse(400, 400, @errorName(err));
                    return;
                },
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "member_card.open", "member_account", 0, "手动开卡", zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "开卡成功", .data = null });
        }

        fn adjust(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const req = ctx.bindJson(AdjustReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer ctx.allocator.free(req.openid);
            self.svc.adjust(tid, account_id, req.openid, req.delta) catch |err| {
                const msg = switch (err) {
                    error.NotFound => "未办卡",
                    error.InsufficientPoints => "积分不足",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            var d1: [128]u8 = undefined;
            const det1 = try std.fmt.bufPrint(&d1, "积分调整 {d}", .{req.delta});
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "member_card.adjust", "member_account", 0, det1, zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "已调整", .data = null });
        }
    };
}

pub const DefaultMemberCardApi = MemberCardApi(service.MemberCardService, user_svc.UserService);
