//! Market API — 包发布/列表（管理端 Bearer）+ 列表/下载（站点端公开）。

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;

const service = @import("service.zig");

const PackageDto = struct {
    id: i64,
    name: []const u8,
    title: []const u8,
    version: []const u8,
    description: []const u8,
    checksum: []const u8,
    created_at: i64,
};

fn toDto(row: service.MarketPackageRow) PackageDto {
    return .{ .id = row.id, .name = row.name, .title = row.title, .version = row.version, .description = row.description, .checksum = row.checksum, .created_at = row.created_at };
}

const PublishReq = struct {
    name: []const u8,
    title: []const u8 = "",
    version: []const u8 = "1.0.0",
    description: []const u8 = "",
    download_url: []const u8 = "",
    checksum: []const u8 = "",
};

const FetchReq = struct {
    name: []const u8,
};

pub fn MarketApi(comptime Service: type) type {
    return struct {
        const Self = @This();
        svc: *Service,
        admin_token: []const u8,

        pub fn init(svc: *Service, admin_token: []const u8) Self {
            return .{ .svc = svc, .admin_token = admin_token };
        }

        pub fn registerRoutes(self: *Self, group: *http.RouteGroup) !void {
            var admin = try group.use(bearerAuth(self.admin_token));
            try admin.post("/cloud/market", publish, @ptrCast(@alignCast(self)));
            try admin.post("/cloud/market/fetch", fetchArtifact, @ptrCast(@alignCast(self)));
            // 站点端公开：列表 + 下载产物。
            try group.get("/cloud/market", list, @ptrCast(@alignCast(self)));
            try group.get("/cloud/market/{name}/download", download, @ptrCast(@alignCast(self)));
        }

        fn publish(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const req = ctx.bindJson(PublishReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer {
                ctx.allocator.free(req.name);
                if (req.title.len > 0) ctx.allocator.free(req.title);
                if (req.version.len > 0) ctx.allocator.free(req.version);
                if (req.description.len > 0) ctx.allocator.free(req.description);
                if (req.download_url.len > 0) ctx.allocator.free(req.download_url);
                if (req.checksum.len > 0) ctx.allocator.free(req.checksum);
            }
            const id = self.svc.publish(req.name, req.title, req.version, req.description, req.download_url, req.checksum) catch |err| {
                const msg = switch (err) {
                    error.InvalidName => "包名/版本不合法（仅 [a-zA-Z0-9_-]）",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            try ctx.jsonStruct(201, .{ .code = 0, .msg = "已发布", .data = .{ .id = id } });
        }

        fn fetchArtifact(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const req = ctx.bindJson(FetchReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer ctx.allocator.free(req.name);
            self.svc.fetchArtifact(req.name) catch |err| {
                const msg = switch (err) {
                    error.NotFound => "市场包不存在或无产物源",
                    error.ChecksumMismatch => "产物校验失败",
                    error.DownloadFailed => "产物下载失败",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "已拉取", .data = null });
        }

        fn list(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 100 });
            var result = self.svc.list(params.page, params.page_size) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer result.free(ctx.allocator);
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, PackageDto, toDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }

        fn download(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const name = ctx.param("name") orelse {
                try ctx.sendErrorResponse(400, 400, "缺少包名");
                return;
            };
            const pkg_opt = self.svc.getByName(name) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            const pkg = pkg_opt orelse {
                try ctx.sendErrorResponse(404, 404, "市场包不存在");
                return;
            };
            defer pkg.free(ctx.allocator);
            const bytes = self.svc.readArtifact(pkg.name, pkg.version) catch |err| {
                const msg = switch (err) {
                    error.NotFound => "产物未拉取（请管理员先 fetch）",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(404, 404, msg);
                return;
            };
            defer ctx.allocator.free(bytes);
            const disposition = try std.fmt.allocPrint(ctx.allocator, "attachment; filename=\"{s}-{s}.bin\"", .{ pkg.name, pkg.version });
            defer ctx.allocator.free(disposition);
            try ctx.setHeader("Content-Disposition", disposition);
            try ctx.text(200, bytes);
            try ctx.setHeader("Content-Type", "application/octet-stream");
        }
    };
}

const bearerAuth = @import("../license/api.zig").http_mw.bearerAuth;
