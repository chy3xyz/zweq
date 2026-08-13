//! WechatService — 公众号服务器回调引擎。
//!
//! Receives WeChat push at `/wx/{token}`, verifies the signature, parses
//! plain or AES-encrypted XML, syncs fans, dispatches text messages through
//! the keyword rule engine, and builds passive replies (text/news, plain or
//! encrypted). Built directly on `zwechat.util` primitives for full control
//! over event handling (zwechat's `server.serve` only parses text).

const std = @import("std");
const zigmodu = @import("zigmodu");
const zwechat = @import("zwechat");
const persist = @import("persistence.zig");
const account_mod = @import("../account/service.zig");
const rule_mod = @import("../rule/service.zig");
const member_mod = @import("../member/service.zig");
const setting_store_mod = @import("../setting/persistence.zig");
const ai_mod = @import("../ai/service.zig");
const module_mod = @import("../module/service.zig");
const cache_svc = @import("../../services/cache.zig");

pub const MessageLogRow = persist.MessageLogRow;

/// WeChat server callback query parameters.
pub const CallbackQuery = struct {
    signature: []const u8 = "",
    timestamp: []const u8 = "",
    nonce: []const u8 = "",
    echostr: []const u8 = "",
    msg_signature: []const u8 = "",
    encrypt_type: []const u8 = "",
};

const ParsedMsg = struct {
    doc: zwechat.util.xml.XmlDoc,
    openid: []const u8,
    to_user: []const u8,
    msg_type: []const u8,
    content: []const u8,
    event: []const u8,
    event_key: []const u8,
    msg_id: []const u8,

    fn deinit(self: *ParsedMsg) void {
        self.doc.deinit();
    }
};

/// A message handed to a bound module's receiver, free of any zwechat XML
/// types so third-party modules never depend on the WeChat SDK directly.
pub const IncomingMessage = struct {
    tenant_id: i64,
    account_id: i64,
    openid: []const u8,
    to_user: []const u8,
    msg_type: []const u8,
    content: []const u8,
    event: []const u8,
    event_key: []const u8,
};

/// A passive reply produced by a module receiver. All fields are owned by the
/// allocator passed to the receiver; `deinit` frees them. Use `text`/`news`
/// constructors rather than building the struct by hand.
pub const Reply = struct {
    reply_type: []const u8, // "text" | "news"
    content: []const u8,
    news_title: []const u8,
    news_description: []const u8,
    news_pic_url: []const u8,
    news_url: []const u8,

    pub fn deinit(self: *Reply, allocator: std.mem.Allocator) void {
        allocator.free(self.content);
        allocator.free(self.news_title);
        allocator.free(self.news_description);
        allocator.free(self.news_pic_url);
        allocator.free(self.news_url);
    }

    /// Caller-owned text reply.
    pub fn text(allocator: std.mem.Allocator, content: []const u8) !Reply {
        var r = Reply{
            .reply_type = "text",
            .content = "",
            .news_title = "",
            .news_description = "",
            .news_pic_url = "",
            .news_url = "",
        };
        errdefer r.deinit(allocator);
        r.content = try allocator.dupe(u8, content);
        r.news_title = try allocator.dupe(u8, "");
        r.news_description = try allocator.dupe(u8, "");
        r.news_pic_url = try allocator.dupe(u8, "");
        r.news_url = try allocator.dupe(u8, "");
        return r;
    }

    /// Caller-owned news reply.
    pub fn news(allocator: std.mem.Allocator, title: []const u8, description: []const u8, pic_url: []const u8, url: []const u8) !Reply {
        var r = Reply{
            .reply_type = "news",
            .content = "",
            .news_title = "",
            .news_description = "",
            .news_pic_url = "",
            .news_url = "",
        };
        errdefer r.deinit(allocator);
        r.content = try allocator.dupe(u8, "");
        r.news_title = try allocator.dupe(u8, title);
        r.news_description = try allocator.dupe(u8, description);
        r.news_pic_url = try allocator.dupe(u8, pic_url);
        r.news_url = try allocator.dupe(u8, url);
        return r;
    }
};

