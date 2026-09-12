//! Persistence over the zent Client — uploaded file metadata.

const std = @import("std");
const zent = @import("zent");
const crud = zent.crud_helpers;
const model = @import("model.zig");
const schema = @import("../../schema.zig");

const graph = zent.codegen.graph.buildGraph(&.{ model.File, model.UploadGroup });
pub const infos = graph.types;
pub const Client = schema.Client;
pub const FileInfo = infos[0];
pub const GroupInfo = infos[1];

pub const FileRow = struct {
    id: i64,
    name: []const u8,
    storage_key: []const u8,
    mime: []const u8,
    size_bytes: i64,
    uploader_id: i64,
    tenant_id: i64,
    group_id: i64,
    created_at: i64,
    updated_at: i64,

    pub fn free(self: FileRow, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.storage_key);
        allocator.free(self.mime);
    }
};

pub const GroupRow = struct {
    id: i64,
    group_name: []const u8,
    group_type: []const u8,
    sort: i64,
    tenant_id: i64,
    created_at: i64,
    updated_at: i64,

    pub fn free(self: GroupRow, allocator: std.mem.Allocator) void {
        allocator.free(self.group_name);
        allocator.free(self.group_type);
    }
};

pub const FileListResult = struct {
    items: []FileRow,
    total: i64,

    pub fn free(self: *FileListResult, allocator: std.mem.Allocator) void {
        for (self.items) |r| r.free(allocator);
        allocator.free(self.items);
    }
};

pub const FileStore = struct {
    allocator: std.mem.Allocator,
    client: Client,

    pub fn init(allocator: std.mem.Allocator, client: Client) FileStore {
        return .{ .allocator = allocator, .client = client };
    }

    fn dup(self: *FileStore, e: anytype) !FileRow {
        const name = try self.allocator.dupe(u8, e.name);
        errdefer self.allocator.free(name);
        const storage_key = try self.allocator.dupe(u8, e.storage_key);
        errdefer self.allocator.free(storage_key);
        const mime = try self.allocator.dupe(u8, e.mime);
        errdefer self.allocator.free(mime);
        return .{
            .id = e.id,
            .name = name,
            .storage_key = storage_key,
            .mime = mime,
            .size_bytes = e.size_bytes,
            .uploader_id = e.uploader_id,
            .tenant_id = e.tenant_id,
            .group_id = e.group_id,
            .created_at = e.created_at orelse 0,
            .updated_at = e.updated_at orelse 0,
        };
    }

    pub fn create(self: *FileStore, name: []const u8, storage_key: []const u8, mime: []const u8, size_bytes: i64, uploader_id: i64, tenant_id: i64, group_id: i64, now: i64) !i64 {
        var row = try crud.create(self.client.file, .{
            .name = name,
            .storage_key = storage_key,
            .mime = mime,
            .size_bytes = size_bytes,
            .uploader_id = uploader_id,
            .tenant_id = tenant_id,
            .group_id = group_id,
            .created_at = now,
            .updated_at = now,
        });
        defer self.client.file.deinitRow(&row);
        return row.id;
    }

    pub fn getById(self: *FileStore, id: i64) !?FileRow {
        const preds = self.client.file.predicates;
        var entity = (try crud.first(self.client.file, .{preds.idEQ(.{ .int = id })})) orelse return null;
        defer self.client.file.deinitRow(&entity);
        return try self.dup(entity);
    }

    pub fn getByStorageKey(self: *FileStore, storage_key: []const u8) !?FileRow {
        const preds = self.client.file.predicates;
        var entity = (try crud.first(self.client.file, .{preds.storage_keyEQ(.{ .string = storage_key })})) orelse return null;
        defer self.client.file.deinitRow(&entity);
        return try self.dup(entity);
    }

    pub fn list(self: *FileStore, page: usize, page_size: usize, uploader_id: ?i64, tenant_id: ?i64, group_id: ?i64, mime_prefix: ?[]const u8, sort_col: ?[]const u8, sort_desc: bool) !FileListResult {
        const preds = self.client.file.predicates;
        const owner_pred = if (uploader_id) |uid| preds.uploader_idEQ(.{ .int = uid }) else null;
        const tenant_pred = if (tenant_id) |tid| preds.tenant_idEQ(.{ .int = tid }) else null;
        const group_pred = if (group_id) |gid| preds.group_idEQ(.{ .int = gid }) else null;
        const mime_pred = if (mime_prefix) |mp| preds.mimeContainsEscaped(mp) else null;

        var q = self.client.file.Query();
        defer q.deinit();
        if (owner_pred) |op| _ = try q.Where(.{op});
        if (tenant_pred) |tp| _ = try q.Where(.{tp});
        if (group_pred) |gp| _ = try q.Where(.{gp});
        if (mime_pred) |mp| _ = try q.Where(.{mp});
        const order: zent.sql.Order = if (sort_col) |col| blk: {
            if (!(std.mem.eql(u8, col, "name") or std.mem.eql(u8, col, "size_bytes") or std.mem.eql(u8, col, "created_at")))
                break :blk zent.sql.Order{ .column = .{ .name = "created_at", .desc = true } };
            break :blk if (sort_desc) zent.sql.OrderDesc(col) else zent.sql.OrderAsc(col);
        } else zent.sql.Order{ .column = .{ .name = "created_at", .desc = true } };
        _ = try q.OrderBy(&.{order});

        var paged = try q.paged(page, page_size);
        defer paged.deinit();

        var out = try self.allocator.alloc(FileRow, paged.items.items.len);
        var n: usize = 0;
        errdefer {
            for (out[0..n]) |r| r.free(self.allocator);
            self.allocator.free(out);
        }
        for (paged.items.items) |e| {
            out[n] = try self.dup(e);
            n += 1;
        }
        return .{ .items = out, .total = paged.total };
    }

    pub fn delete(self: *FileStore, id: i64) !void {
        const preds = self.client.file.predicates;
        _ = try crud.delete(self.client.file, .{preds.idEQ(.{ .int = id })});
    }

    /// Total file count (dashboard stats).
    pub fn countAll(self: *FileStore) !i64 {
        return crud.count(self.client.file, .{});
    }
};

