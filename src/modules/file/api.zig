//! File HTTP API — upload/download/list/delete. Uploads require any
//! authenticated user; admins see all files, users see their own.

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const mw = @import("../../middleware/auth.zig");
const user_svc = @import("../user/service.zig");
const audit_svc = @import("../audit/service.zig");
const service = @import("service.zig");

const FileDto = struct {
    id: i64,
    name: []const u8,
    mime: []const u8,
    size_bytes: i64,
    uploader_id: i64,
    tenant_id: i64,
    group_id: i64,
    storage_key: []const u8,
    created_at: i64,
};

fn toDto(row: service.FileRow) FileDto {
    return .{
        .id = row.id,
        .name = row.name,
        .mime = row.mime,
        .size_bytes = row.size_bytes,
        .uploader_id = row.uploader_id,
        .tenant_id = row.tenant_id,
        .group_id = row.group_id,
        .storage_key = row.storage_key,
        .created_at = row.created_at,
    };
}

pub fn FileApi(comptime Service: type, comptime UserService: type) type {
    return struct {
        const Self = @This();
        svc: *Service,
        user_svc: *UserService,
        audit: *audit_svc.AuditService,
        default_tenant_id: i64,

        pub const module_name = "file";
        pub const nest: []const []const u8 = &.{};
        pub const State = Self;

        pub const routes: []const http.RouteSpec(Self) = &.{
            .{ .method = .POST, .path = "files", .handler = http.wrapHandler(Self, upload), .meta = .{ .auth = .jwt } },
            .{ .method = .GET, .path = "files", .handler = http.wrapHandler(Self, list), .meta = .{ .auth = .jwt } },
            .{ .method = .GET, .path = "files/{id}", .handler = http.wrapHandler(Self, download), .meta = .{ .auth = .jwt } },
            .{ .method = .DELETE, .path = "files/{id}", .handler = http.wrapHandler(Self, delete), .meta = .{ .auth = .jwt } },
            .{ .method = .POST, .path = "files/groups", .handler = http.wrapHandler(Self, createGroup), .meta = .{ .auth = .jwt } },
            .{ .method = .GET, .path = "files/groups", .handler = http.wrapHandler(Self, listGroups), .meta = .{ .auth = .jwt } },
            .{ .method = .PUT, .path = "files/groups/{id}", .handler = http.wrapHandler(Self, updateGroup), .meta = .{ .auth = .jwt } },
            .{ .method = .DELETE, .path = "files/groups/{id}", .handler = http.wrapHandler(Self, deleteGroup), .meta = .{ .auth = .jwt } },
        };

        pub fn init(svc: *Service, users: *UserService, audit: *audit_svc.AuditService, default_tenant_id: i64) Self {
            return .{ .svc = svc, .user_svc = users, .audit = audit, .default_tenant_id = default_tenant_id };
        }

        pub fn registerRoutes(self: *Self, group: *http.RouteGroup) !void {
            var g = try group.use(zigmodu.http.http_middleware.jwtAuthWithSecurity(&self.user_svc.sec.module));
            g = try g.use(mw.tokenVersionGuard(self.user_svc.sec, self.user_svc.store));
            try g.post("/files", upload, @ptrCast(@alignCast(self)));
            try g.get("/files", list, @ptrCast(@alignCast(self)));
            try g.get("/files/{id}", download, @ptrCast(@alignCast(self)));
            try g.delete("/files/{id}", delete, @ptrCast(@alignCast(self)));
        }

        fn authUser(ctx: *http.Context, self: *Self) !?struct { id: i64, admin: bool } {
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
            try ctx.setAttr("audit_actor", row.name);
            return .{ .id = uid, .admin = row.admin };
        }

        fn upload(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const actor = (try authUser(ctx, self)) orelse return;

            const body = ctx.body orelse {
                try ctx.sendErrorResponse(400, 400, "缺少文件内容");
                return;
            };
            const filename = ctx.header("X-File-Name") orelse "upload.bin";
            const mime = ctx.header("Content-Type") orelse "application/octet-stream";

            const tenant_id = mw.authTenantId(ctx) orelse self.default_tenant_id;
            const group_id = blk: {
                const raw = ctx.header("X-Group-Id") orelse "0";
                break :blk std.fmt.parseInt(i64, raw, 10) catch 0;
            };
            const row = self.svc.save(actor.id, tenant_id, group_id, filename, mime, body) catch |err| switch (err) {
                error.FileTooLarge => {
                    try ctx.sendErrorResponse(413, 413, "文件超过大小限制");
                    return;
                },
                error.InvalidMime => {
                    try ctx.sendErrorResponse(400, 400, "不允许的文件类型");
                    return;
                },
                else => {
                    try ctx.sendErrorResponse(500, 500, "服务器错误");
                    return;
                },
            };
            defer row.free(self.svc.allocator);
            try ctx.okValue(toDto(row));
        }

        fn list(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const actor = (try authUser(ctx, self)) orelse return;

            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 100 });
            const current_tenant = mw.authTenantId(ctx) orelse self.default_tenant_id;
            const owner: ?i64 = if (actor.admin) null else actor.id;
            const tenant_filter: ?i64 = if (actor.admin) blk: {
                const tid = ctx.queryInt(i64, "tenant_id", 0);
                break :blk if (tid > 0) tid else null;
            } else current_tenant;
            const sort = zigmodu.http.page.parseSort(ctx, &.{ "name", "size_bytes", "created_at" });
            const sort_col: ?[]const u8 = if (sort) |s| s.column else null;
            const sort_desc = if (sort) |s| s.desc else false;
            const group_id: ?i64 = blk: {
                const gid = ctx.queryInt(i64, "group_id", 0);
                break :blk if (gid > 0) gid else null;
            };
            const mime_prefix: ?[]const u8 = ctx.queryParam("type");

            var result = self.svc.list(params.page, params.page_size, owner, tenant_filter, group_id, mime_prefix, sort_col, sort_desc) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer result.free(self.svc.allocator);

            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, FileDto, toDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }

        fn download(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const actor = (try authUser(ctx, self)) orelse return;

            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的文件 ID");
                return;
            };
            const loaded_opt = self.svc.load(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            var loaded = loaded_opt orelse {
                try ctx.sendErrorResponse(404, 404, "文件不存在");
                return;
            };
            defer loaded.free(self.svc.allocator);

            const current_tenant = mw.authTenantId(ctx) orelse self.default_tenant_id;
            if (!actor.admin and (loaded.row.uploader_id != actor.id or loaded.row.tenant_id != current_tenant)) {
                try ctx.sendErrorResponse(403, 403, "无权访问该文件");
                return;
            }

            try ctx.text(200, loaded.bytes);
            try ctx.setHeader("Content-Type", loaded.row.mime);
            try ctx.setHeader("X-Content-Type-Options", "nosniff");
            const disposition = try std.fmt.allocPrint(ctx.allocator, "attachment; filename=\"{s}\"", .{loaded.row.name});
            defer ctx.allocator.free(disposition);
            try ctx.setHeader("Content-Disposition", disposition);
        }

        fn delete(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const actor = (try authUser(ctx, self)) orelse return;

            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的文件 ID");
                return;
            };
            const row_opt = self.svc.get(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            const row = row_opt orelse {
                try ctx.sendErrorResponse(404, 404, "文件不存在");
                return;
            };
            defer row.free(self.svc.allocator);
            const current_tenant = mw.authTenantId(ctx) orelse self.default_tenant_id;
            if (!actor.admin and (row.uploader_id != actor.id or row.tenant_id != current_tenant)) {
                try ctx.sendErrorResponse(403, 403, "无权删除该文件");
                return;
            }
            self.svc.delete(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            var d5: [96]u8 = undefined;
            const det5 = try std.fmt.bufPrint(&d5, "删除文件 #{d}", .{id});
            self.audit.log(actor.id, ctx.getAttr("audit_actor") orelse "", "file.delete", "file", id, det5, zigmodu.http.RequestUtil.getRealIp(ctx), true, row.tenant_id);
            try ctx.ok("null");
        }

        // ── Upload groups (image-manager categories) ──

        const GroupInput = struct { group_name: []const u8, sort: ?f64 = null };

        fn createGroup(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = try authUser(ctx, self) orelse return;
            const raw_body = ctx.body orelse {
                try ctx.sendErrorResponse(400, 400, "请求体不能为空");
                return;
            };
            var parsed = std.json.parseFromSlice(GroupInput, self.svc.allocator, raw_body, .{}) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer parsed.deinit();
            const name = parsed.value.group_name;
            if (name.len == 0) {
                try ctx.sendErrorResponse(400, 400, "分类名称不能为空");
                return;
            }
            const sort = if (parsed.value.sort) |s| @as(i64, @intFromFloat(s)) else 0;
            const tenant_id = mw.authTenantId(ctx) orelse self.default_tenant_id;
            const id = self.svc.createGroup(name, "image", sort, tenant_id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            try ctx.okValue(.{ .id = id });
        }

        fn listGroups(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = try authUser(ctx, self) orelse return;
            const tenant_id = mw.authTenantId(ctx) orelse self.default_tenant_id;
            const rows = self.svc.listGroups(tenant_id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            const GroupDto = struct { id: i64, group_name: []const u8, group_type: []const u8, sort: i64 };
            var dtos = try self.svc.allocator.alloc(GroupDto, rows.len);
            errdefer {
                for (dtos[0..]) |d| {
                    self.svc.allocator.free(d.group_name);
                    self.svc.allocator.free(d.group_type);
                }
                self.svc.allocator.free(dtos);
            }
            for (rows, 0..) |r, i| {
                dtos[i] = .{
                    .id = r.id,
                    .group_name = try self.svc.allocator.dupe(u8, r.group_name),
                    .group_type = try self.svc.allocator.dupe(u8, r.group_type),
                    .sort = r.sort,
                };
            }
            for (rows) |r| r.free(self.svc.allocator);
            self.svc.allocator.free(rows);
            try ctx.okValue(.{ .items = dtos });
        }

        fn updateGroup(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = try authUser(ctx, self) orelse return;
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的分类 ID");
                return;
            };
            const body_json_raw = ctx.body orelse {
                try ctx.sendErrorResponse(400, 400, "请求体不能为空");
                return;
            };
            var parsed = std.json.parseFromSlice(GroupInput, self.svc.allocator, body_json_raw, .{}) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer parsed.deinit();
            const name = parsed.value.group_name;
            const sort = if (parsed.value.sort) |s| @as(i64, @intFromFloat(s)) else 0;
            self.svc.updateGroup(id, name, sort) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            try ctx.ok("null");
        }

        fn deleteGroup(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = try authUser(ctx, self) orelse return;
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的分类 ID");
                return;
            };
            const count = self.svc.countGroupFiles(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            if (count > 0) {
                try ctx.sendErrorResponse(400, 400, "该分类下还有文件，无法删除");
                return;
            }
            self.svc.deleteGroup(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            try ctx.ok("null");
        }
    };
}

pub const DefaultFileApi = FileApi(service.FileService, user_svc.UserService);