/// A module receiver — the extension point that lets a bound module handle an
/// incoming WeChat message. `module_name` must equal the `module_binding.module`
/// value. `handle` returns a caller-owned `Reply`, or null to decline so the
/// dispatch continues to the next receiver / AI / default reply.
pub const Receiver = struct {
    module_name: []const u8,
    ctx: ?*anyopaque,
    handle: *const fn (ctx: ?*anyopaque, allocator: std.mem.Allocator, msg: IncomingMessage) anyerror!?Reply,
};

/// 模板消息的 data 项（key/value/color），对应微信模板消息的 data 字段。
pub const TemplateDataItem = struct {
    key: []const u8,
    value: []const u8,
    color: []const u8 = "",
};

/// Admin view of the callback log.
pub const MessageLogListResult = persist.MessageLogListResult;

pub const WechatService = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    account_svc: *account_mod.AccountService,
    rule_svc: *rule_mod.RuleService,
    member_svc: *member_mod.MemberService,
    setting_store: *setting_store_mod.SettingStore,
    store: *persist.MessageStore,
    /// Optional AI assistant — set by main.zig after AiService is created.
    /// Used for AI auto-reply when a provider is configured.
    ai_svc: ?*ai_mod.AiService = null,
    /// Optional module registry — set by main.zig after ModuleService is
    /// created. Used to resolve which receivers are bound to an account.
    module_svc: ?*module_mod.ModuleService = null,
    /// Registered module receivers (compile-time set, populated via
    /// `registerReceiver`). Fixed capacity keeps the struct value-sized.
    receivers: [32]Receiver = undefined,
    receiver_count: usize = 0,
    /// Optional cache — set by main.zig for nonce replay detection. When
    /// null, nonce dedup is skipped (timestamp guard still applies).
    cache: ?*cache_svc.CacheService = null,
    /// Optional access_token cache — set by main.zig for主动客服消息等
    /// 需要 access_token 的能力（复用 zwechat credential）。
    token_cache: ?*zwechat.cache.Memory = null,

    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        account_svc: *account_mod.AccountService,
        rule_svc: *rule_mod.RuleService,
        member_svc: *member_mod.MemberService,
        setting_store: *setting_store_mod.SettingStore,
        store: *persist.MessageStore,
    ) WechatService {
        return .{
            .allocator = allocator,
            .io = io,
            .account_svc = account_svc,
            .rule_svc = rule_svc,
            .member_svc = member_svc,
            .setting_store = setting_store,
            .store = store,
        };
    }

    fn now(self: *WechatService) i64 {
        return zigmodu.time.wallClockSeconds(self.io);
    }

    /// Register a module receiver. Call once per receiver at startup (before
    /// serving traffic). Returns `error.TooManyReceivers` past the fixed cap.
    pub fn registerReceiver(self: *WechatService, r: Receiver) !void {
        if (self.receiver_count >= self.receivers.len) return error.TooManyReceivers;
        self.receivers[self.receiver_count] = r;
        self.receiver_count += 1;
    }

    /// Main entry: validate, parse, dispatch, reply. Returns the response
    /// body to write back to WeChat (caller frees).
    pub fn handleCallback(self: *WechatService, allocator: std.mem.Allocator, token: []const u8, q: CallbackQuery, body: []const u8) ![]u8 {
        // 1. Resolve the account by its verify token.
        const wrow_opt = self.account_svc.findByToken(token) catch return error.AccountNotFound;
        const wrow = wrow_opt orelse return error.AccountNotFound;
        defer wrow.free(self.allocator);
        const account_id = wrow.account_id;
        const tenant_id = wrow.tenant_id;

        const cfg_opt = self.account_svc.getWechatConfig(account_id) catch return error.AccountNotFound;
        const cfg = cfg_opt orelse return error.AccountNotFound;
        defer cfg.deinit(self.allocator);

        const encrypted = std.mem.eql(u8, q.encrypt_type, "aes");

        // 2. Base signature over (token, timestamp, nonce).
        const computed = try zwechat.util.signature.signature(allocator, &[_][]const u8{ cfg.token, q.timestamp, q.nonce });
        defer allocator.free(computed);
        if (!std.mem.eql(u8, computed, q.signature)) return error.SignatureMismatch;

        // Replay guard: timestamp must be within ±5 minutes (WeChat best
        // practice to stop replay of captured callbacks).
        const ts = std.fmt.parseInt(i64, q.timestamp, 10) catch return error.TimestampExpired;
        const now_ts = self.now();
        const delta: i64 = if (ts > now_ts) ts - now_ts else now_ts - ts;
        if (delta > 300) return error.TimestampExpired;

        // Nonce dedup: reject a repeated nonce within the cache TTL window
        // (best effort — skipped when no cache is injected).
        if (self.cache) |c| {
            var key_buf: [160]u8 = undefined;
            const key = std.fmt.bufPrint(&key_buf, "wxnonce:{d}:{s}", .{ account_id, q.nonce }) catch "";
            if (key.len > 0 and c.get(key) != null) return error.ReplayDetected;
            c.set(key, "1") catch {};
        }

        // 3. URL handshake (GET with echostr).
        if (q.echostr.len > 0) return allocator.dupe(u8, q.echostr);

        // 4. Parse the message XML.
        var parsed = try parseMessage(allocator, &cfg, q, body, encrypted);
        defer parsed.deinit();

        // 5. Events (subscribe/unsubscribe/…) → fan sync + follow reply.
        if (std.mem.eql(u8, parsed.msg_type, "event")) {
            if (std.mem.eql(u8, parsed.event, "subscribe")) {
                _ = try self.member_svc.onSubscribe(tenant_id, account_id, parsed.openid, "");
                const follow_opt = self.getSetting(allocator, tenant_id, "wechat_follow_reply");
                if (follow_opt) |follow| {
                    defer allocator.free(follow);
                    if (follow.len == 0) {
                        try self.log(tenant_id, account_id, &parsed, "subscribe", "");
                        return allocator.dupe(u8, "success");
                    }
                    const xml = try self.buildTextXml(allocator, parsed.openid, parsed.to_user, follow);
                    errdefer allocator.free(xml);
                    try self.log(tenant_id, account_id, &parsed, "text", follow);
                    if (encrypted) return self.encryptReplyXml(allocator, &cfg, q, xml);
                    return xml;
                }
                try self.log(tenant_id, account_id, &parsed, "subscribe", "");
                return allocator.dupe(u8, "success");
            }
            if (std.mem.eql(u8, parsed.event, "unsubscribe")) {
                try self.member_svc.onUnsubscribe(tenant_id, account_id, parsed.openid);
                try self.log(tenant_id, account_id, &parsed, "", "");
                return allocator.dupe(u8, "success");
            }
            // 其他事件（菜单点击 CLICK、view、扫码等）→ 模块接收器分发。
            if (try self.dispatchAndReply(allocator, tenant_id, account_id, &parsed, encrypted, &cfg, q)) |xml| return xml;
            try self.log(tenant_id, account_id, &parsed, "", "");
            return allocator.dupe(u8, "success");
        }

        // 6. Any non-event message implies the user is a fan.
        if (parsed.openid.len > 0) {
            _ = try self.member_svc.onSubscribe(tenant_id, account_id, parsed.openid, "");
        }

        // 7. Text → keyword rule engine.
        if (std.mem.eql(u8, parsed.msg_type, "text")) {
            const reply_opt = try self.rule_svc.match(allocator, tenant_id, account_id, parsed.content);
            if (reply_opt) |reply_row| {
                defer reply_row.free(allocator);
                const is_news = std.mem.eql(u8, reply_row.reply_type, "news");
                const xml = if (is_news)
                    try self.buildNewsXml(allocator, parsed.openid, parsed.to_user, reply_row)
                else
                    try self.buildTextXml(allocator, parsed.openid, parsed.to_user, reply_row.content);
                errdefer allocator.free(xml);
                const reply_content = if (is_news) reply_row.news_title else reply_row.content;
                try self.log(tenant_id, account_id, &parsed, reply_row.reply_type, reply_content);
                if (encrypted) return self.encryptReplyXml(allocator, &cfg, q, xml);
                return xml;
            }
            // Module receivers: no keyword match → ask account-bound modules
            // (场景应用), in binding order; first non-null reply wins.
            if (try self.dispatchAndReply(allocator, tenant_id, account_id, &parsed, encrypted, &cfg, q)) |xml| return xml;
            // AI auto-reply: no keyword match, AI enabled + provider configured.
            const ai_flag = self.getSetting(allocator, tenant_id, "wechat_ai_auto_reply");
            if (ai_flag) |flag| {
                defer allocator.free(flag);
                if (std.mem.eql(u8, flag, "1")) {
                    if (try self.tryAiReply(allocator, tenant_id, &parsed)) |answer| {
                        defer allocator.free(answer);
                        const xml = try self.buildTextXml(allocator, parsed.openid, parsed.to_user, answer);
                        errdefer allocator.free(xml);
                        try self.log(tenant_id, account_id, &parsed, "text", answer);
                        if (encrypted) return self.encryptReplyXml(allocator, &cfg, q, xml);
                        return xml;
                    }
                }
            }

            const def_opt = self.getSetting(allocator, tenant_id, "wechat_default_reply");
            if (def_opt) |def| {
                defer allocator.free(def);
                if (def.len > 0) {
                    const xml = try self.buildTextXml(allocator, parsed.openid, parsed.to_user, def);
                    errdefer allocator.free(xml);
                    try self.log(tenant_id, account_id, &parsed, "text", def);
                    if (encrypted) return self.encryptReplyXml(allocator, &cfg, q, xml);
                    return xml;
                }
            }
        }

        // 8. No reply → "success".
        try self.log(tenant_id, account_id, &parsed, "", "");
        return allocator.dupe(u8, "success");
    }

    // ── parsing ───────────────────────────────────────────────────

    fn parseMessage(allocator: std.mem.Allocator, cfg: *const account_mod.WechatConfig, q: CallbackQuery, body: []const u8, encrypted: bool) !ParsedMsg {
        if (encrypted) {
            const comp = try zwechat.util.signature.signature(allocator, &[_][]const u8{ cfg.token, q.timestamp, q.nonce, body });
            defer allocator.free(comp);
            if (!std.mem.eql(u8, comp, q.msg_signature)) return error.SignatureMismatch;

            var outer = try zwechat.util.xml.parse(allocator, body);
            defer outer.deinit();
            const enc_b64 = outer.get("Encrypt") orelse return error.MissingEncrypt;
            const dec = try zwechat.util.crypto.aesDecryptMsg(allocator, enc_b64, cfg.encoding_aes_key);
            defer allocator.free(dec.random);
            defer allocator.free(dec.raw_xml_msg);
            defer allocator.free(dec.app_id);
            if (!std.mem.eql(u8, dec.app_id, cfg.appid)) return error.AppIDMismatch;

            const inner = try zwechat.util.xml.parse(allocator, dec.raw_xml_msg);
            return makeParsed(inner);
        }
        const doc = try zwechat.util.xml.parse(allocator, body);
        return makeParsed(doc);
    }

    // ── reply builders ────────────────────────────────────────────

    fn buildTextXml(self: *WechatService, allocator: std.mem.Allocator, to: []const u8, from: []const u8, content: []const u8) ![]u8 {
        const ts_str = try std.fmt.allocPrint(allocator, "{d}", .{self.now()});
        defer allocator.free(ts_str);
        const elements = [_]zwechat.util.xml.XmlElement{
            .{ .key = "ToUserName", .value = to },
            .{ .key = "FromUserName", .value = from },
            .{ .key = "CreateTime", .value = ts_str },
            .{ .key = "MsgType", .value = "text" },
            .{ .key = "Content", .value = content },
        };
        return zwechat.util.xml.serialize(allocator, "xml", &elements);
    }

    fn buildNewsXml(self: *WechatService, allocator: std.mem.Allocator, to: []const u8, from: []const u8, r: rule_mod.RuleReplyRow) ![]u8 {
        return self.buildNewsXmlParts(allocator, to, from, r.news_title, r.news_description, r.news_pic_url, r.news_url);
    }

    /// Build a news reply from parts (shared by rule replies and module
    /// receiver replies).
    fn buildNewsXmlParts(self: *WechatService, allocator: std.mem.Allocator, to: []const u8, from: []const u8, title: []const u8, description: []const u8, pic_url: []const u8, url: []const u8) ![]u8 {
        const ts_str = try std.fmt.allocPrint(allocator, "{d}", .{self.now()});
        defer allocator.free(ts_str);
        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(allocator);
        try buf.print(allocator, "<xml><ToUserName><![CDATA[{s}]]></ToUserName>", .{to});
        try buf.print(allocator, "<FromUserName><![CDATA[{s}]]></FromUserName>", .{from});
        try buf.print(allocator, "<CreateTime>{s}</CreateTime>", .{ts_str});
        try buf.appendSlice(allocator, "<MsgType><![CDATA[news]]></MsgType><ArticleCount>1</ArticleCount><Articles>");
        try buf.print(allocator, "<item><Title><![CDATA[{s}]]></Title><Description><![CDATA[{s}]]></Description>", .{ title, description });
        try buf.print(allocator, "<PicUrl><![CDATA[{s}]]></PicUrl><Url><![CDATA[{s}]]></Url></item>", .{ pic_url, url });
        try buf.appendSlice(allocator, "</Articles></xml>");
        return buf.toOwnedSlice(allocator);
    }

    /// Wrap a reply XML into the AES-encrypted envelope for 安全模式.
    fn encryptReplyXml(self: *WechatService, allocator: std.mem.Allocator, cfg: *const account_mod.WechatConfig, q: CallbackQuery, reply_xml: []const u8) ![]u8 {
        var random: [16]u8 = undefined;
        {
            var file = try std.Io.Dir.cwd().openFile(self.io, "/dev/urandom", .{});
            errdefer file.close(self.io);
            const read = try file.readPositionalAll(self.io, &random, 0);
            if (read != random.len) return error.Unexpected;
        }
        const cipher = try zwechat.util.crypto.aesEncryptMsg(allocator, &random, reply_xml, cfg.appid, cfg.encoding_aes_key);
        defer allocator.free(cipher);
        const Enc = std.base64.standard.Encoder;
        const b64_buf = try allocator.alloc(u8, Enc.calcSize(cipher.len));
        defer allocator.free(b64_buf);
        const cipher_b64 = Enc.encode(b64_buf, cipher);
        const sig = try zwechat.util.signature.signature(allocator, &[_][]const u8{ cfg.token, q.timestamp, q.nonce, cipher_b64 });
        defer allocator.free(sig);
        const elements = [_]zwechat.util.xml.XmlElement{
            .{ .key = "Encrypt", .value = cipher_b64 },
            .{ .key = "MsgSignature", .value = sig },
            .{ .key = "TimeStamp", .value = q.timestamp },
            .{ .key = "Nonce", .value = q.nonce },
        };
        return zwechat.util.xml.serialize(allocator, "xml", &elements);
    }

    // ── helpers ───────────────────────────────────────────────────

    /// One-shot LLM auto-reply for a WeChat text message. Returns a
    /// caller-owned answer, or null when no provider/quota/network path works
    /// (caller falls back to the default reply / "success").
    fn tryAiReply(self: *WechatService, allocator: std.mem.Allocator, tenant_id: i64, parsed: *const ParsedMsg) !?[]const u8 {
        const ai = self.ai_svc orelse return null;
        var buf: [512]u8 = undefined;
        const content = if (parsed.content.len > 200) parsed.content[0..200] else parsed.content;
        const prompt = std.fmt.bufPrint(&buf, "你是公众号智能客服。请用中文简洁回复用户，不超过200字。用户说：{s}", .{content}) catch return null;
        // user_id 0 = no platform user → no skill permissions → plain completion.
        const outcome = ai.chat(allocator, 0, 0, tenant_id, prompt) catch return null;
        defer allocator.free(outcome.answer);
        if (outcome.answer.len == 0 or std.mem.eql(u8, outcome.answer, "success")) return null;
        const answer = if (outcome.answer.len > 1000) outcome.answer[0..1000] else outcome.answer;
        const dup = allocator.dupe(u8, answer) catch return null;
        return dup;
    }

    fn getSetting(self: *WechatService, allocator: std.mem.Allocator, tenant_id: i64, key: []const u8) ?[]const u8 {
        const row_opt = self.setting_store.get(tenant_id, key) catch return null;
        const row = row_opt orelse return null;
        defer row.free(self.setting_store.allocator);
        return allocator.dupe(u8, row.value) catch null;
    }

    fn log(self: *WechatService, tenant_id: i64, account_id: i64, parsed: *const ParsedMsg, reply_type: []const u8, reply_content: []const u8) !void {
        _ = self.store.create(tenant_id, account_id, parsed.msg_id, parsed.openid, parsed.msg_type, parsed.event, parsed.content, reply_type, reply_content, self.now()) catch {};
    }

    /// Walk the account's active module bindings and ask each bound module's
    /// receiver (if registered) to handle the message. Returns the first
    /// caller-owned reply, or null when no receiver handles it (fall through
    /// to AI / default reply).
    fn dispatchReceivers(self: *WechatService, allocator: std.mem.Allocator, tenant_id: i64, account_id: i64, parsed: *const ParsedMsg) !?Reply {
        const msvc = self.module_svc orelse return null;
        if (self.receiver_count == 0) return null;
        const bindings = msvc.accountModules(tenant_id, account_id) catch return null;
        defer {
            for (bindings) |b| b.free(allocator);
            allocator.free(bindings);
        }
        const msg = IncomingMessage{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .openid = parsed.openid,
            .to_user = parsed.to_user,
            .msg_type = parsed.msg_type,
            .content = parsed.content,
            .event = parsed.event,
            .event_key = parsed.event_key,
        };
        for (bindings) |b| {
            if (!std.mem.eql(u8, b.status, "active")) continue;
            for (self.receivers[0..self.receiver_count]) |r| {
                if (!std.mem.eql(u8, r.module_name, b.module)) continue;
                if (r.handle(r.ctx, allocator, msg) catch null) |reply| return reply;
            }
        }
        return null;
    }

    /// 调模块接收器分发并构建回复 XML；无接收器响应时返回 null。
    /// text 与 event（菜单点击等）分支共用。
    fn dispatchAndReply(self: *WechatService, allocator: std.mem.Allocator, tenant_id: i64, account_id: i64, parsed: *const ParsedMsg, encrypted: bool, cfg: *const account_mod.WechatConfig, q: CallbackQuery) !?[]u8 {
        const recv_reply = try self.dispatchReceivers(allocator, tenant_id, account_id, parsed);
        if (recv_reply) |recv| {
            var reply = recv;
            defer reply.deinit(allocator);
            const is_news = std.mem.eql(u8, reply.reply_type, "news");
            const xml = if (is_news)
                try self.buildNewsXmlParts(allocator, parsed.openid, parsed.to_user, reply.news_title, reply.news_description, reply.news_pic_url, reply.news_url)
            else
                try self.buildTextXml(allocator, parsed.openid, parsed.to_user, reply.content);
            errdefer allocator.free(xml);
            const reply_content = if (is_news) reply.news_title else reply.content;
            try self.log(tenant_id, account_id, parsed, reply.reply_type, reply_content);
            if (encrypted) return try self.encryptReplyXml(allocator, cfg, q, xml);
            return xml;
        }
        return null;
    }

    /// 获取 access_token（复用 zwechat credential + 进程级缓存）。
    fn getAccessToken(self: *WechatService, account_id: i64) ![]u8 {
        const tc = self.token_cache orelse return error.TokenCacheUnavailable;
        const cfg_opt = self.account_svc.getWechatConfig(account_id) catch return error.AccountNotFound;
        const cfg = cfg_opt orelse return error.AccountNotFound;
        defer cfg.deinit(self.allocator);
        var ak = zwechat.credential.DefaultAccessToken.init(cfg.appid, cfg.secret, "zweq", tc.asCache());
        return ak.getAccessToken(self.allocator) catch error.WechatApiError;
    }

    /// 群发文本消息（按粉丝标签；tag_id <= 0 表示全部粉丝）。
    /// 微信 `message/mass/sendall`；返回 msg_id。**自实现**（zwechat
    /// broadcast.sendToTag 硬编码 is_to_all:false 且 content 不做 JSON 转义，
    /// 含引号内容会破坏请求——自实现用 Stringify 安全处理）。
    pub fn sendBroadcastText(self: *WechatService, account_id: i64, tag_id: i64, content: []const u8) !i64 {
        const token = try self.getAccessToken(account_id);
        defer self.allocator.free(token);

        const uri = try std.fmt.allocPrint(self.allocator, "{s}?access_token={s}", .{ "https://api.weixin.qq.com/cgi-bin/message/mass/sendall", token });
        defer self.allocator.free(uri);

        var out: std.Io.Writer.Allocating = .init(self.allocator);
        defer out.deinit();
        var s: std.json.Stringify = .{ .writer = &out.writer };
        try s.beginObject();
        try s.objectField("filter");
        try s.beginObject();
        try s.objectField("is_to_all");
        try s.write(@intFromBool(tag_id <= 0));
        try s.objectField("tag_id");
        try s.write(@max(tag_id, 0));
        try s.endObject();
        try s.objectField("msgtype");
        try s.write("text");
        try s.objectField("text");
        try s.beginObject();
        try s.objectField("content");
        try s.write(content);
        try s.endObject();
        try s.endObject();
        const body = try out.toOwnedSlice();
        defer self.allocator.free(body);

        const client = zwechat.util.http.getDefaultClient(self.allocator);
        const resp = client.postJSON(uri, body) catch return error.WechatApiError;
        defer self.allocator.free(resp);

        var parsed = std.json.parseFromSlice(struct { errcode: i64 = 0, msg_id: i64 = 0 }, self.allocator, resp, .{}) catch return error.WechatApiError;
        defer parsed.deinit();
        if (parsed.value.errcode != 0) return error.WechatApiError;
        return parsed.value.msg_id;
    }

    /// 拉取微信数据统计（datacube），返回原始 JSON（透传，前端渲染）。
    /// api 白名单：getusersummary / getusercumulate / getarticlesummary /
    /// getinterfacesummary。
    pub fn getDatacube(self: *WechatService, account_id: i64, api: []const u8, begin_date: []const u8, end_date: []const u8) ![]u8 {
        const allowed = [_][]const u8{ "getusersummary", "getusercumulate", "getarticlesummary", "getinterfacesummary" };
        var ok = false;
        for (allowed) |a| {
            if (std.mem.eql(u8, api, a)) {
                ok = true;
                break;
            }
        }
        if (!ok) return error.InvalidDatacubeApi;
        if (begin_date.len == 0 or end_date.len == 0) return error.InvalidDate;

        const token = try self.getAccessToken(account_id);
        defer self.allocator.free(token);
        const uri = try std.fmt.allocPrint(self.allocator, "https://api.weixin.qq.com/datacube/{s}?access_token={s}", .{ api, token });
        defer self.allocator.free(uri);

        var out: std.Io.Writer.Allocating = .init(self.allocator);
        defer out.deinit();
        var s: std.json.Stringify = .{ .writer = &out.writer };
        try s.beginObject();
        try s.objectField("begin_date");
        try s.write(begin_date);
        try s.objectField("end_date");
        try s.write(end_date);
        try s.endObject();
        const body = try out.toOwnedSlice();
        defer self.allocator.free(body);

        const client = zwechat.util.http.getDefaultClient(self.allocator);
        const resp = client.postJSON(uri, body) catch return error.WechatApiError;
        defer self.allocator.free(resp);
        return self.allocator.dupe(u8, resp) catch error.OutOfMemory;
    }

    /// 小程序登录（sns/jscode2session，用 appid+secret 直接换 openid，
    /// 不需要 access_token）。返回 openid（caller free）。
    /// 复用 zwechat miniprogram.Auth（v0.3.0 已修复 code2Session 的 UAF：
    /// 返回 std.json.Parsed，由调用方 deinit）。
    pub fn miniLogin(self: *WechatService, account_id: i64, js_code: []const u8) ![]u8 {
        const cfg_opt = self.account_svc.getWechatConfig(account_id) catch return error.AccountNotFound;
        const cfg = cfg_opt orelse return error.AccountNotFound;
        defer cfg.deinit(self.allocator);

        var mp = zwechat.miniprogram.MiniProgram.init(
            self.allocator,
            .{
                .app_id = cfg.appid,
                .app_secret = cfg.secret,
                .token = cfg.token,
                .encoding_aes_key = cfg.encoding_aes_key,
            },
            // code2Session 不经过 access_token_handle（用 appid+secret 直接换）。
            .{ .ptr = undefined, .vtable = undefined },
        );
        const mctx = mp.getContext();
        var auth = zwechat.miniprogram.Auth.init(mctx, self.allocator);
        var parsed = auth.code2Session(js_code) catch return error.WechatApiError;
        defer parsed.deinit();
        if (parsed.value.errcode != 0) return error.WechatApiError;
        if (parsed.value.openid.len == 0) return error.WechatApiError;
        return self.allocator.dupe(u8, parsed.value.openid) catch error.OutOfMemory;
    }

    /// 主动发送客服文本消息（48h 会话窗口内）。复用 zwechat message API，
    /// access_token 走注入的 token_cache。
    pub fn sendCustomerText(self: *WechatService, account_id: i64, openid: []const u8, content: []const u8) !void {
        const tc = self.token_cache orelse return error.TokenCacheUnavailable;
        const cfg_opt = self.account_svc.getWechatConfig(account_id) catch return error.AccountNotFound;
        const cfg = cfg_opt orelse return error.AccountNotFound;
        defer cfg.deinit(self.allocator);

        var ak = zwechat.credential.DefaultAccessToken.init(cfg.appid, cfg.secret, "zweq", tc.asCache());
        var ctx = zwechat.officialaccount.Context{
            .config = .{
                .app_id = cfg.appid,
                .app_secret = cfg.secret,
                .token = cfg.token,
                .encoding_aes_key = cfg.encoding_aes_key,
            },
            .access_token_handle = ak.asHandle(),
        };
        var msg = zwechat.officialaccount.message.Message.init(&ctx, self.allocator);
        msg.sendCustomerText(.{ .touser = openid, .content = content }) catch return error.WechatApiError;
    }

    /// 发送模板消息（通知类场景）。复用 zwechat sendTemplate，返回 msgid。
    pub fn sendTemplate(self: *WechatService, account_id: i64, to_user: []const u8, template_id: []const u8, data: []const TemplateDataItem) !i64 {
        const tc = self.token_cache orelse return error.TokenCacheUnavailable;
        const cfg_opt = self.account_svc.getWechatConfig(account_id) catch return error.AccountNotFound;
        const cfg = cfg_opt orelse return error.AccountNotFound;
        defer cfg.deinit(self.allocator);

        const zdata = self.allocator.alloc(zwechat.officialaccount.message.TemplateMessage.TemplateData, data.len) catch return error.OutOfMemory;
        defer self.allocator.free(zdata);
        for (data, 0..) |d, i| {
            zdata[i] = .{ .key = d.key, .value = d.value, .color = d.color };
        }

        var ak = zwechat.credential.DefaultAccessToken.init(cfg.appid, cfg.secret, "zweq", tc.asCache());
        var ctx = zwechat.officialaccount.Context{
            .config = .{
                .app_id = cfg.appid,
                .app_secret = cfg.secret,
                .token = cfg.token,
                .encoding_aes_key = cfg.encoding_aes_key,
            },
            .access_token_handle = ak.asHandle(),
        };
        var msg = zwechat.officialaccount.message.Message.init(&ctx, self.allocator);
        return msg.sendTemplate(.{ .to_user = to_user, .template_id = template_id, .data = zdata }) catch error.WechatApiError;
    }

    /// Admin view: list callback logs for an account.
    pub fn listLogs(self: *WechatService, page: usize, page_size: usize, tenant_id: i64, account_id: i64) !MessageLogListResult {
        return self.store.list(page, page_size, tenant_id, account_id);
    }
};

fn makeParsed(doc: zwechat.util.xml.XmlDoc) ParsedMsg {
    return .{
        .doc = doc,
        .openid = doc.get("FromUserName") orelse "",
        .to_user = doc.get("ToUserName") orelse "",
        .msg_type = doc.get("MsgType") orelse "",
        .content = doc.get("Content") orelse "",
        .event = doc.get("Event") orelse "",
        .event_key = doc.get("EventKey") orelse "",
        .msg_id = doc.get("MsgId") orelse "",
    };
}
