//! Admin-facing seckill API — 秒杀活动 CRUD + 抢购记录 + 手动抢购。

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const mw = @import("../../middleware/auth.zig");
const user_svc = @import("../user/service.zig");
const audit_svc = @import("../audit/service.zig");

const service = @import("service.zig");

const ActivityDto = struct {
    id: i64,
    account_id: i64,
    title: []const u8,
    price: i64,
    original_price: i64,
    stock: i64,
    sold: i64,
    per_user: i64,
    start_at: i64,
    end_at: i64,
    status: i64,
    created_at: i64,
};

fn toDto(row: service.SeckillActivityRow) ActivityDto {
    return .{
        .id = row.id,
        .account_id = row.account_id,
        .title = row.title,
        .price = std.fmt.parseInt(i64, row.price, 10) catch 0,
        .original_price = std.fmt.parseInt(i64, row.original_price, 10) catch 0,
        .stock = row.stock,
        .sold = row.sold,
        .per_user = row.per_user,
        .start_at = row.start_at,
        .end_at = row.end_at,
        .status = row.status,
        .created_at = row.created_at,
    };
}

const CreateActivityReq = struct {
    account_id: i64,
    title: []const u8,
    price: i64,
    original_price: i64 = 0,
    stock: i64,
    per_user: i64 = 1,
    start_at: i64 = 0,
    end_at: i64 = 0,
    status: i64 = 1,
};

/// 整体更新：字段同 `CreateActivityReq`，不含 account_id（account 作用域不变）。
const UpdateActivityReq = struct {
    title: []const u8,
    price: i64,
    original_price: i64 = 0,
    stock: i64,
    per_user: i64 = 1,
    start_at: i64 = 0,
    end_at: i64 = 0,
    status: i64 = 1,
};

const SetStatusReq = struct {
    status: i64,
};

const RushReq = struct {
    openid: []const u8,
    quantity: i64 = 1,
};

