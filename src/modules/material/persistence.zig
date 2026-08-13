//! Persistence over the zent Client — material library (news + files).

const std = @import("std");
const zent = @import("zent");
const model = @import("model.zig");
const schema = @import("../../schema.zig");

const graph = zent.codegen.graph.buildGraph(&.{ model.MaterialNews, model.MaterialFile });
pub const infos = graph.types;
/// Shared, application-wide typed client (all schemas registered in schema.zig).
pub const Client = schema.Client;
pub const MaterialNewsInfo = infos[0];
pub const MaterialFileInfo = infos[1];

pub const MaterialNewsRow = struct {
    id: i64,
    tenant_id: i64,
    account_id: i64,
    media_id: []const u8,
    title: []const u8,
    author: []const u8,
    digest: []const u8,
    content: []const u8,
    thumb_media_id: []const u8,
    thumb_url: []const u8,
    url: []const u8,
    created_at: i64,
    updated_at: i64,

    pub fn free(self: MaterialNewsRow, allocator: std.mem.Allocator) void {
        allocator.free(self.media_id);
        allocator.free(self.title);
        allocator.free(self.author);
        allocator.free(self.digest);
        allocator.free(self.content);
        allocator.free(self.thumb_media_id);
        allocator.free(self.thumb_url);
        allocator.free(self.url);
    }
};

pub const MaterialNewsListResult = struct {
    items: []MaterialNewsRow,
    total: i64,

    pub fn free(self: *MaterialNewsListResult, allocator: std.mem.Allocator) void {
        for (self.items) |r| r.free(allocator);
        allocator.free(self.items);
    }
};

pub const MaterialFileRow = struct {
    id: i64,
    tenant_id: i64,
    account_id: i64,
    kind: []const u8,
    media_id: []const u8,
    url: []const u8,
    created_at: i64,
    updated_at: i64,

    pub fn free(self: MaterialFileRow, allocator: std.mem.Allocator) void {
        allocator.free(self.kind);
        allocator.free(self.media_id);
        allocator.free(self.url);
    }
};

pub const MaterialFileListResult = struct {
    items: []MaterialFileRow,
    total: i64,

    pub fn free(self: *MaterialFileListResult, allocator: std.mem.Allocator) void {
        for (self.items) |r| r.free(allocator);
        allocator.free(self.items);
    }
};

