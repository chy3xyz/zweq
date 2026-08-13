//! Menu service — 公众号自定义菜单 + access_token 管理。
//!
//! 菜单以按钮数组 JSON 存库（`WechatMenu.menu_json`）；`publish` 时把 JSON
//! 解析为 zwechat 的 `Button` 并调 `menu/setMenu` 发布，`deleteRemote` 调
//! `menu/deleteMenu`。access_token 复用 zwechat 的 `DefaultAccessToken`
//! （进程级 `cache.Memory` 缓存，`{prefix}_access_token_{appid}` key 天然按
//! 账号隔离，TTL = expires_in - 1500 提前刷新）。

const std = @import("std");
const zigmodu = @import("zigmodu");
const zwechat = @import("zwechat");
const persist = @import("persistence.zig");
const account_mod = @import("../account/service.zig");

pub const MenuRow = persist.MenuRow;

pub const MenuError = error{
    InvalidJson,
    AccountNotFound,
    MenuNotConfigured,
    WechatApiError,
    NotFound,
    Unexpected,
};

/// JSON 友好的按钮 DTO（字段名与微信 JSON 一致，`type` 用 @"type" 规避
/// Zig 关键字）。
const ButtonDto = struct {
    @"type": []const u8 = "",
    name: []const u8 = "",
    key: []const u8 = "",
    url: []const u8 = "",
    media_id: []const u8 = "",
    appid: []const u8 = "",
    pagepath: []const u8 = "",
    sub_button: []ButtonDto = &.{},
};

/// 递归把 DTO 转成 zwechat `Button`（`type` → `type_`；sub_button 递归）。
/// 所有字符串字段深拷贝，不依赖 DTO/parse 结果的生命周期。
fn toButton(allocator: std.mem.Allocator, dto: ButtonDto) !zwechat.officialaccount.menu.Button {
    const type_ = try allocator.dupe(u8, dto.@"type");
    errdefer allocator.free(type_);
    const name = try allocator.dupe(u8, dto.name);
    errdefer allocator.free(name);
    const key = try allocator.dupe(u8, dto.key);
    errdefer allocator.free(key);
    const url = try allocator.dupe(u8, dto.url);
    errdefer allocator.free(url);
    const media_id = try allocator.dupe(u8, dto.media_id);
    errdefer allocator.free(media_id);
    const appid = try allocator.dupe(u8, dto.appid);
    errdefer allocator.free(appid);
    const pagepath = try allocator.dupe(u8, dto.pagepath);
    errdefer allocator.free(pagepath);

    var b = zwechat.officialaccount.menu.Button{
        .type_ = type_,
        .name = name,
        .key = key,
        .url = url,
        .media_id = media_id,
        .appid = appid,
        .pagepath = pagepath,
        .sub_button = &.{},
    };
    if (dto.sub_button.len > 0) {
        const subs = try allocator.alloc(zwechat.officialaccount.menu.Button, dto.sub_button.len);
        for (dto.sub_button, 0..) |sb, i| {
            subs[i] = try toButton(allocator, sb);
        }
        b.sub_button = subs;
    }
    return b;
}

/// 解析按钮数组 JSON 为 zwechat `Button[]`（分配在传入的 allocator 上，
/// 通常是一个 arena，随 arena 整体释放）。
pub fn parseButtons(allocator: std.mem.Allocator, json: []const u8) MenuError![]zwechat.officialaccount.menu.Button {
    var parsed = std.json.parseFromSlice([]ButtonDto, allocator, json, .{}) catch return error.InvalidJson;
    defer parsed.deinit();
    const dtos = parsed.value;
    const buttons = allocator.alloc(zwechat.officialaccount.menu.Button, dtos.len) catch return error.Unexpected;
    for (dtos, 0..) |d, i| {
        buttons[i] = toButton(allocator, d) catch return error.Unexpected;
    }
    return buttons;
}

