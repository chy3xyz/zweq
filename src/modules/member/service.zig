//! Member service — WeChat fans + 粉丝标签. No HTTP/SQL leakage.

const std = @import("std");
const zigmodu = @import("zigmodu");
const zwechat = @import("zwechat");
const persist = @import("persistence.zig");
const account_mod = @import("../account/service.zig");

pub const FanRow = persist.FanRow;
pub const FanListResult = persist.FanListResult;
pub const FanTagRow = persist.FanTagRow;

pub const MemberError = error{
    InvalidOpenid,
    InvalidName,
    NotFound,
    TagStoreUnavailable,
    TokenCacheUnavailable,
    WechatApiError,
    WriteFailed,
    OutOfMemory,
    Unexpected,
};

pub const MemberService = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    store: *persist.FanStore,
    /// 标签存储（main.zig 注入；null 时标签 API 不可用）。
    tag_store: ?*persist.TagStore = null,
    /// access_token 缓存（main.zig 注入）。
    token_cache: ?*zwechat.cache.Memory = null,
    /// 账号服务（main.zig 注入；读 appid/secret）。
    account_svc: ?*account_mod.AccountService = null,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, store: *persist.FanStore) MemberService {
        return .{ .allocator = allocator, .io = io, .store = store };
    }

    fn now(self: *MemberService) i64 {
        return zigmodu.time.wallClockSeconds(self.io);
    }

    /// Record a 关注 event (upsert fan). Returns the fan id.
    pub fn onSubscribe(self: *MemberService, tenant_id: i64, account_id: i64, openid: []const u8, unionid: []const u8) MemberError!i64 {
        if (openid.len == 0) return error.InvalidOpenid;
        return self.store.upsert(tenant_id, account_id, openid, unionid, "", "", true, self.now(), self.now()) catch error.Unexpected;
    }

    /// Record a 取关 event.
    pub fn onUnsubscribe(self: *MemberService, tenant_id: i64, account_id: i64, openid: []const u8) !void {
        if (openid.len == 0) return error.InvalidOpenid;
        const row_opt = self.store.getByOpenid(tenant_id, account_id, openid) catch return error.Unexpected;
        if (row_opt) |row| {
            defer row.free(self.allocator);
            const preds = self.store.client.fan.predicates;
            var upd = self.store.client.fan.Update();
            defer upd.deinit();
            _ = try upd.set("subscribed", .{ .bool = false });
            _ = try upd.setFieldValue("updated_at", self.now());
            _ = try upd.Where(.{preds.idEQ(.{ .int = row.id })});
            _ = try upd.Save();
            return;
        }
    }

    pub fn get(self: *MemberService, id: i64) MemberError!?FanRow {
        return self.store.getById(id) catch error.Unexpected;
    }

    pub fn list(self: *MemberService, page: usize, page_size: usize, tenant_id: i64, account_id: i64, keyword: ?[]const u8, subscribed_only: bool) MemberError!FanListResult {
        return self.store.list(page, page_size, tenant_id, account_id, keyword, subscribed_only) catch error.Unexpected;
    }

    // ── 粉丝标签（微信 tags API 自实现；zwechat user 模块无 tag CRUD）──

    fn getAccessToken(self: *MemberService, account_id: i64) MemberError![]u8 {
        const tc = self.token_cache orelse return error.TokenCacheUnavailable;
        const ac = self.account_svc orelse return error.TagStoreUnavailable;
        const cfg_opt = ac.getWechatConfig(account_id) catch return error.NotFound;
        const cfg = cfg_opt orelse return error.NotFound;
        defer cfg.deinit(self.allocator);
        var ak = zwechat.credential.DefaultAccessToken.init(cfg.appid, cfg.secret, "zweq", tc.asCache());
        return ak.getAccessToken(self.allocator) catch error.WechatApiError;
    }

    /// 微信建标签并存本地。返回 wx_tag_id。
    pub fn createWxTag(self: *MemberService, tenant_id: i64, account_id: i64, name: []const u8) MemberError!i64 {
        if (std.mem.trim(u8, name, " \t").len == 0) return error.InvalidName;
        const ts = self.tag_store orelse return error.TagStoreUnavailable;
        const token = try self.getAccessToken(account_id);
        defer self.allocator.free(token);

        const uri = try std.fmt.allocPrint(self.allocator, "{s}?access_token={s}", .{ "https://api.weixin.qq.com/cgi-bin/tags/create", token });
        defer self.allocator.free(uri);

        var out: std.Io.Writer.Allocating = .init(self.allocator);
        defer out.deinit();
        var s: std.json.Stringify = .{ .writer = &out.writer };
        try s.beginObject();
        try s.objectField("tag");
        try s.beginObject();
        try s.objectField("name");
        try s.write(name);
        try s.endObject();
        try s.endObject();
        const body = try out.toOwnedSlice();
        defer self.allocator.free(body);

        const client = zwechat.util.http.getDefaultClient(self.allocator);
        const resp = client.postJSON(uri, body) catch return error.WechatApiError;
        defer self.allocator.free(resp);

        var parsed = std.json.parseFromSlice(struct {
            errcode: i64 = 0,
            errmsg: []const u8 = "",
            tag: struct { id: i64 = 0, name: []const u8 = "" } = .{},
        }, self.allocator, resp, .{}) catch return error.WechatApiError;
        defer parsed.deinit();
        if (parsed.value.errcode != 0) return error.WechatApiError;
        const wx_id = parsed.value.tag.id;
        _ = ts.upsert(tenant_id, account_id, wx_id, parsed.value.tag.name, self.now()) catch return error.Unexpected;
        return wx_id;
    }

    /// 拉取微信全部标签并存本地，返回本地列表（caller free）。
    pub fn listWxTags(self: *MemberService, tenant_id: i64, account_id: i64) MemberError![]FanTagRow {
        const ts = self.tag_store orelse return error.TagStoreUnavailable;
        const token = try self.getAccessToken(account_id);
        defer self.allocator.free(token);

        const client = zwechat.util.http.getDefaultClient(self.allocator);
        const uri = try std.fmt.allocPrint(self.allocator, "{s}?access_token={s}", .{ "https://api.weixin.qq.com/cgi-bin/tags/get", token });
        defer self.allocator.free(uri);
        const resp = client.get(uri) catch return error.WechatApiError;
        defer self.allocator.free(resp);

        var parsed = std.json.parseFromSlice(struct {
            errcode: i64 = 0,
            errmsg: []const u8 = "",
            tags: []struct { id: i64 = 0, name: []const u8 = "" } = &.{},
        }, self.allocator, resp, .{}) catch return error.WechatApiError;
        defer parsed.deinit();
        if (parsed.value.errcode != 0) return error.WechatApiError;
        for (parsed.value.tags) |t| {
            _ = ts.upsert(tenant_id, account_id, t.id, t.name, self.now()) catch return error.Unexpected;
        }
        return ts.list(tenant_id, account_id) catch error.Unexpected;
    }

    /// 给粉丝打标签（微信 batchtagging）。
    pub fn tagFan(self: *MemberService, account_id: i64, openid: []const u8, wx_tag_id: i64) MemberError!void {
        if (openid.len == 0) return error.InvalidOpenid;
        const token = try self.getAccessToken(account_id);
        defer self.allocator.free(token);

        const uri = try std.fmt.allocPrint(self.allocator, "{s}?access_token={s}", .{ "https://api.weixin.qq.com/cgi-bin/tags/members/batchtagging", token });
        defer self.allocator.free(uri);

        var out: std.Io.Writer.Allocating = .init(self.allocator);
        defer out.deinit();
        var s: std.json.Stringify = .{ .writer = &out.writer };
        try s.beginObject();
        try s.objectField("openid_list");
        try s.beginArray();
        try s.write(openid);
        try s.endArray();
        try s.objectField("tagid");
        try s.write(wx_tag_id);
        try s.endObject();
        const body = try out.toOwnedSlice();
        defer self.allocator.free(body);

        const client = zwechat.util.http.getDefaultClient(self.allocator);
        const resp = client.postJSON(uri, body) catch return error.WechatApiError;
        defer self.allocator.free(resp);
        var parsed = std.json.parseFromSlice(struct { errcode: i64 = 0, errmsg: []const u8 = "" }, self.allocator, resp, .{}) catch return error.WechatApiError;
        defer parsed.deinit();
        if (parsed.value.errcode != 0) return error.WechatApiError;
    }
};
