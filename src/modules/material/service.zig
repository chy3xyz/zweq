//! Material service — 素材库（图文 news + 图片/语音/视频 file）。No HTTP/SQL leakage.

const std = @import("std");
const zigmodu = @import("zigmodu");
const persist = @import("persistence.zig");

pub const MaterialNewsRow = persist.MaterialNewsRow;
pub const MaterialNewsListResult = persist.MaterialNewsListResult;
pub const MaterialFileRow = persist.MaterialFileRow;
pub const MaterialFileListResult = persist.MaterialFileListResult;

pub const MaterialError = error{
    InvalidTitle,
    InvalidKind,
    NotFound,
    Unexpected,
};

pub fn validKind(kind: []const u8) bool {
    return std.mem.eql(u8, kind, "image") or
        std.mem.eql(u8, kind, "voice") or
        std.mem.eql(u8, kind, "video");
}

pub const MaterialService = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    store: *persist.MaterialStore,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, store: *persist.MaterialStore) MaterialService {
        return .{ .allocator = allocator, .io = io, .store = store };
    }

    fn now(self: *MaterialService) i64 {
        return zigmodu.time.wallClockSeconds(self.io);
    }

    pub fn createNews(self: *MaterialService, tenant_id: i64, account_id: i64, title: []const u8, author: []const u8, digest: []const u8, content: []const u8, thumb_media_id: []const u8, thumb_url: []const u8, url: []const u8) MaterialError!i64 {
        if (std.mem.trim(u8, title, " \t").len == 0) return error.InvalidTitle;
        return self.store.createNews(tenant_id, account_id, title, author, digest, content, thumb_media_id, thumb_url, url, self.now()) catch error.Unexpected;
    }

    pub fn getNews(self: *MaterialService, id: i64) MaterialError!?MaterialNewsRow {
        return self.store.getNews(id) catch error.Unexpected;
    }

    pub fn listNews(self: *MaterialService, page: usize, page_size: usize, tenant_id: i64, account_id: i64) MaterialError!MaterialNewsListResult {
        return self.store.listNews(page, page_size, tenant_id, account_id) catch error.Unexpected;
    }

    pub fn updateNews(self: *MaterialService, id: i64, title: []const u8, author: []const u8, digest: []const u8, content: []const u8, thumb_media_id: []const u8, thumb_url: []const u8, url: []const u8) MaterialError!void {
        if (std.mem.trim(u8, title, " \t").len == 0) return error.InvalidTitle;
        self.store.updateNews(id, title, author, digest, content, thumb_media_id, thumb_url, url, self.now()) catch return error.Unexpected;
    }

    pub fn deleteNews(self: *MaterialService, id: i64) MaterialError!void {
        self.store.deleteNews(id) catch return error.Unexpected;
    }

    pub fn createFile(self: *MaterialService, tenant_id: i64, account_id: i64, kind: []const u8, media_id: []const u8, url: []const u8) MaterialError!i64 {
        if (!validKind(kind)) return error.InvalidKind;
        return self.store.createFile(tenant_id, account_id, kind, media_id, url, self.now()) catch error.Unexpected;
    }

    pub fn listFiles(self: *MaterialService, page: usize, page_size: usize, tenant_id: i64, account_id: i64, kind: ?[]const u8) MaterialError!MaterialFileListResult {
        return self.store.listFiles(page, page_size, tenant_id, account_id, kind) catch error.Unexpected;
    }

    pub fn deleteFile(self: *MaterialService, id: i64) MaterialError!void {
        self.store.deleteFile(id) catch return error.Unexpected;
    }
};