pub const MaterialStore = struct {
    allocator: std.mem.Allocator,
    client: Client,

    pub fn init(allocator: std.mem.Allocator, client: Client) MaterialStore {
        return .{ .allocator = allocator, .client = client };
    }

    fn dupNews(self: *MaterialStore, e: anytype) !MaterialNewsRow {
        const media_id = try self.allocator.dupe(u8, e.media_id);
        errdefer self.allocator.free(media_id);
        const title = try self.allocator.dupe(u8, e.title);
        errdefer self.allocator.free(title);
        const author = try self.allocator.dupe(u8, e.author);
        errdefer self.allocator.free(author);
        const digest = try self.allocator.dupe(u8, e.digest);
        errdefer self.allocator.free(digest);
        const content = try self.allocator.dupe(u8, e.content);
        errdefer self.allocator.free(content);
        const thumb_media_id = try self.allocator.dupe(u8, e.thumb_media_id);
        errdefer self.allocator.free(thumb_media_id);
        const thumb_url = try self.allocator.dupe(u8, e.thumb_url);
        errdefer self.allocator.free(thumb_url);
        const url = try self.allocator.dupe(u8, e.url);
        errdefer self.allocator.free(url);
        return .{
            .id = e.id,
            .tenant_id = e.tenant_id,
            .account_id = e.account_id,
            .media_id = media_id,
            .title = title,
            .author = author,
            .digest = digest,
            .content = content,
            .thumb_media_id = thumb_media_id,
            .thumb_url = thumb_url,
            .url = url,
            .created_at = e.created_at orelse 0,
            .updated_at = e.updated_at orelse 0,
        };
    }

    fn dupFile(self: *MaterialStore, e: anytype) !MaterialFileRow {
        const kind = try self.allocator.dupe(u8, e.kind);
        errdefer self.allocator.free(kind);
        const media_id = try self.allocator.dupe(u8, e.media_id);
        errdefer self.allocator.free(media_id);
        const url = try self.allocator.dupe(u8, e.url);
        errdefer self.allocator.free(url);
        return .{
            .id = e.id,
            .tenant_id = e.tenant_id,
            .account_id = e.account_id,
            .kind = kind,
            .media_id = media_id,
            .url = url,
            .created_at = e.created_at orelse 0,
            .updated_at = e.updated_at orelse 0,
        };
    }

    // ── MaterialNews ─────────────────────────────────────────────

    pub fn createNews(self: *MaterialStore, tenant_id: i64, account_id: i64, title: []const u8, author: []const u8, digest: []const u8, content: []const u8, thumb_media_id: []const u8, thumb_url: []const u8, url: []const u8, now: i64) !i64 {
        var b = try self.client.material_news.Create();
        defer b.deinit();
        _ = try b.setFieldValue("tenant_id", tenant_id);
        _ = try b.setFieldValue("account_id", account_id);
        _ = try b.setFieldValue("title", title);
        _ = try b.setFieldValue("author", author);
        _ = try b.setFieldValue("digest", digest);
        _ = try b.setFieldValue("content", content);
        _ = try b.setFieldValue("thumb_media_id", thumb_media_id);
        _ = try b.setFieldValue("thumb_url", thumb_url);
        _ = try b.setFieldValue("url", url);
        _ = try b.setFieldValue("created_at", now);
        _ = try b.setFieldValue("updated_at", now);
        var row = try b.Save();
        defer zent.codegen.deinitEntity(infos, MaterialNewsInfo, &row, self.allocator);
        return row.id;
    }

    pub fn getNews(self: *MaterialStore, id: i64) !?MaterialNewsRow {
        var q = self.client.material_news.Query();
        defer q.deinit();
        const preds = self.client.material_news.predicates;
        _ = try q.Where(.{preds.idEQ(.{ .int = id })});
        const entity_opt = try q.First();
        var entity = entity_opt orelse return null;
        defer zent.codegen.deinitEntity(infos, MaterialNewsInfo, &entity, self.allocator);
        return try self.dupNews(entity);
    }

    pub fn listNews(self: *MaterialStore, page: usize, page_size: usize, tenant_id: i64, account_id: i64) !MaterialNewsListResult {
        var q = self.client.material_news.Query();
        defer q.deinit();
        const preds = self.client.material_news.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderDesc("id")});

        var paged = try q.paged(page, page_size);
        defer paged.deinit();

        var out = try self.allocator.alloc(MaterialNewsRow, paged.items.items.len);
        var n: usize = 0;
        errdefer {
            for (out[0..n]) |r| r.free(self.allocator);
            self.allocator.free(out);
        }
        for (paged.items.items) |e| {
            out[n] = try self.dupNews(e);
            n += 1;
        }
        return .{ .items = out, .total = paged.total };
    }

    pub fn updateNews(self: *MaterialStore, id: i64, title: []const u8, author: []const u8, digest: []const u8, content: []const u8, thumb_media_id: []const u8, thumb_url: []const u8, url: []const u8, now: i64) !void {
        const preds = self.client.material_news.predicates;
        var upd = self.client.material_news.Update();
        defer upd.deinit();
        _ = try upd.set("title", .{ .string = title });
        _ = try upd.set("author", .{ .string = author });
        _ = try upd.set("digest", .{ .string = digest });
        _ = try upd.set("content", .{ .string = content });
        _ = try upd.set("thumb_media_id", .{ .string = thumb_media_id });
        _ = try upd.set("thumb_url", .{ .string = thumb_url });
        _ = try upd.set("url", .{ .string = url });
        _ = try upd.setFieldValue("updated_at", now);
        _ = try upd.Where(.{preds.idEQ(.{ .int = id })});
        _ = try upd.Save();
    }

    pub fn deleteNews(self: *MaterialStore, id: i64) !void {
        const preds = self.client.material_news.predicates;
        var d = self.client.material_news.Delete();
        defer d.deinit();
        _ = try d.Where(.{preds.idEQ(.{ .int = id })});
        _ = try d.Exec();
    }

    /// 按微信 media_id 查图文素材。
    pub fn getNewsByMediaId(self: *MaterialStore, tenant_id: i64, account_id: i64, media_id: []const u8) !?MaterialNewsRow {
        var q = self.client.material_news.Query();
        defer q.deinit();
        const preds = self.client.material_news.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.Where(.{preds.media_idEQ(.{ .string = media_id })});
        var entity = (try q.First()) orelse return null;
        defer zent.codegen.deinitEntity(infos, MaterialNewsInfo, &entity, self.allocator);
        return try self.dupNews(entity);
    }

    /// 按 media_id upsert 图文素材（同步微信素材用）。返回行 id。
    pub fn upsertNews(self: *MaterialStore, tenant_id: i64, account_id: i64, media_id: []const u8, title: []const u8, author: []const u8, digest: []const u8, content: []const u8, thumb_media_id: []const u8, thumb_url: []const u8, url: []const u8, now: i64) !i64 {
        if (try self.getNewsByMediaId(tenant_id, account_id, media_id)) |row| {
            defer row.free(self.allocator);
            const preds = self.client.material_news.predicates;
            var upd = self.client.material_news.Update();
            defer upd.deinit();
            _ = try upd.set("title", .{ .string = title });
            _ = try upd.set("author", .{ .string = author });
            _ = try upd.set("digest", .{ .string = digest });
            _ = try upd.set("content", .{ .string = content });
            _ = try upd.set("thumb_media_id", .{ .string = thumb_media_id });
            _ = try upd.set("thumb_url", .{ .string = thumb_url });
            _ = try upd.set("url", .{ .string = url });
            _ = try upd.setFieldValue("updated_at", now);
            _ = try upd.Where(.{preds.idEQ(.{ .int = row.id })});
            _ = try upd.Save();
            return row.id;
        }
        var b = try self.client.material_news.Create();
        defer b.deinit();
        _ = try b.setFieldValue("tenant_id", tenant_id);
        _ = try b.setFieldValue("account_id", account_id);
        _ = try b.setFieldValue("media_id", media_id);
        _ = try b.setFieldValue("title", title);
        _ = try b.setFieldValue("author", author);
        _ = try b.setFieldValue("digest", digest);
        _ = try b.setFieldValue("content", content);
        _ = try b.setFieldValue("thumb_media_id", thumb_media_id);
        _ = try b.setFieldValue("thumb_url", thumb_url);
        _ = try b.setFieldValue("url", url);
        _ = try b.setFieldValue("created_at", now);
        _ = try b.setFieldValue("updated_at", now);
        var nrow = try b.Save();
        defer zent.codegen.deinitEntity(infos, MaterialNewsInfo, &nrow, self.allocator);
        return nrow.id;
    }

    // ── MaterialFile ──────────────────────────────────────────────

    pub fn createFile(self: *MaterialStore, tenant_id: i64, account_id: i64, kind: []const u8, media_id: []const u8, url: []const u8, now: i64) !i64 {
        var b = try self.client.material_file.Create();
        defer b.deinit();
        _ = try b.setFieldValue("tenant_id", tenant_id);
        _ = try b.setFieldValue("account_id", account_id);
        _ = try b.setFieldValue("kind", kind);
        _ = try b.setFieldValue("media_id", media_id);
        _ = try b.setFieldValue("url", url);
        _ = try b.setFieldValue("created_at", now);
        _ = try b.setFieldValue("updated_at", now);
        var row = try b.Save();
        defer zent.codegen.deinitEntity(infos, MaterialFileInfo, &row, self.allocator);
        return row.id;
    }

    pub fn listFiles(self: *MaterialStore, page: usize, page_size: usize, tenant_id: i64, account_id: i64, kind: ?[]const u8) !MaterialFileListResult {
        var q = self.client.material_file.Query();
        defer q.deinit();
        const preds = self.client.material_file.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        if (kind) |k| {
            if (k.len > 0) _ = try q.Where(.{preds.kindEQ(.{ .string = k })});
        }
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderDesc("id")});

        var paged = try q.paged(page, page_size);
        defer paged.deinit();

        var out = try self.allocator.alloc(MaterialFileRow, paged.items.items.len);
        var n: usize = 0;
        errdefer {
            for (out[0..n]) |r| r.free(self.allocator);
            self.allocator.free(out);
        }
        for (paged.items.items) |e| {
            out[n] = try self.dupFile(e);
            n += 1;
        }
        return .{ .items = out, .total = paged.total };
    }

    pub fn deleteFile(self: *MaterialStore, id: i64) !void {
        const preds = self.client.material_file.predicates;
        var d = self.client.material_file.Delete();
        defer d.deinit();
        _ = try d.Where(.{preds.idEQ(.{ .int = id })});
        _ = try d.Exec();
    }

    /// 按微信 media_id 查素材文件。
    pub fn getFileByMediaId(self: *MaterialStore, tenant_id: i64, account_id: i64, media_id: []const u8) !?MaterialFileRow {
        var q = self.client.material_file.Query();
        defer q.deinit();
        const preds = self.client.material_file.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.Where(.{preds.media_idEQ(.{ .string = media_id })});
        var entity = (try q.First()) orelse return null;
        defer zent.codegen.deinitEntity(infos, MaterialFileInfo, &entity, self.allocator);
        return try self.dupFile(entity);
    }

    /// 按 media_id upsert 素材文件（同步微信素材用）。返回行 id。
    pub fn upsertFile(self: *MaterialStore, tenant_id: i64, account_id: i64, kind: []const u8, media_id: []const u8, url: []const u8, now: i64) !i64 {
        if (try self.getFileByMediaId(tenant_id, account_id, media_id)) |row| {
            defer row.free(self.allocator);
            const preds = self.client.material_file.predicates;
            var upd = self.client.material_file.Update();
            defer upd.deinit();
            _ = try upd.set("kind", .{ .string = kind });
            _ = try upd.set("url", .{ .string = url });
            _ = try upd.setFieldValue("updated_at", now);
            _ = try upd.Where(.{preds.idEQ(.{ .int = row.id })});
            _ = try upd.Save();
            return row.id;
        }
        var b = try self.client.material_file.Create();
        defer b.deinit();
        _ = try b.setFieldValue("tenant_id", tenant_id);
        _ = try b.setFieldValue("account_id", account_id);
        _ = try b.setFieldValue("kind", kind);
        _ = try b.setFieldValue("media_id", media_id);
        _ = try b.setFieldValue("url", url);
        _ = try b.setFieldValue("created_at", now);
        _ = try b.setFieldValue("updated_at", now);
        var nrow = try b.Save();
        defer zent.codegen.deinitEntity(infos, MaterialFileInfo, &nrow, self.allocator);
        return nrow.id;
    }
};