pub fn SeckillApi(comptime Service: type, comptime UserService: type) type {
    return struct {
        const Self = @This();
        svc: *Service,
        user_svc: *UserService,
        audit: *audit_svc.AuditService,
        default_tenant_id: i64,

        pub const module_name = "seckill";
        pub const nest: []const []const u8 = &.{};
        pub const State = Self;

        pub const routes: []const http.RouteSpec(Self) = &.{
            .{ .method = .GET, .path = "seckills", .handler = http.wrapHandler(Self, list), .meta = .{ .permission = "seckill:read" } },
            .{ .method = .POST, .path = "seckills", .handler = http.wrapHandler(Self, create), .meta = .{ .permission = "seckill:write" } },
            .{ .method = .GET, .path = "seckills/{id}", .handler = http.wrapHandler(Self, get), .meta = .{ .permission = "seckill:read" } },
            .{ .method = .PUT, .path = "seckills/{id}", .handler = http.wrapHandler(Self, update), .meta = .{ .permission = "seckill:write" } },
            .{ .method = .DELETE, .path = "seckills/{id}", .handler = http.wrapHandler(Self, delete), .meta = .{ .permission = "seckill:write" } },
            .{ .method = .PUT, .path = "seckills/{id}/status", .handler = http.wrapHandler(Self, setStatus), .meta = .{ .permission = "seckill:write" } },
            .{ .method = .GET, .path = "seckills/orders", .handler = http.wrapHandler(Self, orders), .meta = .{ .permission = "seckill:read" } },
            .{ .method = .POST, .path = "seckills/{id}/rush", .handler = http.wrapHandler(Self, rush), .meta = .{ .permission = "seckill:write" } },
        };

        pub fn init(svc: *Service, users: *UserService, audit: *audit_svc.AuditService, default_tenant_id: i64) Self {
            return .{ .svc = svc, .user_svc = users, .audit = audit, .default_tenant_id = default_tenant_id };
        }

        pub fn registerRoutes(self: *Self, group: *http.RouteGroup) !void {
            var g = try group.use(zigmodu.http.http_middleware.jwtAuthWithSecurity(&self.user_svc.sec.module));
            g = try g.use(mw.tokenVersionGuard(self.user_svc.sec, self.user_svc.store));
            try g.get("/seckills", list, @ptrCast(@alignCast(self)));
            try g.post("/seckills", create, @ptrCast(@alignCast(self)));
            try g.get("/seckills/{id}", get, @ptrCast(@alignCast(self)));
            try g.put("/seckills/{id}", update, @ptrCast(@alignCast(self)));
            try g.delete("/seckills/{id}", delete, @ptrCast(@alignCast(self)));
            try g.put("/seckills/{id}/status", setStatus, @ptrCast(@alignCast(self)));
            try g.get("/seckills/orders", orders, @ptrCast(@alignCast(self)));
            try g.post("/seckills/{id}/rush", rush, @ptrCast(@alignCast(self)));
        }

        fn setAuditActor(ctx: *http.Context, self: *Self) !void {
            const uid = ctx.userIdInt(i64) orelse return;
            const row_opt = self.user_svc.getUserById(uid) catch return;
            const row = row_opt orelse return;
            defer row.free(self.user_svc.store.allocator);
            try ctx.setAttr("audit_actor", row.name);
        }

        fn requireAdmin(ctx: *http.Context, self: *Self) !?i64 {
            const uid = ctx.userIdInt(i64) orelse {
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
            try setAuditActor(ctx, self);
            const tid = tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const keyword = ctx.queryStr("keyword", "");
            const status = ctx.queryInt(i64, "status", -1);
            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 100 });
            var result = self.svc.listActivities(params.page, params.page_size, tid, account_id, keyword, status) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer result.free(self.svc.allocator);
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, ActivityDto, toDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }

        /// 上下架：body `{"status": 1|0}`。
        fn setStatus(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const admin_id = ctx.userIdInt(i64) orelse return;
            const tid = tenantScope(ctx, self);
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的活动 ID");
                return;
            };
            const req = ctx.bindJson(SetStatusReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            if (req.status != 0 and req.status != 1) {
                try ctx.sendErrorResponse(400, 400, "status 只能为 0 或 1");
                return;
            }
            const ok = self.svc.setActivityStatus(id, req.status) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            if (!ok) {
                try ctx.sendErrorResponse(404, 404, "活动不存在");
                return;
            }
            const action = if (req.status == 1) "上架" else "下架";
            var d: [128]u8 = undefined;
            const det = try std.fmt.bufPrint(&d, "{s}秒杀活动 #{d}", .{ action, id });
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "seckill.status", "seckill_activity", id, det, zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.ok("null");
        }

        fn create(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const admin_id = ctx.userIdInt(i64) orelse return;
            const tid = tenantScope(ctx, self);
            const req = ctx.bindJson(CreateActivityReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer {
                ctx.allocator.free(req.title);
            }
            const id = self.svc.createActivity(tid, req.account_id, req.title, req.price, req.original_price, req.stock, req.per_user, req.start_at, req.end_at, req.status) catch |err| {
                try ctx.sendErrorResponse(400, 400, @errorName(err));
                return;
            };
            var d1: [128]u8 = undefined;
            const det1 = try std.fmt.bufPrint(&d1, "创建秒杀 {s}", .{req.title});
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "seckill.create", "seckill_activity", id, det1, zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.okValue(.{ .id = id });
        }

        /// 单条详情（tenant 过滤）：活动不存在或不属于本 tenant 均 404。DTO 与列表同构。
        fn get(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const tid = tenantScope(ctx, self);
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的活动 ID");
                return;
            };
            const row_opt = self.svc.getActivityById(tid, id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            const row = row_opt orelse {
                try ctx.sendErrorResponse(404, 404, "活动不存在");
                return;
            };
            defer row.free(self.svc.allocator);
            try ctx.okValue(toDto(row));
        }

        /// 整体更新活动（account 作用域不变）。请求体同 `CreateActivityReq` 去 account_id。
        fn update(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const admin_id = ctx.userIdInt(i64) orelse return;
            const tid = tenantScope(ctx, self);
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的活动 ID");
                return;
            };
            const req = ctx.bindJson(UpdateActivityReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer ctx.allocator.free(req.title);
            self.svc.updateActivity(tid, id, req.title, req.price, req.original_price, req.stock, req.per_user, req.start_at, req.end_at, req.status) catch |err| switch (err) {
                error.NotFound => {
                    try ctx.sendErrorResponse(404, 404, "活动不存在");
                    return;
                },
                error.InvalidInput => {
                    try ctx.sendErrorResponse(400, 400, "参数非法");
                    return;
                },
                else => {
                    try ctx.sendErrorResponse(500, 500, "服务器错误");
                    return;
                },
            };
            var d1: [128]u8 = undefined;
            const det1 = try std.fmt.bufPrint(&d1, "更新秒杀活动 #{d}", .{id});
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "seckill.update", "seckill_activity", id, det1, zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.okValue(.{ .id = id });
        }

        /// 删除活动及其抢购记录（先删订单再删活动）。
        fn delete(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const admin_id = ctx.userIdInt(i64) orelse return;
            const tid = tenantScope(ctx, self);
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的活动 ID");
                return;
            };
            self.svc.deleteActivity(tid, id) catch |err| switch (err) {
                error.NotFound => {
                    try ctx.sendErrorResponse(404, 404, "活动不存在");
                    return;
                },
                else => {
                    try ctx.sendErrorResponse(500, 500, "服务器错误");
                    return;
                },
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "seckill.delete", "seckill_activity", id, "删除秒杀活动", zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.ok("null");
        }

        fn orders(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const tid = tenantScope(ctx, self);
            const account_id = ctx.queryInt(i64, "account_id", 0);
            const keyword = ctx.queryStr("keyword", "");
            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 100 });
            var result = self.svc.listOrders(params.page, params.page_size, tid, account_id, "", keyword) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer result.free(ctx.allocator);
            // 每行按 activity_id 补齐活动标题（页 ≤ 100，逐行小查询可接受）。
            const rows = self.svc.enrichOrders(ctx.allocator, tid, result.items) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer {
                for (rows) |v| v.free(ctx.allocator);
                ctx.allocator.free(rows);
            }
            try zigmodu.http.sendPaged(ctx, rows, @intCast(result.total), params, .ruoyi);
        }

        fn rush(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const admin_id = ctx.userIdInt(i64) orelse return;
            const tid = tenantScope(ctx, self);
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的活动 ID");
                return;
            };
            const req = ctx.bindJson(RushReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer ctx.allocator.free(req.openid);
            _ = self.svc.rush(tid, 0, req.openid, id, req.quantity) catch |err| {
                const msg = switch (err) {
                    error.OutOfStock => "已抢光",
                    error.LimitReached => "超过限购",
                    error.NotStarted => "未开始",
                    error.Ended => "已结束",
                    error.NotFound => "活动不存在",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "seckill.rush", "seckill_order", id, "手动抢购", zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.ok("null");
        }
    };
}

pub const DefaultSeckillApi = SeckillApi(service.SeckillService, user_svc.UserService);