pub const GroupStore = struct {
    allocator: std.mem.Allocator,
    client: Client,

    pub fn init(allocator: std.mem.Allocator, client: Client) GroupStore {
        return .{ .allocator = allocator, .client = client };
    }

    fn dupGroup(self: *GroupStore, e: anytype) !GroupRow {
        const name = try self.allocator.dupe(u8, e.group_name);
        errdefer self.allocator.free(name);
        const gtype = try self.allocator.dupe(u8, e.group_type);
        errdefer self.allocator.free(gtype);
        return .{
            .id = e.id,
            .group_name = name,
            .group_type = gtype,
            .sort = e.sort,
            .tenant_id = e.tenant_id,
            .created_at = e.created_at orelse 0,
            .updated_at = e.updated_at orelse 0,
        };
    }

    pub fn create(self: *GroupStore, name: []const u8, group_type: []const u8, sort: i64, tenant_id: i64, now: i64) !i64 {
        var row = try crud.create(self.client.upload_group, .{
            .group_name = name,
            .group_type = group_type,
            .sort = sort,
            .tenant_id = tenant_id,
            .created_at = now,
            .updated_at = now,
        });
        defer self.client.upload_group.deinitRow(&row);
        return row.id;
    }

    pub fn list(self: *GroupStore, tenant_id: i64) ![]GroupRow {
        const preds = self.client.upload_group.predicates;
        var q = self.client.upload_group.Query();
        defer q.deinit();
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderDesc("sort")});
        var paged = try q.paged(1, 1000);
        defer paged.deinit();
        var out = try self.allocator.alloc(GroupRow, paged.items.items.len);
        var n: usize = 0;
        errdefer {
            for (out[0..n]) |r| r.free(self.allocator);
            self.allocator.free(out);
        }
        for (paged.items.items) |e| {
            out[n] = try self.dupGroup(e);
            n += 1;
        }
        return out;
    }

    pub fn getById(self: *GroupStore, id: i64) !?GroupRow {
        const preds = self.client.upload_group.predicates;
        var entity = (try crud.first(self.client.upload_group, .{preds.idEQ(.{ .int = id })})) orelse return null;
        defer self.client.upload_group.deinitRow(&entity);
        return try self.dupGroup(entity);
    }

    pub fn update(self: *GroupStore, id: i64, name: []const u8, sort: i64) !void {
        const preds = self.client.upload_group.predicates;
        _ = try crud.update(self.client.upload_group, .{ .group_name = name, .sort = sort }, .{preds.idEQ(.{ .int = id })});
    }

    pub fn delete(self: *GroupStore, id: i64) !void {
        const preds = self.client.upload_group.predicates;
        _ = try crud.delete(self.client.upload_group, .{preds.idEQ(.{ .int = id })});
    }

    pub fn countFiles(self: *GroupStore, group_id: i64) !i64 {
        const preds = self.client.file.predicates;
        return crud.count(self.client.file, .{preds.group_idEQ(.{ .int = group_id })});
    }
};