pub const MenuService = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    store: *persist.MenuStore,
    account_svc: *account_mod.AccountService,
    token_cache: *zwechat.cache.Memory,

    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        store: *persist.MenuStore,
        account_svc: *account_mod.AccountService,
        token_cache: *zwechat.cache.Memory,
    ) MenuService {
        return .{ .allocator = allocator, .io = io, .store = store, .account_svc = account_svc, .token_cache = token_cache };
    }

    fn now(self: *MenuService) i64 {
        return zigmodu.time.wallClockSeconds(self.io);
    }

    fn wechatConfig(self: *MenuService, account_id: i64) MenuError!account_mod.WechatConfig {
        const cfg_opt = self.account_svc.getWechatConfig(account_id) catch return error.AccountNotFound;
        return cfg_opt orelse error.AccountNotFound;
    }

    /// Save the menu JSON for an account (validated as a button-array JSON).
    pub fn save(self: *MenuService, tenant_id: i64, account_id: i64, menu_json: []const u8) MenuError!i64 {
        // 校验是合法 JSON（空数组也算合法）。
        const parsed = std.json.parseFromSlice([]ButtonDto, self.allocator, menu_json, .{}) catch return error.InvalidJson;
        parsed.deinit();
        return self.store.upsert(tenant_id, account_id, menu_json, self.now()) catch error.Unexpected;
    }

    pub fn get(self: *MenuService, tenant_id: i64, account_id: i64) MenuError!?MenuRow {
        return self.store.getByAccount(tenant_id, account_id) catch error.Unexpected;
    }

    /// Publish the saved menu to WeChat (`menu/create`).
    pub fn publish(self: *MenuService, tenant_id: i64, account_id: i64) MenuError!void {
        var cfg = try self.wechatConfig(account_id);
        defer cfg.deinit(self.allocator);

        const row_opt = self.store.getByAccount(tenant_id, account_id) catch return error.Unexpected;
        const row = row_opt orelse return error.MenuNotConfigured;
        defer row.free(self.allocator);

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const buttons = try parseButtons(arena.allocator(), row.menu_json);

        var ak = zwechat.credential.DefaultAccessToken.init(cfg.appid, cfg.secret, "zweq", self.token_cache.asCache());
        var ctx = zwechat.officialaccount.Context{
            .config = .{
                .app_id = cfg.appid,
                .app_secret = cfg.secret,
                .token = cfg.token,
                .encoding_aes_key = cfg.encoding_aes_key,
            },
            .access_token_handle = ak.asHandle(),
        };
        var menu = zwechat.officialaccount.menu.Menu.init(&ctx, self.allocator);
        menu.setMenu(buttons) catch return error.WechatApiError;
    }

    /// Delete the WeChat menu (`menu/delete`).
    pub fn deleteRemote(self: *MenuService, account_id: i64) MenuError!void {
        var cfg = try self.wechatConfig(account_id);
        defer cfg.deinit(self.allocator);

        var ak = zwechat.credential.DefaultAccessToken.init(cfg.appid, cfg.secret, "zweq", self.token_cache.asCache());
        var ctx = zwechat.officialaccount.Context{
            .config = .{
                .app_id = cfg.appid,
                .app_secret = cfg.secret,
                .token = cfg.token,
                .encoding_aes_key = cfg.encoding_aes_key,
            },
            .access_token_handle = ak.asHandle(),
        };
        var menu = zwechat.officialaccount.menu.Menu.init(&ctx, self.allocator);
        menu.deleteMenu() catch return error.WechatApiError;
    }

    /// 获取 access_token（复用 zwechat credential + 进程级缓存）。
    fn getAccessToken(self: *MenuService, account_id: i64) MenuError![]u8 {
        var cfg = try self.wechatConfig(account_id);
        defer cfg.deinit(self.allocator);
        var ak = zwechat.credential.DefaultAccessToken.init(cfg.appid, cfg.secret, "zweq", self.token_cache.asCache());
        return ak.getAccessToken(self.allocator) catch error.WechatApiError;
    }

    /// 从微信拉取当前菜单，**透传原始 JSON**（前端直接渲染）。
    /// 绕开 zwechat `getMenu` 的 `Button.type_` 反射丢失 bug（type 字段
    /// 无法从 JSON `"type"` 解析），返回 caller-owned 原始响应。
    pub fn fetchMenu(self: *MenuService, account_id: i64) MenuError![]u8 {
        const token = try self.getAccessToken(account_id);
        defer self.allocator.free(token);
        const uri = std.fmt.allocPrint(self.allocator, "{s}?access_token={s}", .{ "https://api.weixin.qq.com/cgi-bin/menu/get", token }) catch return error.Unexpected;
        defer self.allocator.free(uri);

        const client = zwechat.util.http.getDefaultClient(self.allocator);
        const resp = client.get(uri) catch return error.WechatApiError;
        defer self.allocator.free(resp);
        return self.allocator.dupe(u8, resp) catch error.Unexpected;
    }
};
