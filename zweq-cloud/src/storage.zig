//! Artifact storage abstraction — 产物托管后端可插拔。
//!
//! - `ArtifactStorage`：vtable 接口（put/get/exists），本地目录与对象存储
//!   （S3-compatible）可互换。
//! - `LocalArtifactStorage`：本地目录（默认）。
//! - `S3ArtifactStorage`：S3-compatible REST（SigV4 签名），path-style。
//!
//! 后端由环境变量切换（见 config.zig）。S3 后端支持 AWS S3 与任意
//! S3-compatible 服务（MinIO、阿里 OSS S3 接口等）。

const std = @import("std");

// ── 抽象接口 ────────────────────────────────────────────────────────────

pub const ArtifactStorage = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        put: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, key: []const u8, content: []const u8) anyerror!void,
        get: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, key: []const u8) anyerror![]u8,
        exists: *const fn (ptr: *anyopaque, key: []const u8) bool,
    };

    pub fn put(self: ArtifactStorage, allocator: std.mem.Allocator, key: []const u8, content: []const u8) !void {
        return self.vtable.put(self.ptr, allocator, key, content);
    }
    pub fn get(self: ArtifactStorage, allocator: std.mem.Allocator, key: []const u8) ![]u8 {
        return self.vtable.get(self.ptr, allocator, key);
    }
    pub fn exists(self: ArtifactStorage, key: []const u8) bool {
        return self.vtable.exists(self.ptr, key);
    }
};

// ── 本地目录后端 ────────────────────────────────────────────────────────

pub const LocalArtifactStorage = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: []const u8,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, dir: []const u8) LocalArtifactStorage {
        return .{ .allocator = allocator, .io = io, .dir = dir };
    }

    pub fn storage(self: *LocalArtifactStorage) ArtifactStorage {
        return .{ .ptr = self, .vtable = &vtable };
    }

    fn pathOf(self: *LocalArtifactStorage, key: []const u8) ![]u8 {
        return std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.dir, key });
    }

    fn put(ptr: *anyopaque, allocator: std.mem.Allocator, key: []const u8, content: []const u8) anyerror!void {
        const self: *LocalArtifactStorage = @ptrCast(@alignCast(ptr));
        _ = allocator;
        var cwd = std.Io.Dir.cwd();
        cwd.createDir(self.io, self.dir, .default_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
        const path = try self.pathOf(key);
        defer self.allocator.free(path);
        var file = cwd.createFile(self.io, path, .{ .exclusive = true }) catch |err| switch (err) {
            error.PathAlreadyExists => return, // 幂等
            else => return err,
        };
        defer file.close(self.io);
        file.writePositionalAll(self.io, content, 0) catch return error.WriteFailed;
    }

    fn get(ptr: *anyopaque, allocator: std.mem.Allocator, key: []const u8) anyerror![]u8 {
        const self: *LocalArtifactStorage = @ptrCast(@alignCast(ptr));
        const path = try self.pathOf(key);
        defer self.allocator.free(path);
        return std.Io.Dir.cwd().readFileAlloc(self.io, path, allocator, .limited(256 * 1024 * 1024)) catch |err| switch (err) {
            error.FileNotFound => error.NotFound,
            else => err,
        };
    }

    fn exists(ptr: *anyopaque, key: []const u8) bool {
        const self: *LocalArtifactStorage = @ptrCast(@alignCast(ptr));
        const path = self.pathOf(key) catch return false;
        defer self.allocator.free(path);
        const f = std.Io.Dir.cwd().openFile(self.io, path, .{}) catch return false;
        f.close(self.io);
        return true;
    }

    const vtable = ArtifactStorage.VTable{ .put = put, .get = get, .exists = exists };
};

// ── S3-compatible 后端（SigV4）──────────────────────────────────────────

pub const S3Config = struct {
    endpoint: []const u8, // e.g. "https://s3.amazonaws.com" 或 "http://minio:9000"
    bucket: []const u8,
    region: []const u8,
    access_key: []const u8,
    secret_key: []const u8,
    path_style: bool = true,
};

