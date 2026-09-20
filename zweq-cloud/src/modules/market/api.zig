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
            // SSRF 基线：download_url 非空时会被服务端 fetchArtifact 主动拉取，写入前校验。
            if (req.download_url.len > 0 and !isAcceptableOutboundUrl(req.download_url)) {
                try ctx.sendErrorResponse(400, 400, "download_url 不允许（需 http(s) 且非内网地址）");
                return;
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

/// 出站 URL 白名单校验（OWASP API4 SSRF 基线）。
/// 与主站 src/http/url_guard.zig 同款，因独立构建根（不能 import 主站 src）而复制。
/// 局限：按字面判断，不做 DNS 解析（域名解析到内网的情况防不住），
/// 不识别 IP 等价写法（十进制/十六进制整数形式等）；完整防护需在出站连接层二次拦截。
fn isAcceptableOutboundUrl(url: []const u8) bool {
    // scheme 只认 http/https（大小写不敏感），其余（ftp/file/无 scheme 等）一律拒绝。
    const rest = if (std.ascii.startsWithIgnoreCase(url, "https://"))
        url["https://".len..]
    else if (std.ascii.startsWithIgnoreCase(url, "http://"))
        url["http://".len..]
    else
        return false;

    // authority 段到首个 / ? # 为止。
    const authority_end = std.mem.indexOfAny(u8, rest, "/?#") orelse rest.len;
    var authority = rest[0..authority_end];

    // 剥离 userinfo（user:pass@host）：取最后一个 '@' 之后，防 http://x@127.0.0.1/ 字面绕过。
    if (std.mem.lastIndexOfScalar(u8, authority, '@')) |at| authority = authority[at + 1 ..];

    // host 段：IPv6 字面量带 [] 整段取；否则取到首个 ':'（端口分隔符）前。
    var host: []const u8 = undefined;
    if (authority.len > 0 and authority[0] == '[') {
        const close = std.mem.indexOfScalar(u8, authority, ']') orelse return false;
        host = authority[0 .. close + 1];
    } else {
        const colon = std.mem.indexOfScalar(u8, authority, ':') orelse authority.len;
        host = authority[0..colon];
    }
    if (host.len == 0) return false;

    return !isLiteralPrivateHost(host);
}

/// 字面回环/内网地址判断（不解析、不做 DNS）：
/// localhost、::1 与 [::1]、127. / 10. / 192.168. / 169.254. 前缀、172.16.–172.31. 段。
fn isLiteralPrivateHost(host: []const u8) bool {
    if (std.ascii.eqlIgnoreCase(host, "localhost")) return true;
    if (std.mem.eql(u8, host, "::1") or std.mem.eql(u8, host, "[::1]")) return true;
    if (std.ascii.startsWithIgnoreCase(host, "127.")) return true;
    if (std.ascii.startsWithIgnoreCase(host, "10.")) return true;
    if (std.ascii.startsWithIgnoreCase(host, "192.168.")) return true;
    if (std.ascii.startsWithIgnoreCase(host, "169.254.")) return true;
    // 172.16.0.0 – 172.31.255.255：解析 "172." 后的第一段八位组。
    if (std.ascii.startsWithIgnoreCase(host, "172.")) {
        const second_end = std.mem.indexOfScalarPos(u8, host, 4, '.') orelse return false;
        const second = std.fmt.parseInt(u16, host[4..second_end], 10) catch return false;
        if (second >= 16 and second <= 31) return true;
    }
    return false;
}
