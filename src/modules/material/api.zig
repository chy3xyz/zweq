//! Admin-facing material API — 图文素材 + 图片/语音/视频素材。

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const mw = @import("../../middleware/auth.zig");
const user_svc = @import("../user/service.zig");
const audit_svc = @import("../audit/service.zig");

const service = @import("service.zig");

const NewsDto = struct {
    id: i64,
    account_id: i64,
    title: []const u8,
    author: []const u8,
    digest: []const u8,
    content: []const u8,
    thumb_media_id: []const u8,
    thumb_url: []const u8,
    url: []const u8,
    created_at: i64,
    updated_at: i64,
};

fn toNewsDto(row: service.MaterialNewsRow) NewsDto {
    return .{
        .id = row.id,
        .account_id = row.account_id,
        .title = row.title,
        .author = row.author,
        .digest = row.digest,
        .content = row.content,
        .thumb_media_id = row.thumb_media_id,
        .thumb_url = row.thumb_url,
        .url = row.url,
        .created_at = row.created_at,
        .updated_at = row.updated_at,
    };
}

const FileDto = struct {
    id: i64,
    account_id: i64,
    kind: []const u8,
    media_id: []const u8,
    url: []const u8,
    created_at: i64,
};

fn toFileDto(row: service.MaterialFileRow) FileDto {
    return .{
        .id = row.id,
        .account_id = row.account_id,
        .kind = row.kind,
        .media_id = row.media_id,
        .url = row.url,
        .created_at = row.created_at,
    };
}

const CreateNewsReq = struct {
    account_id: i64,
    title: []const u8,
    author: ?[]const u8 = null,
    digest: ?[]const u8 = null,
    content: ?[]const u8 = null,
    thumb_media_id: ?[]const u8 = null,
    thumb_url: ?[]const u8 = null,
    url: ?[]const u8 = null,
};

const UpdateNewsReq = struct {
    title: ?[]const u8 = null,
    author: ?[]const u8 = null,
    digest: ?[]const u8 = null,
    content: ?[]const u8 = null,
    thumb_media_id: ?[]const u8 = null,
    thumb_url: ?[]const u8 = null,
    url: ?[]const u8 = null,
};

const CreateFileReq = struct {
    account_id: i64,
    kind: []const u8,
    media_id: []const u8,
    url: ?[]const u8 = null,
};