pub const S3ArtifactStorage = struct {
    allocator: std.mem.Allocator,
    cfg: S3Config,

    pub fn init(allocator: std.mem.Allocator, cfg: S3Config) S3ArtifactStorage {
        return .{ .allocator = allocator, .cfg = cfg };
    }

    pub fn storage(self: *S3ArtifactStorage) ArtifactStorage {
        return .{ .ptr = self, .vtable = &vtable };
    }

    fn objectUrl(self: *S3ArtifactStorage, allocator: std.mem.Allocator, key: []const u8) ![]u8 {
        const uri_path = if (self.cfg.path_style)
            try std.fmt.allocPrint(allocator, "/{s}/{s}", .{ self.cfg.bucket, key })
        else
            try std.fmt.allocPrint(allocator, "/{s}", .{key});
        defer allocator.free(uri_path);
        return std.fmt.allocPrint(allocator, "{s}{s}", .{ self.cfg.endpoint, uri_path });
    }

    fn put(ptr: *anyopaque, allocator: std.mem.Allocator, key: []const u8, content: []const u8) anyerror!void {
        const self: *S3ArtifactStorage = @ptrCast(@alignCast(ptr));
        const url = try self.objectUrl(allocator, key);
        defer allocator.free(url);
        _ = try self.request(allocator, .PUT, url, content);
    }

    fn get(ptr: *anyopaque, allocator: std.mem.Allocator, key: []const u8) anyerror![]u8 {
        const self: *S3ArtifactStorage = @ptrCast(@alignCast(ptr));
        const url = try self.objectUrl(allocator, key);
        defer allocator.free(url);
        return self.request(allocator, .GET, url, "");
    }

    fn exists(ptr: *anyopaque, key: []const u8) bool {
        const self: *S3ArtifactStorage = @ptrCast(@alignCast(ptr));
        const url = self.objectUrl(self.allocator, key) catch return false;
        defer self.allocator.free(url);
        const body = self.request(self.allocator, .GET, url, "") catch return false;
        defer self.allocator.free(body);
        return true;
    }

    /// 发出签名后的 S3 请求。返回响应 body（caller-owned）。
    fn request(self: *S3ArtifactStorage, allocator: std.mem.Allocator, method: std.http.Method, url: []const u8, payload: []const u8) anyerror![]u8 {
        const uri = std.Uri.parse(url) catch return error.InvalidUrl;
        const host = try allocator.dupe(u8, (uri.host orelse return error.InvalidUrl).percent_encoded);
        defer allocator.free(host);
        const canonical_uri = try allocator.dupe(u8, uri.path.percent_encoded);
        defer allocator.free(canonical_uri);

        const auth = try sigV4(allocator, .{
            .method = if (method == .PUT) "PUT" else "GET",
            .host = host,
            .canonical_uri = canonical_uri,
            .payload = payload,
        }, self.cfg.access_key, self.cfg.secret_key, self.cfg.region, "s3");
        defer auth.deinit(allocator);

        var client: std.http.Client = .{ .allocator = allocator, .io = std.Io.Threaded.global_single_threaded.io() };
        defer client.deinit();

        var extra = std.ArrayList(std.http.Header).empty;
        defer extra.deinit(allocator);
        try extra.append(allocator, .{ .name = "x-amz-date", .value = auth.amz_date });
        try extra.append(allocator, .{ .name = "x-amz-content-sha256", .value = auth.payload_hash });
        try extra.append(allocator, .{ .name = "authorization", .value = auth.authorization });

        var body_writer: std.Io.Writer.Allocating = .init(allocator);
        defer body_writer.deinit();

        const result = client.fetch(.{
            .method = method,
            .location = .{ .url = url },
            .payload = if (payload.len == 0 and method == .GET) null else payload,
            .response_writer = &body_writer.writer,
            .extra_headers = extra.items,
        }) catch return error.RequestFailed;

        if (result.status != .ok) return error.HttpStatusNotOk;
        var list = body_writer.toArrayList();
        defer list.deinit(allocator);
        return list.toOwnedSlice(allocator);
    }

    const vtable = ArtifactStorage.VTable{ .put = put, .get = get, .exists = exists };
};

// ── SigV4 签名（AWS Signature Version 4）────────────────────────────────

pub const SigV4Input = struct {
    method: []const u8,
    host: []const u8,
    canonical_uri: []const u8 = "/",
    canonical_query: []const u8 = "",
    payload: []const u8 = "",
};

pub const SigV4Auth = struct {
    authorization: []const u8,
    amz_date: []const u8,
    payload_hash: []const u8,

    pub fn deinit(self: *const SigV4Auth, allocator: std.mem.Allocator) void {
        allocator.free(self.authorization);
        allocator.free(self.amz_date);
        allocator.free(self.payload_hash);
    }
};

/// 计算 SigV4 Authorization（amz_date 用当前 UTC）。caller 需 `deinit`。
pub fn sigV4(allocator: std.mem.Allocator, input: SigV4Input, access_key: []const u8, secret_key: []const u8, region: []const u8, service: []const u8) !SigV4Auth {
    const amz_date = try nowAmzDate(allocator);
    errdefer allocator.free(amz_date);
    const payload_hash = try sha256Hex(allocator, input.payload);
    errdefer allocator.free(payload_hash);
    const authorization = try signV4(allocator, input, access_key, secret_key, region, service, amz_date, payload_hash);
    return .{ .authorization = authorization, .amz_date = amz_date, .payload_hash = payload_hash };
}

