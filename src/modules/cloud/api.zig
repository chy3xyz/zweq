//! Admin-facing cloud API — licenses (授权码) + marketplace (应用市场).

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const mw = @import("../../middleware/auth.zig");
const user_svc = @import("../user/service.zig");
const audit_svc = @import("../audit/service.zig");

const service = @import("service.zig");

const LicenseDto = struct {
    id: i64,
    license_key: []const u8,
    status: []const u8,
    expires_at: i64,
    created_at: i64,
};

fn toLicenseDto(row: service.LicenseRow) LicenseDto {
    return .{
        .id = row.id,
        .license_key = row.license_key,
        .status = row.status,
        .expires_at = row.expires_at,
        .created_at = row.created_at,
    };
}

const MarketDto = struct {
    id: i64,
    name: []const u8,
    title: []const u8,
    version: []const u8,
    description: []const u8,
    download_url: []const u8,
    updated_at: i64,
};

fn toMarketDto(row: service.MarketPackageRow) MarketDto {
    return .{
        .id = row.id,
        .name = row.name,
        .title = row.title,
        .version = row.version,
        .description = row.description,
        .download_url = row.download_url,
        .updated_at = row.updated_at,
    };
}

const GenerateLicenseReq = struct {
    days: i64,
};

const VerifyLicenseReq = struct {
    key: []const u8,
};

const PublishPackageReq = struct {
    name: []const u8,
    title: []const u8,
    version: []const u8,
    description: []const u8,
    download_url: []const u8,
};

const InstallPackageReq = struct {
    account_id: i64,
};

pub fn CloudApi(comptime Service: type, comptime UserService: type) type {
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
            try g.post("/cloud/licenses", generateLicense, @ptrCast(@alignCast(self)));
            try g.get("/cloud/licenses", listLicenses, @ptrCast(@alignCast(self)));
            try g.post("/cloud/licenses/{id}/revoke", revokeLicense, @ptrCast(@alignCast(self)));
            try g.post("/cloud/licenses/verify", verifyLicense, @ptrCast(@alignCast(self)));
            try g.get("/cloud/market", listMarket, @ptrCast(@alignCast(self)));
            try g.post("/cloud/market", publishPackage, @ptrCast(@alignCast(self)));
            try g.post("/cloud/market/{name}/install", installPackage, @ptrCast(@alignCast(self)));
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

        fn generateLicense(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);

            const req = ctx.bindJson(GenerateLicenseReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            const row = self.svc.generateLicense(ctx.allocator, tid, req.days) catch |err| {
                const msg = switch (err) {
                    error.InvalidDays => "授权天数必须大于 0",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            defer row.free(self.svc.allocator);
            var d1: [160]u8 = undefined;
            const det1 = try std.fmt.bufPrint(&d1, "生成授权码 {s} ({d}天)", .{ row.license_key, req.days });
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "cloud.license.issue", "cloud", row.id, det1, zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(201, .{ .code = 0, .msg = "授权码已生成", .data = toLicenseDto(row) });
        }

        fn listLicenses(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);

            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 100 });
            var result = self.svc.listLicenses(params.page, params.page_size, tid) catch |err| {
                try ctx.sendErrorResponse(500, 500, @errorName(err));
                return;
            };
            defer result.free(self.svc.allocator);
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, LicenseDto, toLicenseDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }

        fn revokeLicense(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;

            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的授权码 ID");
                return;
            };
            self.svc.revokeLicense(id) catch |err| {
                try ctx.sendErrorResponse(500, 500, @errorName(err));
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "cloud.license.revoke", "cloud", id, "撤销授权码", zigmodu.http.RequestUtil.getRealIp(ctx), true, tenantScope(ctx, self));
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "已撤销", .data = null });
        }

        fn verifyLicense(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);

            const req = ctx.bindJson(VerifyLicenseReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer ctx.allocator.free(req.key);
            const valid = self.svc.verifyLicense(tid, req.key) catch |err| {
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

        fn listMarket(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);

            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 100 });
            var result = self.svc.listMarket(params.page, params.page_size, tid) catch |err| {
                try ctx.sendErrorResponse(500, 500, @errorName(err));
                return;
            };
            defer result.free(self.svc.allocator);
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, MarketDto, toMarketDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }

        fn publishPackage(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);

            const req = ctx.bindJson(PublishPackageReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer {
                ctx.allocator.free(req.name);
                ctx.allocator.free(req.title);
                ctx.allocator.free(req.version);
                ctx.allocator.free(req.description);
                ctx.allocator.free(req.download_url);
            }
            const id = self.svc.publishPackage(tid, req.name, req.title, req.version, req.description, req.download_url) catch |err| {
                try ctx.sendErrorResponse(400, 400, @errorName(err));
                return;
            };
            var d1: [128]u8 = undefined;
            const det1 = try std.fmt.bufPrint(&d1, "发布市场包 {s} v{s}", .{ req.name, req.version });
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "cloud.market.publish", "cloud", id, det1, zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(201, .{ .code = 0, .msg = "已发布", .data = .{ .id = id } });
        }

        fn installPackage(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);

            const name = ctx.param("name") orelse {
                try ctx.sendErrorResponse(400, 400, "缺少包名");
                return;
            };
            const req = ctx.bindJson(InstallPackageReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            const module_id = self.svc.installPackage(tid, name, req.account_id) catch |err| {
                const msg = switch (err) {
                    error.InvalidName => "包名不能为空",
                    error.NotFound => "市场包不存在",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            var d1: [128]u8 = undefined;
            const det1 = try std.fmt.bufPrint(&d1, "安装市场包 {s} → 模块 #{d}", .{ name, module_id });
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "cloud.market.install", "cloud", module_id, det1, zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "已安装", .data = .{ .module_id = module_id } });
        }
    };
}

pub const DefaultCloudApi = CloudApi(service.CloudService, user_svc.UserService);
