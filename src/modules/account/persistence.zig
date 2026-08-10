//! Persistence over the zent Client — platform accounts and their WeChat config.

const std = @import("std");
const zent = @import("zent");
const model = @import("model.zig");
const schema = @import("../../schema.zig");

const graph = zent.codegen.graph.buildGraph(&.{ model.Account, model.AccountWechat });
pub const infos = graph.types;
/// Shared, application-wide typed client (all schemas registered in schema.zig).
pub const Client = schema.Client;
pub const AccountInfo = infos[0];
pub const AccountWechatInfo = infos[1];

pub const AccountRow = struct {
    id: i64,
    tenant_id: i64,
    name: []const u8,
    kind: []const u8,
    status: []const u8,
    created_at: i64,
    updated_at: i64,

    pub fn free(self: AccountRow, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.kind);
        allocator.free(self.status);
    }
};

pub const AccountWechatRow = struct {
    id: i64,
    tenant_id: i64,
    account_id: i64,
    appid: []const u8,
    token: []const u8,
    verified: bool,
    created_at: i64,
    updated_at: i64,

    pub fn free(self: AccountWechatRow, allocator: std.mem.Allocator) void {
        allocator.free(self.appid);
        allocator.free(self.token);
    }
};

pub const AccountListResult = struct {
    items: []AccountRow,
    total: i64,

    pub fn free(self: *AccountListResult, allocator: std.mem.Allocator) void {
        for (self.items) |r| r.free(allocator);
        allocator.free(self.items);
    }
};