/// 纯签名计算（amz_date 由调用方给定，便于确定性测试）。
pub fn signV4(allocator: std.mem.Allocator, input: SigV4Input, access_key: []const u8, secret_key: []const u8, region: []const u8, service: []const u8, amz_date: []const u8, payload_hash: []const u8) ![]u8 {
    const date_stamp = amz_date[0..8];

    // 规范化 headers（固定三个，字典序升序）。
    const canonical_headers = try std.fmt.allocPrint(allocator, "host:{s}\nx-amz-content-sha256:{s}\nx-amz-date:{s}\n", .{ input.host, payload_hash, amz_date });
    defer allocator.free(canonical_headers);
    const signed_headers = "host;x-amz-content-sha256;x-amz-date";

    const canonical_request = try std.fmt.allocPrint(allocator, "{s}\n{s}\n{s}\n{s}\n{s}\n{s}", .{
        input.method,
        input.canonical_uri,
        input.canonical_query,
        canonical_headers,
        signed_headers,
        payload_hash,
    });
    defer allocator.free(canonical_request);
    const cr_hash = try sha256Hex(allocator, canonical_request);
    defer allocator.free(cr_hash);

    const scope = try std.fmt.allocPrint(allocator, "{s}/{s}/{s}/aws4_request", .{ date_stamp, region, service });
    defer allocator.free(scope);
    const string_to_sign = try std.fmt.allocPrint(allocator, "AWS4-HMAC-SHA256\n{s}\n{s}\n{s}", .{ amz_date, scope, cr_hash });
    defer allocator.free(string_to_sign);

    // HMAC 链：kDate → kRegion → kService → kSigning。
    var k_date: [32]u8 = undefined;
    var k_region: [32]u8 = undefined;
    var k_service: [32]u8 = undefined;
    var k_signing: [32]u8 = undefined;
    const secret_prefix = try std.fmt.allocPrint(allocator, "AWS4{s}", .{secret_key});
    defer allocator.free(secret_prefix);
    hmacSha256(&k_date, secret_prefix, date_stamp);
    hmacSha256(&k_region, &k_date, region);
    hmacSha256(&k_service, &k_region, service);
    hmacSha256(&k_signing, &k_service, "aws4_request");

    var sig_bytes: [32]u8 = undefined;
    hmacSha256(&sig_bytes, &k_signing, string_to_sign);
    const sig_hex = try hexEncode(allocator, &sig_bytes);
    defer allocator.free(sig_hex);

    return std.fmt.allocPrint(allocator, "AWS4-HMAC-SHA256 Credential={s}/{s}, SignedHeaders={s}, Signature={s}", .{
        access_key, scope, signed_headers, sig_hex,
    });
}

/// 生成当前 UTC 的 amz_date（"YYYYMMDDTHHMMSSZ"）。
pub fn nowAmzDate(allocator: std.mem.Allocator) ![]u8 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.REALTIME, &ts);
    const secs: u64 = @intCast(ts.sec);
    const es = std.time.epoch.EpochSeconds{ .secs = secs };
    const yd = es.getEpochDay().calculateYearDay();
    const md = yd.calculateMonthDay();
    const ds = es.getDaySeconds();
    return std.fmt.allocPrint(allocator, "{d:0>4}{d:0>2}{d:0>2}T{d:0>2}{d:0>2}{d:0>2}Z", .{
        yd.year,
        @intFromEnum(md.month) + 1,
        md.day_index + 1,
        ds.getHoursIntoDay(),
        ds.getMinutesIntoHour(),
        ds.getSecondsIntoMinute(),
    });
}

fn hmacSha256(out: *[32]u8, key: []const u8, msg: []const u8) void {
    std.crypto.auth.hmac.sha2.HmacSha256.create(out, msg, key);
}

fn sha256Hex(allocator: std.mem.Allocator, msg: []const u8) ![]u8 {
    var d: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(msg, &d, .{});
    return hexEncode(allocator, &d);
}

fn hexEncode(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const hex_chars = "0123456789abcdef";
    const out = try allocator.alloc(u8, bytes.len * 2);
    for (bytes, 0..) |b, i| {
        out[i * 2] = hex_chars[b >> 4];
        out[i * 2 + 1] = hex_chars[b & 0xF];
    }
    return out;
}
