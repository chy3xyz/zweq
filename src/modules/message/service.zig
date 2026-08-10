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
        const ts_str = try std.fmt.allocPrint(allocator, "{d}", .{self.now()});
        defer allocator.free(ts_str);
        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(allocator);
        try buf.print(allocator, "<xml><ToUserName><![CDATA[{s}]]></ToUserName>", .{to});
        try buf.print(allocator, "<FromUserName><![CDATA[{s}]]></FromUserName>", .{from});
        try buf.print(allocator, "<CreateTime>{s}</CreateTime>", .{ts_str});
        try buf.appendSlice(allocator, "<MsgType><![CDATA[news]]></MsgType><ArticleCount>1</ArticleCount><Articles>");
        try buf.print(allocator, "<item><Title><![CDATA[{s}]]></Title><Description><![CDATA[{s}]]></Description>", .{ r.news_title, r.news_description });
        try buf.print(allocator, "<PicUrl><![CDATA[{s}]]></PicUrl><Url><![CDATA[{s}]]></Url></item>", .{ r.news_pic_url, r.news_url });
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
