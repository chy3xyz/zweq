//! Account service — platform account CRUD + WeChat config. No HTTP/SQL leakage.

const std = @import("std");
const zigmodu = @import("zigmodu");
const persist = @import("persistence.zig");

pub const AccountRow = persist.AccountRow;
pub const AccountWechatRow = persist.AccountWechatRow;
pub const AccountListResult = persist.AccountListResult;

pub const AccountError = error{
    InvalidName,
    InvalidKind,
    InvalidStatus,
    NotFound,
    Unexpected,
};

/// WeEngine account kinds. Only `wechat`/`wxapp` get a WeChat config.
pub fn validKind(kind: []const u8) bool {
    return std.mem.eql(u8, kind, "wechat") or
        std.mem.eql(u8, kind, "wxapp") or
        std.mem.eql(u8, kind, "app");
}

pub fn validStatus(status: []const u8) bool {
    return std.mem.eql(u8, status, "active") or
        std.mem.eql(u8, status, "disabled");
}

pub const WechatConfig = struct {
    appid: []const u8,
    secret: []const u8,
    token: []const u8,
    encoding_aes_key: []const u8,
    verified: bool,

    pub fn deinit(self: WechatConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.appid);
        allocator.free(self.secret);
        allocator.free(self.token);
        allocator.free(self.encoding_aes_key);
    }
};

pub const AccountService = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    store: *persist.AccountStore,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, store: *persist.AccountStore) AccountService {
        return .{ .allocator = allocator, .io = io, .store = store };
    }

    fn now(self: *AccountService) i64 {
        return zigmodu.time.wallClockSeconds(self.io);
    }

    pub fn create(self: *AccountService, tenant_id: i64, name: []const u8, kind: []const u8) AccountError!i64 {
        if (std.mem.trim(u8, name, " \t").len == 0) return error.InvalidName;
        if (!validKind(kind)) return error.InvalidKind;
        return self.store.create(tenant_id, name, kind, "active", self.now()) catch error.Unexpected;
    }

    pub fn get(self: *AccountService, id: i64) AccountError!?AccountRow {
        return self.store.getById(id) catch error.Unexpected;
    }

    pub fn list(self: *AccountService, page: usize, page_size: usize, tenant_id: ?i64, kind: ?[]const u8) AccountError!AccountListResult {
        return self.store.list(page, page_size, tenant_id, kind) catch error.Unexpected;
    }

    pub fn update(self: *AccountService, id: i64, name: []const u8, kind: []const u8, status: []const u8) AccountError!bool {
        if (std.mem.trim(u8, name, " \t").len == 0) return error.InvalidName;
        if (!validKind(kind)) return error.InvalidKind;
        if (!validStatus(status)) return error.InvalidStatus;
        return self.store.update(id, name, kind, status, self.now()) catch error.Unexpected;
    }

    pub fn delete(self: *AccountService, id: i64) AccountError!void {
        self.store.delete(id) catch return error.Unexpected;
    }

    pub fn getWechat(self: *AccountService, account_id: i64) AccountError!?AccountWechatRow {
        return self.store.getWechatByAccount(account_id) catch error.Unexpected;
    }

    /// Server callback lookup by verify token.
    pub fn findByToken(self: *AccountService, token: []const u8) AccountError!?AccountWechatRow {
        return self.store.getWechatByToken(token) catch error.Unexpected;
    }

    /// Read full config including sensitive fields (for the WeChat server
    /// callback / SDK). Caller frees via `WechatConfig.deinit`.
    pub fn getWechatConfig(self: *AccountService, account_id: i64) !?WechatConfig {
        const secrets_opt = self.store.getWechatSecretsByAccount(account_id) catch return error.Unexpected;
        const secrets = secrets_opt orelse return null;
        defer self.allocator.free(secrets.secret);
        defer self.allocator.free(secrets.encoding_aes_key);
        const row_opt = self.getWechat(account_id) catch return null;
        const row = row_opt orelse return null;
        defer row.free(self.allocator);
        const appid = try self.allocator.dupe(u8, row.appid);
        errdefer self.allocator.free(appid);
        const token = try self.allocator.dupe(u8, row.token);
        errdefer self.allocator.free(token);
        const secret = try self.allocator.dupe(u8, secrets.secret);
        errdefer self.allocator.free(secret);
        const key = try self.allocator.dupe(u8, secrets.encoding_aes_key);
        errdefer self.allocator.free(key);
        return .{
            .appid = appid,
            .secret = secret,
            .token = token,
            .encoding_aes_key = key,
            .verified = row.verified,
        };
    }

    pub fn upsertWechat(self: *AccountService, tenant_id: i64, account_id: i64, cfg: WechatConfig) AccountError!i64 {
        return self.store.upsertWechat(tenant_id, account_id, cfg.appid, cfg.secret, cfg.token, cfg.encoding_aes_key, cfg.verified, self.now()) catch error.Unexpected;
    }
};