pub const AccountStore = struct {
    allocator: std.mem.Allocator,
    client: Client,

    pub fn init(allocator: std.mem.Allocator, client: Client) AccountStore {
        return .{ .allocator = allocator, .client = client };
    }

    fn dupAccount(self: *AccountStore, e: anytype) !AccountRow {
        const name = try self.allocator.dupe(u8, e.name);
        errdefer self.allocator.free(name);
        const kind = try self.allocator.dupe(u8, e.kind);
        errdefer self.allocator.free(kind);
        const status = try self.allocator.dupe(u8, e.status);
        errdefer self.allocator.free(status);
        return .{
            .id = e.id,
            .tenant_id = e.tenant_id,
            .name = name,
            .kind = kind,
            .status = status,
            .created_at = e.created_at orelse 0,
            .updated_at = e.updated_at orelse 0,
        };
    }

    pub fn create(self: *AccountStore, tenant_id: i64, name: []const u8, kind: []const u8, status: []const u8, now: i64) !i64 {
        var b = try self.client.account.Create();
        defer b.deinit();
        _ = try b.setFieldValue("tenant_id", tenant_id);
        _ = try b.setFieldValue("name", name);
        _ = try b.setFieldValue("kind", kind);
        _ = try b.setFieldValue("status", status);
        _ = try b.setFieldValue("created_at", now);
        _ = try b.setFieldValue("updated_at", now);
        var row = try b.Save();
        defer zent.codegen.deinitEntity(infos, AccountInfo, &row, self.allocator);
        return row.id;
    }

    pub fn getById(self: *AccountStore, id: i64) !?AccountRow {
        var q = self.client.account.Query();
        defer q.deinit();
        const preds = self.client.account.predicates;
        _ = try q.Where(.{preds.idEQ(.{ .int = id })});
        const entity_opt = try q.First();
        var entity = entity_opt orelse return null;
        defer zent.codegen.deinitEntity(infos, AccountInfo, &entity, self.allocator);
        return try self.dupAccount(entity);
    }

    pub fn list(self: *AccountStore, page: usize, page_size: usize, tenant_id: ?i64, kind: ?[]const u8) !AccountListResult {
        var q = self.client.account.Query();
        defer q.deinit();
        const preds = self.client.account.predicates;
        if (tenant_id) |tid| _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tid })});
        if (kind) |k| {
            if (k.len > 0) _ = try q.Where(.{preds.kindEQ(.{ .string = k })});
        }
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderAsc("id")});

        var paged = try q.paged(page, page_size);
        defer paged.deinit();

        var out = try self.allocator.alloc(AccountRow, paged.items.items.len);
        var n: usize = 0;
        errdefer {
            for (out[0..n]) |r| r.free(self.allocator);
            self.allocator.free(out);
        }
        for (paged.items.items) |e| {
            out[n] = try self.dupAccount(e);
            n += 1;
        }
        return .{ .items = out, .total = paged.total };
    }

    pub fn update(self: *AccountStore, id: i64, name: []const u8, kind: []const u8, status: []const u8, now: i64) !bool {
        const preds = self.client.account.predicates;
        var upd = self.client.account.Update();
        defer upd.deinit();
        _ = try upd.set("name", .{ .string = name });
        _ = try upd.set("kind", .{ .string = kind });
        _ = try upd.set("status", .{ .string = status });
        _ = try upd.setFieldValue("updated_at", now);
        _ = try upd.Where(.{preds.idEQ(.{ .int = id })});
        _ = try upd.Save();
        return true;
    }

    pub fn delete(self: *AccountStore, id: i64) !void {
        const preds = self.client.account.predicates;
        var d = self.client.account.Delete();
        defer d.deinit();
        _ = try d.Where(.{preds.idEQ(.{ .int = id })});
        _ = try d.Exec();
    }

    // ── AccountWechat (1:1 WeChat config) ─────────────────────────

    fn dupWechat(self: *AccountStore, e: anytype) !AccountWechatRow {
        const appid = try self.allocator.dupe(u8, e.appid);
        errdefer self.allocator.free(appid);
        const token = try self.allocator.dupe(u8, e.token);
        errdefer self.allocator.free(token);
        return .{
            .id = e.id,
            .tenant_id = e.tenant_id,
            .account_id = e.account_id,
            .appid = appid,
            .token = token,
            .verified = e.verified,
            .created_at = e.created_at orelse 0,
            .updated_at = e.updated_at orelse 0,
        };
    }

    pub fn getWechatByAccount(self: *AccountStore, account_id: i64) !?AccountWechatRow {
        var q = self.client.account_wechat.Query();
        defer q.deinit();
        const preds = self.client.account_wechat.predicates;
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = q.Limit(1);
        const entity_opt = try q.First();
        var entity = entity_opt orelse return null;
        defer zent.codegen.deinitEntity(infos, AccountWechatInfo, &entity, self.allocator);
        return try self.dupWechat(entity);
    }

    /// Server callback lookup: find the account by its message-verify token.
    pub fn getWechatByToken(self: *AccountStore, token: []const u8) !?AccountWechatRow {
        if (token.len == 0) return null;
        var q = self.client.account_wechat.Query();
        defer q.deinit();
        const preds = self.client.account_wechat.predicates;
        _ = try q.Where(.{preds.tokenEQ(.{ .string = token })});
        _ = q.Limit(1);
        const entity_opt = try q.First();
        var entity = entity_opt orelse return null;
        defer zent.codegen.deinitEntity(infos, AccountWechatInfo, &entity, self.allocator);
        return try self.dupWechat(entity);
    }

    /// Raw secret + encoding_aes_key (Sensitive fields are not in the row).
    pub fn getWechatSecretsByAccount(self: *AccountStore, account_id: i64) !?struct { secret: []const u8, encoding_aes_key: []const u8 } {
        var q = self.client.account_wechat.Query();
        defer q.deinit();
        const preds = self.client.account_wechat.predicates;
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = q.Limit(1);
        const entity_opt = try q.First();
        var entity = entity_opt orelse return null;
        defer zent.codegen.deinitEntity(infos, AccountWechatInfo, &entity, self.allocator);
        const secret = try self.allocator.dupe(u8, entity.secret);
        errdefer self.allocator.free(secret);
        const key = try self.allocator.dupe(u8, entity.encoding_aes_key);
        errdefer self.allocator.free(key);
        return .{ .secret = secret, .encoding_aes_key = key };
    }

    /// Upsert a WeChat config for an account (1:1). Returns the row id.
    pub fn upsertWechat(self: *AccountStore, tenant_id: i64, account_id: i64, appid: []const u8, secret: []const u8, token: []const u8, encoding_aes_key: []const u8, verified: bool, now: i64) !i64 {
        const existing = try self.getWechatByAccount(account_id);
        if (existing) |row| {
            defer row.free(self.allocator);
            const preds = self.client.account_wechat.predicates;
            var upd = self.client.account_wechat.Update();
            defer upd.deinit();
            _ = try upd.set("appid", .{ .string = appid });
            _ = try upd.set("secret", .{ .string = secret });
            _ = try upd.set("token", .{ .string = token });
            _ = try upd.set("encoding_aes_key", .{ .string = encoding_aes_key });
            _ = try upd.set("verified", .{ .bool = verified });
            _ = try upd.setFieldValue("updated_at", now);
            _ = try upd.Where(.{preds.account_idEQ(.{ .int = account_id })});
            _ = try upd.Save();
            return row.id;
        }
        var b = try self.client.account_wechat.Create();
        defer b.deinit();
        _ = try b.setFieldValue("tenant_id", tenant_id);
        _ = try b.setFieldValue("account_id", account_id);
        _ = try b.setFieldValue("appid", appid);
        _ = try b.setFieldValue("secret", secret);
        _ = try b.setFieldValue("token", token);
        _ = try b.setFieldValue("encoding_aes_key", encoding_aes_key);
        _ = try b.setFieldValue("verified", verified);
        _ = try b.setFieldValue("created_at", now);
        _ = try b.setFieldValue("updated_at", now);
        var row = try b.Save();
        defer zent.codegen.deinitEntity(infos, AccountWechatInfo, &row, self.allocator);
        return row.id;
    }

    /// Total account count (dashboard stats).
    pub fn countAll(self: *AccountStore) !i64 {
        var q = self.client.account.Query();
        defer q.deinit();
        return @intCast(try q.Count());
    }
};
