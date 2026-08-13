//! Market service — 应用市场包发布/校验/产物托管。No HTTP/SQL leakage。

const std = @import("std");
const zigmodu = @import("zigmodu");
const persist = @import("persistence.zig");
const storage = @import("../../storage.zig");

pub const MarketPackageRow = persist.MarketPackageRow;
pub const MarketListResult = persist.MarketListResult;

pub const MarketError = error{
    InvalidName,
    ChecksumMismatch,
    DownloadFailed,
    NotFound,
    Unexpected,
};

pub const MarketService = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    store: *persist.MarketStore,
    /// 产物托管后端（本地目录 / S3 等，可插拔）。
    artifact: storage.ArtifactStorage,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, store: *persist.MarketStore, artifact: storage.ArtifactStorage) MarketService {
        return .{ .allocator = allocator, .io = io, .store = store, .artifact = artifact };
    }

    fn now(self: *MarketService) i64 {
        return zigmodu.time.wallClockSeconds(self.io);
    }

    pub fn publish(self: *MarketService, name: []const u8, title: []const u8, version: []const u8, description: []const u8, download_url: []const u8, checksum: []const u8) MarketError!i64 {
        if (std.mem.trim(u8, name, " \t").len == 0) return error.InvalidName;
        if (!safeArtifactComponent(name) or !safeArtifactComponent(version)) return error.InvalidName;
        return self.store.upsert(name, title, version, description, download_url, checksum, self.now()) catch error.Unexpected;
    }

    pub fn list(self: *MarketService, page: usize, page_size: usize) MarketError!MarketListResult {
        return self.store.list(page, page_size) catch error.Unexpected;
    }

    pub fn getByName(self: *MarketService, name: []const u8) MarketError!?MarketPackageRow {
        return self.store.getByName(name) catch error.Unexpected;
    }

    /// 校验内容 sha256 是否与期望 hex 匹配（空期望跳过）。
    pub fn verifyChecksum(content: []const u8, expected_hex: []const u8) bool {
        if (expected_hex.len == 0) return true;
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(content, &digest, .{});
        const hex = std.fmt.bytesToHex(digest, .lower);
        return std.mem.eql(u8, &hex, expected_hex);
    }

    /// 下载产物 → 校验 → 写入产物托管后端。key = `{name}-{version}.bin`。
    pub fn fetchArtifact(self: *MarketService, name: []const u8) MarketError!void {
        const pkg_opt = self.store.getByName(name) catch return error.Unexpected;
        const pkg = pkg_opt orelse return error.NotFound;
        defer pkg.free(self.allocator);
        if (pkg.download_url.len == 0) return error.NotFound; // 无产物源

        var client = zwechat_http_client(self.allocator);
        defer client.deinit();
        const body = client.get(pkg.download_url) catch return error.DownloadFailed;
        defer self.allocator.free(body);
        if (!verifyChecksum(body, pkg.checksum)) return error.ChecksumMismatch;

        const key = try self.artifactKey(pkg.name, pkg.version);
        defer self.allocator.free(key);
        self.artifact.put(self.allocator, key, body) catch return error.Unexpected;
    }

    /// 读取托管产物（站点端下载用）。caller-owned。
    pub fn readArtifact(self: *MarketService, name: []const u8, version: []const u8) MarketError![]u8 {
        if (!safeArtifactComponent(name) or !safeArtifactComponent(version)) return error.InvalidName;
        const key = try self.artifactKey(name, version);
        defer self.allocator.free(key);
        return self.artifact.get(self.allocator, key) catch |err| switch (err) {
            error.NotFound => error.NotFound,
            else => error.Unexpected,
        };
    }

    fn artifactKey(self: *MarketService, name: []const u8, version: []const u8) MarketError![]u8 {
        return std.fmt.allocPrint(self.allocator, "{s}-{s}.bin", .{ name, version }) catch error.Unexpected;
    }

    /// 产物文件名组件安全校验（[a-zA-Z0-9_.-]，1-64，防路径逃逸；允许
    /// `.` 以支持版本号，`.` 不会形成路径段逃逸）。
    pub fn safeArtifactComponent(s: []const u8) bool {
        if (s.len == 0 or s.len > 64) return false;
        for (s) |c| {
            const ok = (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_' or c == '-' or c == '.';
            if (!ok) return false;
        }
        return true;
    }
};

/// zwechat 的 HTTP client（下载产物）。
const zwechat = @import("zwechat");
fn zwechat_http_client(allocator: std.mem.Allocator) zwechat.util.http.HttpClient {
    return zwechat.util.http.HttpClient.init(allocator);
}