pub fn MaterialApi(comptime Service: type, comptime UserService: type) type {
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
            try g.get("/materials/news", listNews, @ptrCast(@alignCast(self)));
            try g.post("/materials/news", createNews, @ptrCast(@alignCast(self)));
            try g.get("/materials/news/{id}", getNews, @ptrCast(@alignCast(self)));
            try g.put("/materials/news/{id}", updateNews, @ptrCast(@alignCast(self)));
            try g.delete("/materials/news/{id}", deleteNews, @ptrCast(@alignCast(self)));
            try g.get("/materials/files", listFiles, @ptrCast(@alignCast(self)));
            try g.post("/materials/files", createFile, @ptrCast(@alignCast(self)));
            try g.delete("/materials/files/{id}", deleteFile, @ptrCast(@alignCast(self)));
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

        fn parseAccount(ctx: *http.Context) ?i64 {
            const raw = ctx.queryParam("account_id") orelse return null;
            return std.fmt.parseInt(i64, raw, 10) catch null;
        }

        fn listNews(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);
            const account_id = parseAccount(ctx) orelse {
                try ctx.sendErrorResponse(400, 400, "缺少 account_id");
                return;
            };
            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 100 });
            var result = self.svc.listNews(params.page, params.page_size, tid, account_id) catch |err| {
                try ctx.sendErrorResponse(500, 500, @errorName(err));
                return;
            };
            defer result.free(self.svc.allocator);
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, NewsDto, toNewsDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }

        fn createNews(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);

            const req = ctx.bindJson(CreateNewsReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer {
                ctx.allocator.free(req.title);
                if (req.author) |s| ctx.allocator.free(s);
                if (req.digest) |s| ctx.allocator.free(s);
                if (req.content) |s| ctx.allocator.free(s);
                if (req.thumb_media_id) |s| ctx.allocator.free(s);
                if (req.thumb_url) |s| ctx.allocator.free(s);
                if (req.url) |s| ctx.allocator.free(s);
            }
            const id = self.svc.createNews(tid, req.account_id, req.title, req.author orelse "", req.digest orelse "", req.content orelse "", req.thumb_media_id orelse "", req.thumb_url orelse "", req.url orelse "") catch |err| {
                const msg = switch (err) {
                    error.InvalidTitle => "标题不能为空",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            var d1: [128]u8 = undefined;
            const det1 = try std.fmt.bufPrint(&d1, "新建图文素材 {s}", .{req.title});
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "material.news.create", "material", id, det1, zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(201, .{ .code = 0, .msg = "素材已创建", .data = .{ .id = id } });
        }

        fn getNews(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = (try requireAdmin(ctx, self)) orelse return;
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的素材 ID");
                return;
            };
            const row_opt = self.svc.getNews(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            const row = row_opt orelse {
                try ctx.sendErrorResponse(404, 404, "素材不存在");
                return;
            };
            defer row.free(self.svc.allocator);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = toNewsDto(row) });
        }

        fn updateNews(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的素材 ID");
                return;
            };
            const req = ctx.bindJson(UpdateNewsReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer {
                if (req.title) |s| ctx.allocator.free(s);
                if (req.author) |s| ctx.allocator.free(s);
                if (req.digest) |s| ctx.allocator.free(s);
                if (req.content) |s| ctx.allocator.free(s);
                if (req.thumb_media_id) |s| ctx.allocator.free(s);
                if (req.thumb_url) |s| ctx.allocator.free(s);
                if (req.url) |s| ctx.allocator.free(s);
            }
            const cur_opt = self.svc.getNews(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            const cur = cur_opt orelse {
                try ctx.sendErrorResponse(404, 404, "素材不存在");
                return;
            };
            defer cur.free(self.svc.allocator);
            self.svc.updateNews(id, req.title orelse cur.title, req.author orelse cur.author, req.digest orelse cur.digest, req.content orelse cur.content, req.thumb_media_id orelse cur.thumb_media_id, req.thumb_url orelse cur.thumb_url, req.url orelse cur.url) catch |err| {
                try ctx.sendErrorResponse(400, 400, @errorName(err));
                return;
            };
            var d1: [128]u8 = undefined;
            const det1 = try std.fmt.bufPrint(&d1, "更新图文素材 #{d}", .{id});
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "material.news.update", "material", id, det1, zigmodu.http.RequestUtil.getRealIp(ctx), true, tenantScope(ctx, self));
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = null });
        }

        fn deleteNews(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的素材 ID");
                return;
            };
            self.svc.deleteNews(id) catch |err| {
                try ctx.sendErrorResponse(500, 500, @errorName(err));
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "material.news.delete", "material", id, "删除图文素材", zigmodu.http.RequestUtil.getRealIp(ctx), true, tenantScope(ctx, self));
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = null });
        }

        fn listFiles(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);
            const account_id = parseAccount(ctx) orelse {
                try ctx.sendErrorResponse(400, 400, "缺少 account_id");
                return;
            };
            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 100 });
            var result = self.svc.listFiles(params.page, params.page_size, tid, account_id, ctx.queryParam("kind")) catch |err| {
                try ctx.sendErrorResponse(500, 500, @errorName(err));
                return;
            };
            defer result.free(self.svc.allocator);
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, FileDto, toFileDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }

        fn createFile(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);

            const req = ctx.bindJson(CreateFileReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer {
                ctx.allocator.free(req.kind);
                ctx.allocator.free(req.media_id);
                if (req.url) |s| ctx.allocator.free(s);
            }
            const id = self.svc.createFile(tid, req.account_id, req.kind, req.media_id, req.url orelse "") catch |err| {
                const msg = switch (err) {
                    error.InvalidKind => "素材类型仅支持 image/voice/video",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            var d1: [128]u8 = undefined;
            const det1 = try std.fmt.bufPrint(&d1, "新建 {s} 素材", .{req.kind});
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "material.file.create", "material", id, det1, zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(201, .{ .code = 0, .msg = "素材已创建", .data = .{ .id = id } });
        }

        fn deleteFile(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的素材 ID");
                return;
            };
            self.svc.deleteFile(id) catch |err| {
                try ctx.sendErrorResponse(500, 500, @errorName(err));
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "material.file.delete", "material", id, "删除素材", zigmodu.http.RequestUtil.getRealIp(ctx), true, tenantScope(ctx, self));
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = null });
        }
    };
}

pub const DefaultMaterialApi = MaterialApi(service.MaterialService, user_svc.UserService);
