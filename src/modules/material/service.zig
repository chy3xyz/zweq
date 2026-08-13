//! Material service — 素材库（图文 news + 图片/语音/视频 file）。No HTTP/SQL leakage.

const std = @import("std");
const zigmodu = @import("zigmodu");
const zwechat = @import("zwechat");
const persist = @import("persistence.zig");
const account_mod = @import("../account/service.zig");

pub const MaterialNewsRow = persist.MaterialNewsRow;
pub const MaterialNewsListResult = persist.MaterialNewsListResult;
pub const MaterialFileRow = persist.MaterialFileRow;
pub const MaterialFileListResult = persist.MaterialFileListResult;

/// 微信 batchget_material 返回的 JSON 结构（zwechat 未导出 material 模块，
pub const MaterialError = error{
    InvalidTitle,
    InvalidKind,
    NotFound,
    WechatApiError,
    OutOfMemory,
    WriteFailed,
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
    account_svc: *account_mod.AccountService,
    token_cache: *zwechat.cache.Memory,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, store: *persist.MaterialStore, account_svc: *account_mod.AccountService, token_cache: *zwechat.cache.Memory) MaterialService {
        return .{ .allocator = allocator, .io = io, .store = store, .account_svc = account_svc, .token_cache = token_cache };
    }

    fn now(self: *MaterialService) i64 {
        return zigmodu.time.wallClockSeconds(self.io);
    }

    fn wechatConfig(self: *MaterialService, account_id: i64) MaterialError!account_mod.WechatConfig {
        const cfg_opt = self.account_svc.getWechatConfig(account_id) catch return error.NotFound;
        return cfg_opt orelse error.NotFound;
    }

    /// 拉取微信永久素材列表并落库。复用 zwechat material（v0.4.2 已修复
    /// 编译 bug 且导出子模块；batchGetMaterial 返回 std.json.Parsed，UAF 已修）。
    fn syncMaterialList(self: *MaterialService, tenant_id: i64, account_id: i64, mtype: zwechat.officialaccount.material.PermanentMaterialType) MaterialError!void {
        const cfg_opt = self.account_svc.getWechatConfig(account_id) catch return error.NotFound;
        const cfg = cfg_opt orelse return error.NotFound;
        defer cfg.deinit(self.allocator);

        var ak = zwechat.credential.DefaultAccessToken.init(cfg.appid, cfg.secret, "zweq", self.token_cache.asCache());
        var ctx = zwechat.officialaccount.Context{
            .config = .{ .app_id = cfg.appid, .app_secret = cfg.secret, .token = cfg.token, .encoding_aes_key = cfg.encoding_aes_key },
            .access_token_handle = ak.asHandle(),
        };
        var mat = zwechat.officialaccount.material.Material.init(&ctx, self.allocator);

        var parsed = mat.batchGetMaterial(mtype, 0, 20) catch return error.WechatApiError;
        defer parsed.deinit();
        const list = parsed.value;
        if (list.errcode != 0) return error.WechatApiError;
        const mtype_str = @tagName(mtype);
        for (list.item) |it| {
            if (mtype == .news) {
                if (it.content.news_item.len == 0) continue;
                const art = it.content.news_item[0];
                _ = self.store.upsertNews(tenant_id, account_id, it.media_id, art.title, art.author, art.digest, art.content, art.thumb_media_id, "", art.url, self.now()) catch return error.Unexpected;
            } else {
                _ = self.store.upsertFile(tenant_id, account_id, mtype_str, it.media_id, it.url, self.now()) catch return error.Unexpected;
            }
        }
    }

    /// 同步微信图文素材到本地。
    pub fn syncNews(self: *MaterialService, tenant_id: i64, account_id: i64) MaterialError!void {
        return self.syncMaterialList(tenant_id, account_id, .news);
    }

    /// 同步微信图片/语音/视频素材到本地。
    pub fn syncFiles(self: *MaterialService, tenant_id: i64, account_id: i64, kind: []const u8) MaterialError!void {
        if (!validKind(kind)) return error.InvalidKind;
        const mt: zwechat.officialaccount.material.PermanentMaterialType = if (std.mem.eql(u8, kind, "image")) .image else if (std.mem.eql(u8, kind, "voice")) .voice else .video;
        return self.syncMaterialList(tenant_id, account_id, mt);
    }

    /// 拉取素材总数。复用 zwechat material.getMaterialCount（返回 Parsed）。
    pub fn syncCount(self: *MaterialService, account_id: i64) MaterialError!struct { voice: i64, video: i64, image: i64, news: i64 } {
        const cfg_opt = self.account_svc.getWechatConfig(account_id) catch return error.NotFound;
        const cfg = cfg_opt orelse return error.NotFound;
        defer cfg.deinit(self.allocator);

        var ak = zwechat.credential.DefaultAccessToken.init(cfg.appid, cfg.secret, "zweq", self.token_cache.asCache());
        var ctx = zwechat.officialaccount.Context{
            .config = .{ .app_id = cfg.appid, .app_secret = cfg.secret, .token = cfg.token, .encoding_aes_key = cfg.encoding_aes_key },
            .access_token_handle = ak.asHandle(),
        };
        var mat = zwechat.officialaccount.material.Material.init(&ctx, self.allocator);

        var parsed = mat.getMaterialCount() catch return error.WechatApiError;
        defer parsed.deinit();
        const c = parsed.value;
        if (c.errcode != 0) return error.WechatApiError;
        return .{ .voice = c.voice_count, .video = c.video_count, .image = c.image_count, .news = c.news_count };
    }

    /// 上传图文素材到微信（material/add_news）。返回微信 media_id（caller
    /// free），并按 media_id upsert 到本地 MaterialNews。JSON 用 Stringify
    /// 构造（content 含转义安全）。
    /// 上传图文素材到微信（复用 zwechat material.addNews，返回 dupe media_id）。
    /// 并按 media_id upsert 到本地 MaterialNews。
    pub fn uploadNews(self: *MaterialService, tenant_id: i64, account_id: i64, title: []const u8, author: []const u8, digest: []const u8, content: []const u8, thumb_media_id: []const u8, content_source_url: []const u8) MaterialError![]u8 {
        const cfg_opt = self.account_svc.getWechatConfig(account_id) catch return error.NotFound;
        const cfg = cfg_opt orelse return error.NotFound;
        defer cfg.deinit(self.allocator);

        var ak = zwechat.credential.DefaultAccessToken.init(cfg.appid, cfg.secret, "zweq", self.token_cache.asCache());
        var ctx = zwechat.officialaccount.Context{
            .config = .{ .app_id = cfg.appid, .app_secret = cfg.secret, .token = cfg.token, .encoding_aes_key = cfg.encoding_aes_key },
            .access_token_handle = ak.asHandle(),
        };
        var mat = zwechat.officialaccount.material.Material.init(&ctx, self.allocator);

        const articles = [_]zwechat.officialaccount.material.Article{.{
            .title = title,
            .thumb_media_id = thumb_media_id,
            .author = author,
            .digest = digest,
            .content = content,
            .content_source_url = content_source_url,
        }};
        const media_id = mat.addNews(&articles) catch return error.WechatApiError;
        defer self.allocator.free(@constCast(media_id));

        _ = self.store.upsertNews(tenant_id, account_id, media_id, title, author, digest, content, thumb_media_id, "", content_source_url, self.now()) catch return error.Unexpected;
        return self.allocator.dupe(u8, media_id) catch error.OutOfMemory;
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
