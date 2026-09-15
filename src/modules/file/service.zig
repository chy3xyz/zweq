//! File service — local-disk storage with DB metadata.

const std = @import("std");
const zigmodu = @import("zigmodu");
const persist = @import("persistence.zig");

pub const FileRow = persist.FileRow;
pub const FileListResult = persist.FileListResult;

pub const LoadedFile = struct {
    row: FileRow,
    bytes: []u8,

    pub fn free(self: *LoadedFile, allocator: std.mem.Allocator) void {
        self.row.free(allocator);
        allocator.free(self.bytes);
    }
};

/// 上传内容策略（生产与测试共用同一份，避免推断漂移）：字节嗅探 + 主动内容
/// fail-closed，但**不**要求扩展名与内容一致——本模块是通用文件管理，
/// `.docx`/`.xlsx`/`.jar` 内容本就是 ZIP、`.heic`/`.rar`/`.mov` 无魔数，
/// 开了对齐会把正常上传判死。窄接口（例如只收头像）应另配白名单收紧。
pub const upload_policy = zigmodu.http.UploadGuard.Policy{ .require_extension_match = false };

pub const FileService = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    store: *persist.FileStore,
    group_store: *persist.GroupStore,
    upload_dir: []const u8,
    max_bytes: usize,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, store: *persist.FileStore, group_store: *persist.GroupStore, upload_dir: []const u8, max_bytes: usize) FileService {
        return .{ .allocator = allocator, .io = io, .store = store, .group_store = group_store, .upload_dir = upload_dir, .max_bytes = max_bytes };
    }

    pub fn ensureDir(self: *FileService) !void {
        var dir = std.Io.Dir.cwd();
        dir.createDir(self.io, self.upload_dir, .default_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }

    /// Reject mime types a browser may render as active content (XSS risk).
    /// Only the base type (before `;`) is compared.
    pub fn validMime(mime: []const u8) bool {
        var base = mime;
        if (std.mem.indexOfScalar(u8, mime, ';')) |i| base = mime[0..i];
        base = std.mem.trim(u8, base, " \t");
        const dangerous = [_][]const u8{
            "text/html",
            "image/svg+xml",
            "application/xhtml+xml",
            "application/xml",
            "text/xml",
            "application/javascript",
            "text/javascript",
        };
        for (dangerous) |d| {
            if (std.mem.eql(u8, base, d)) return false;
        }
        return true;
    }

    /// Persist raw bytes to disk and record metadata. `filename` is the
    /// user-facing name; the on-disk name is a generated storage key.
    pub fn save(self: *FileService, uploader_id: i64, tenant_id: i64, group_id: i64, filename: []const u8, mime: []const u8, data: []const u8) !FileRow {
        if (data.len > self.max_bytes) return error.FileTooLarge;
        if (!validMime(mime)) return error.InvalidMime;
        // 内容判定以**字节**为准（zigmodu v0.15.46 `http.UploadGuard` 嗅探魔数）：
        // 上面两道检查用的都是客户端自己写的头/文件名，`说明.png` + `image/png`
        // 里装 HTML/SVG 正是同源存储型 XSS 的经典形态。策略见 `upload_policy`
        // （主动内容 fail-closed 拒绝；不要求扩展名与内容一致）。
        _ = zigmodu.http.UploadGuard.check(filename, data, upload_policy) catch |err| switch (err) {
            error.ActiveContentNotAllowed => return error.ActiveContent,
            else => return error.InvalidMime,
        };
        try self.ensureDir();

        const key = try self.storageKey(filename);
        defer self.allocator.free(key);

        const path = try self.pathFor(key);
        defer self.allocator.free(path);

        var file = try std.Io.Dir.cwd().createFile(self.io, path, .{ .exclusive = true });
        errdefer file.close(self.io);
        try file.writePositionalAll(self.io, data, 0);
        file.close(self.io);

        const now = wallNow(self.io);
        const id = self.store.create(filename, key, mime, @intCast(data.len), uploader_id, tenant_id, group_id, now) catch |err| {
            // Roll back the orphaned disk file on metadata failure.
            std.Io.Dir.cwd().deleteFile(self.io, path) catch {};
            return err;
        };
        return (self.store.getById(id) catch return error.Unexpected) orelse return error.Unexpected;
    }

    /// Read file bytes back from disk.
    pub fn load(self: *FileService, id: i64) !?LoadedFile {
        const row_opt = try self.store.getById(id);
        const row = row_opt orelse return null;
        errdefer row.free(self.allocator);

        const path = try self.pathFor(row.storage_key);
        defer self.allocator.free(path);

        const bytes = std.Io.Dir.cwd().readFileAlloc(self.io, path, self.allocator, .limited(self.max_bytes)) catch |err| switch (err) {
            error.FileNotFound => return null,
            else => return err,
        };
        return .{ .row = row, .bytes = bytes };
    }

    pub fn list(self: *FileService, page: usize, page_size: usize, uploader_id: ?i64, tenant_id: ?i64, group_id: ?i64, mime_prefix: ?[]const u8, sort_col: ?[]const u8, sort_desc: bool) !FileListResult {
        return self.store.list(page, page_size, uploader_id, tenant_id, group_id, mime_prefix, sort_col, sort_desc);
    }

    // ── Upload groups (file-manager categories) ──

    pub fn createGroup(self: *FileService, name: []const u8, group_type: []const u8, sort: i64, tenant_id: i64) !i64 {
        const now = wallNow(self.io);
        return self.group_store.create(name, group_type, sort, tenant_id, now);
    }

    pub fn listGroups(self: *FileService, tenant_id: i64) ![]persist.GroupRow {
        return self.group_store.list(tenant_id);
    }

    pub fn getGroup(self: *FileService, id: i64) !?persist.GroupRow {
        return self.group_store.getById(id);
    }

    pub fn updateGroup(self: *FileService, id: i64, name: []const u8, sort: i64) !void {
        return self.group_store.update(id, name, sort);
    }

    pub fn deleteGroup(self: *FileService, id: i64) !void {
        return self.group_store.delete(id);
    }

    pub fn countGroupFiles(self: *FileService, group_id: i64) !i64 {
        return self.group_store.countFiles(group_id);
    }

    pub fn get(self: *FileService, id: i64) !?FileRow {
        return self.store.getById(id);
    }

    /// Delete metadata and the disk file.
    pub fn delete(self: *FileService, id: i64) !void {
        const row_opt = try self.store.getById(id);
        const row = row_opt orelse return;
        defer row.free(self.allocator);
        try self.store.delete(id);
        const path = try self.pathFor(row.storage_key);
        defer self.allocator.free(path);
        std.Io.Dir.cwd().deleteFile(self.io, path) catch {};
    }

    fn storageKey(self: *FileService, filename: []const u8) ![]const u8 {
        const now = wallNow(self.io);
        const ext = extensionOf(filename);
        return std.fmt.allocPrint(self.allocator, "{d}-{x}-{s}", .{ now, randomU32(self.io), ext });
    }

    fn pathFor(self: *FileService, storage_key: []const u8) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.upload_dir, storage_key });
    }
};

fn wallNow(io: std.Io) i64 {
    return zigmodu.time.wallClockSeconds(io);
}

fn extensionOf(filename: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, filename, '.')) |i| {
        const ext = filename[i + 1 ..];
        if (ext.len > 0 and ext.len <= 16) return ext;
    }
    return "bin";
}

fn randomU32(io: std.Io) u32 {
    var buf: [4]u8 = undefined;
    var file = std.Io.Dir.cwd().openFile(io, "/dev/urandom", .{}) catch return 0;
    defer file.close(io);
    _ = file.readPositionalAll(io, &buf, 0) catch return 0;
    return std.mem.readInt(u32, &buf, .big);
}
