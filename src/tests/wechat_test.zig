//! 微信运营：账号 CRUD 与微信配置、关键词规则引擎、粉丝订阅/打标、消息回调（握手/关注/回复/签名/重放/菜单事件/AI 兜底）、菜单 JSON 解析、素材同步。
// 拆分自原 src/tests.zig（按域分文件，正文逐字保留）。

// 与原 src/tests.zig 相同的顶层命名，测试正文逐字搬运、零改动。
const std = @import("common.zig").std;
const zigmodu = @import("common.zig").zigmodu;
const zent = @import("common.zig").zent;
const zwechat = @import("common.zig").zwechat;
const db_mod = @import("common.zig").db_mod;
const schema = @import("common.zig").schema;
const user = @import("common.zig").user;
const auth = @import("common.zig").auth;
const task = @import("common.zig").task;
const file = @import("common.zig").file;
const notify = @import("common.zig").notify;
const tenant = @import("common.zig").tenant;
const audit = @import("common.zig").audit;
const mail_template = @import("common.zig").mail_template;
const ai = @import("common.zig").ai;
const account = @import("common.zig").account;
const permission = @import("common.zig").permission;
const setting = @import("common.zig").setting;
const rule = @import("common.zig").rule;
const member = @import("common.zig").member;
const message = @import("common.zig").message;
const appmod = @import("common.zig").appmod;
const payment = @import("common.zig").payment;
const cloud = @import("common.zig").cloud;
const material = @import("common.zig").material;
const checkin = @import("common.zig").checkin;
const lucky_draw = @import("common.zig").lucky_draw;
const coupon = @import("common.zig").coupon;
const vote = @import("common.zig").vote;
const seckill = @import("common.zig").seckill;
const member_card = @import("common.zig").member_card;
const distribution = @import("common.zig").distribution;
const shop = @import("common.zig").shop;
const menu = @import("common.zig").menu;
const points = @import("common.zig").points;
const cache_svc = @import("common.zig").cache_svc;
const mail = @import("common.zig").mail;
const mw_rate = @import("common.zig").mw_rate;
const all_infos = @import("common.zig").all_infos;
const openMemory = @import("common.zig").openMemory;
const openPostgres = @import("common.zig").openPostgres;

test "account: CRUD, tenant isolation, wechat config upsert" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var a_store = account.persistence.AccountStore.init(allocator, env.client);
    var a_svc = account.service.AccountService.init(allocator, std.testing.io, &a_store);

    // create + get
    const id = try a_svc.create(1, "测试公众号", "wechat");
    const row = (try a_svc.get(id)).?;
    defer row.free(allocator);
    try std.testing.expectEqualStrings("测试公众号", row.name);
    try std.testing.expectEqualStrings("wechat", row.kind);
    try std.testing.expectEqualStrings("active", row.status);

    // invalid kind rejected
    try std.testing.expectError(error.InvalidKind, a_svc.create(1, "坏类型", "car"));
    try std.testing.expectError(error.InvalidName, a_svc.create(1, "   ", "wechat"));

    // tenant isolation in list
    _ = try a_svc.create(2, "租户二公众号", "wechat");
    var t1 = try a_svc.list(1, 20, 1, null, "", "");
    defer t1.free(allocator);
    try std.testing.expectEqual(@as(i64, 1), t1.total);

    // kind filter
    var wc = try a_svc.list(1, 20, null, "wechat", "", "");
    defer wc.free(allocator);
    try std.testing.expectEqual(@as(i64, 2), wc.total);

    // update
    _ = try a_svc.update(id, "改名公众号", "wechat", "active");
    const updated = (try a_svc.get(id)).?;
    defer updated.free(allocator);
    try std.testing.expectEqualStrings("改名公众号", updated.name);

    // wechat config upsert (idempotent) + secrets round-trip
    const cfg1 = account.service.WechatConfig{
        .appid = "wx123",
        .secret = "sec1",
        .token = "tok1",
        .encoding_aes_key = "key1",
        .verified = false,
    };
    _ = try a_svc.upsertWechat(1, id, cfg1);
    const w1 = (try a_svc.getWechatConfig(id)).?;
    defer w1.deinit(allocator);
    try std.testing.expectEqualStrings("wx123", w1.appid);
    try std.testing.expectEqualStrings("sec1", w1.secret);

    const cfg2 = account.service.WechatConfig{
        .appid = "wx123",
        .secret = "sec2",
        .token = "tok1",
        .encoding_aes_key = "key1",
        .verified = true,
    };
    _ = try a_svc.upsertWechat(1, id, cfg2);
    const w2 = (try a_svc.getWechatConfig(id)).?;
    defer w2.deinit(allocator);
    try std.testing.expectEqualStrings("sec2", w2.secret);
    try std.testing.expect(w2.verified);

    // delete
    try a_svc.delete(id);
    try std.testing.expect((try a_svc.get(id)) == null);
}

test "rule: keyword engine matches full/contain and returns first reply" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var rule_store = rule.persistence.RuleStore.init(allocator, env.client);
    var rule_svc = rule.service.RuleService.init(allocator, std.testing.io, &rule_store);

    const account_id: i64 = 1;
    const r1 = try rule_svc.createRule(1, account_id, "问候");
    _ = try rule_svc.addKeyword(1, account_id, r1, "你好", "full");
    _ = try rule_svc.addReply(1, account_id, r1, "text", "你好呀", "", "", "", "");

    const r2 = try rule_svc.createRule(1, account_id, "新闻");
    _ = try rule_svc.addKeyword(1, account_id, r2, "新闻", "contain");
    _ = try rule_svc.addReply(1, account_id, r2, "news", "", "今日头条", "摘要", "http://pic/x.png", "http://a/x");

    // full match + contain match
    const m1 = (try rule_svc.match(allocator, 1, account_id, "你好")).?;
    defer m1.free(allocator);
    try std.testing.expectEqualStrings("text", m1.reply_type);
    try std.testing.expectEqualStrings("你好呀", m1.content);

    const m2 = (try rule_svc.match(allocator, 1, account_id, "看看新闻")).?;
    defer m2.free(allocator);
    try std.testing.expectEqualStrings("news", m2.reply_type);
    try std.testing.expectEqualStrings("今日头条", m2.news_title);

    // no match
    try std.testing.expect((try rule_svc.match(allocator, 1, account_id, "无关内容")) == null);

    // disabled rule is skipped
    try rule_svc.updateRule(r2, "新闻", "disabled");
    try std.testing.expect((try rule_svc.match(allocator, 1, account_id, "看看新闻")) == null);
}

test "member: fan subscribe/unsubscribe lifecycle + tenant isolation" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var fan_store = member.persistence.FanStore.init(allocator, env.client);
    var member_svc = member.service.MemberService.init(allocator, std.testing.io, &fan_store);

    _ = try member_svc.onSubscribe(1, 5, "o_abc", "");
    const fan = (try fan_store.getByOpenid(1, 5, "o_abc")).?;
    defer fan.free(allocator);
    try std.testing.expect(fan.subscribed);
    try std.testing.expectEqual(@as(i64, 5), fan.account_id);

    try member_svc.onUnsubscribe(1, 5, "o_abc");
    const fan2 = (try fan_store.getByOpenid(1, 5, "o_abc")).?;
    defer fan2.free(allocator);
    try std.testing.expect(!fan2.subscribed);

    // 不同租户同 openid 互不影响
    _ = try member_svc.onSubscribe(2, 5, "o_abc", "");
    var t1 = try member_svc.list(1, 20, 1, 5, null, true);
    defer t1.free(allocator);
    try std.testing.expectEqual(@as(i64, 0), t1.total); // t1 的 o_abc 已取关
    var t2 = try member_svc.list(1, 20, 2, 5, null, true);
    defer t2.free(allocator);
    try std.testing.expectEqual(@as(i64, 1), t2.total);
}

test "member: fan tag store upsert idempotent + list" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var tag_store = member.persistence.TagStore.init(allocator, env.client);

    // 同 wx_tag_id 两次 upsert → 同 id，字段更新。
    const t1 = try tag_store.upsert(1, 5, 100, "VIP", 100);
    const t2 = try tag_store.upsert(1, 5, 100, "VIPv2", 101);
    try std.testing.expectEqual(t1, t2);
    const t3 = try tag_store.upsert(1, 5, 101, "新客", 102);
    try std.testing.expect(t3 != t1);

    // list 按 wx_tag_id 升序。
    const rows = try tag_store.list(1, 5);
    defer {
        for (rows) |r| r.free(allocator);
        allocator.free(rows);
    }
    try std.testing.expectEqual(@as(usize, 2), rows.len);
    try std.testing.expectEqualStrings("VIPv2", rows[0].name);
    try std.testing.expectEqualStrings("新客", rows[1].name);

    // 另一租户隔离。
    const other = try tag_store.list(2, 5);
    defer {
        for (other) |r| r.free(allocator);
        allocator.free(other);
    }
    try std.testing.expectEqual(@as(usize, 0), other.len);
}

test "message: WeChat callback — handshake, subscribe, keyword reply, bad sig" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var account_store = account.persistence.AccountStore.init(allocator, env.client);
    var account_svc = account.service.AccountService.init(allocator, std.testing.io, &account_store);
    var rule_store = rule.persistence.RuleStore.init(allocator, env.client);
    var rule_svc = rule.service.RuleService.init(allocator, std.testing.io, &rule_store);
    var fan_store = member.persistence.FanStore.init(allocator, env.client);
    var member_svc = member.service.MemberService.init(allocator, std.testing.io, &fan_store);
    var setting_store = setting.persistence.SettingStore.init(allocator, env.client);
    var message_store = message.persistence.MessageStore.init(allocator, env.client);
    var wechat_svc = message.service.WechatService.init(allocator, std.testing.io, &account_svc, &rule_svc, &member_svc, &setting_store, &message_store);

    const account_id = try account_svc.create(1, "测试公众号", "wechat");
    _ = try account_svc.upsertWechat(1, account_id, .{
        .appid = "wx1",
        .secret = "s",
        .token = "tok",
        .encoding_aes_key = "",
        .verified = false,
    });
    const rule_id = try rule_svc.createRule(1, account_id, "问候");
    _ = try rule_svc.addKeyword(1, account_id, rule_id, "你好", "full");
    _ = try rule_svc.addReply(1, account_id, rule_id, "text", "你好呀", "", "", "", "");

    const token = "tok";
    var ts_buf: [16]u8 = undefined;
    const ts = try std.fmt.bufPrint(&ts_buf, "{d}", .{zigmodu.time.wallClockSeconds(std.testing.io)});
    const nonce = "n1";
    const sig = try zwechat.util.signature.signature(allocator, &[_][]const u8{ token, ts, nonce });
    defer allocator.free(sig);

    // 1. URL handshake: echostr echoed back.
    const handshake = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce, .echostr = "echo-me" }, "");
    defer allocator.free(handshake);
    try std.testing.expectEqualStrings("echo-me", handshake);

    // 2. subscribe event → fan saved, no follow reply configured → "success".
    const sub_xml = "<xml><ToUserName><![CDATA[gh_x]]></ToUserName><FromUserName><![CDATA[o_1]]></FromUserName><CreateTime>1700000000</CreateTime><MsgType><![CDATA[event]]></MsgType><Event><![CDATA[subscribe]]></Event></xml>";
    const sub_reply = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, sub_xml);
    defer allocator.free(sub_reply);
    try std.testing.expectEqualStrings("success", sub_reply);
    const fan = (try fan_store.getByOpenid(1, account_id, "o_1")).?;
    defer fan.free(allocator);
    try std.testing.expect(fan.subscribed);

    // 3. text keyword → passive text reply.
    const text_xml = "<xml><ToUserName><![CDATA[gh_x]]></ToUserName><FromUserName><![CDATA[o_1]]></FromUserName><CreateTime>1700000000</CreateTime><MsgType><![CDATA[text]]></MsgType><Content><![CDATA[你好]]></Content></xml>";
    const reply = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, text_xml);
    defer allocator.free(reply);
    try std.testing.expect(std.mem.indexOf(u8, reply, "你好呀") != null);
    try std.testing.expect(std.mem.indexOf(u8, reply, "<MsgType><![CDATA[text]]>") != null);

    // 4. bad signature → SignatureMismatch.
    try std.testing.expectError(error.SignatureMismatch, wechat_svc.handleCallback(allocator, token, .{ .signature = "bad", .timestamp = ts, .nonce = nonce }, text_xml));

    // 5. unsubscribe → fan flips to unsubscribed.
    const unsub_xml = "<xml><ToUserName><![CDATA[gh_x]]></ToUserName><FromUserName><![CDATA[o_1]]></FromUserName><CreateTime>1700000000</CreateTime><MsgType><![CDATA[event]]></MsgType><Event><![CDATA[unsubscribe]]></Event></xml>";
    const unsub_reply = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, unsub_xml);
    defer allocator.free(unsub_reply);
    const fan2 = (try fan_store.getByOpenid(1, account_id, "o_1")).?;
    defer fan2.free(allocator);
    try std.testing.expect(!fan2.subscribed);
}

test "message: replay guard rejects stale timestamp + duplicate nonce" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var account_store = account.persistence.AccountStore.init(allocator, env.client);
    var account_svc = account.service.AccountService.init(allocator, std.testing.io, &account_store);
    var rule_store = rule.persistence.RuleStore.init(allocator, env.client);
    var rule_svc = rule.service.RuleService.init(allocator, std.testing.io, &rule_store);
    var fan_store = member.persistence.FanStore.init(allocator, env.client);
    var member_svc = member.service.MemberService.init(allocator, std.testing.io, &fan_store);
    var setting_store = setting.persistence.SettingStore.init(allocator, env.client);
    var message_store = message.persistence.MessageStore.init(allocator, env.client);
    var cache = cache_svc.CacheService.init(allocator, 1024, 300);
    defer cache.deinit();
    var wechat_svc = message.service.WechatService.init(allocator, std.testing.io, &account_svc, &rule_svc, &member_svc, &setting_store, &message_store);
    wechat_svc.cache = &cache;

    const account_id = try account_svc.create(1, "测试公众号", "wechat");
    _ = try account_svc.upsertWechat(1, account_id, .{ .appid = "wx1", .secret = "s", .token = "tokr", .encoding_aes_key = "", .verified = false });

    const token = "tokr";
    const nonce = "n-replay";
    const now = zigmodu.time.wallClockSeconds(std.testing.io);
    const text_xml = "<xml><ToUserName><![CDATA[gh]]></ToUserName><FromUserName><![CDATA[o_r]]></FromUserName><CreateTime>1</CreateTime><MsgType><![CDATA[text]]></MsgType><Content><![CDATA[你好]]></Content></xml>";

    // 过期 timestamp（10 分钟前）→ 拒绝。
    var stale_buf: [16]u8 = undefined;
    const stale_ts = try std.fmt.bufPrint(&stale_buf, "{d}", .{now - 600});
    const stale_sig = try zwechat.util.signature.signature(allocator, &[_][]const u8{ token, stale_ts, nonce });
    defer allocator.free(stale_sig);
    try std.testing.expectError(error.TimestampExpired, wechat_svc.handleCallback(allocator, token, .{ .signature = stale_sig, .timestamp = stale_ts, .nonce = nonce }, text_xml));

    // 当前 timestamp + 相同 nonce：首次通过，重放被拒。
    var ts_buf: [16]u8 = undefined;
    const ts = try std.fmt.bufPrint(&ts_buf, "{d}", .{now});
    const sig = try zwechat.util.signature.signature(allocator, &[_][]const u8{ token, ts, nonce });
    defer allocator.free(sig);
    const first = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, text_xml);
    defer allocator.free(first);
    try std.testing.expectError(error.ReplayDetected, wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, text_xml));
}

test "message: menu CLICK event dispatches to module receiver" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var account_store = account.persistence.AccountStore.init(allocator, env.client);
    var account_svc = account.service.AccountService.init(allocator, std.testing.io, &account_store);
    var rule_store = rule.persistence.RuleStore.init(allocator, env.client);
    var rule_svc = rule.service.RuleService.init(allocator, std.testing.io, &rule_store);
    var fan_store = member.persistence.FanStore.init(allocator, env.client);
    var member_svc = member.service.MemberService.init(allocator, std.testing.io, &fan_store);
    var setting_store = setting.persistence.SettingStore.init(allocator, env.client);
    var message_store = message.persistence.MessageStore.init(allocator, env.client);
    var module_store = appmod.persistence.ModuleStore.init(allocator, env.client);
    var module_svc = appmod.service.ModuleService.init(allocator, std.testing.io, &module_store);
    var wechat_svc = message.service.WechatService.init(allocator, std.testing.io, &account_svc, &rule_svc, &member_svc, &setting_store, &message_store);
    wechat_svc.module_svc = &module_svc;

    // 注册一个响应菜单点击的接收器（demo 模块）。
    const Demo = struct {
        fn handle(_: ?*anyopaque, al: std.mem.Allocator, msg: message.service.IncomingMessage) anyerror!?message.service.Reply {
            if (!std.mem.eql(u8, msg.msg_type, "event")) return null;
            if (!std.mem.eql(u8, msg.event, "CLICK")) return null;
            if (!std.mem.eql(u8, msg.event_key, "VOTE_ENTRY")) return null;
            return try message.service.Reply.text(al, "菜单点击：进入投票");
        }
    };
    try wechat_svc.registerReceiver(.{ .module_name = "demo", .ctx = null, .handle = Demo.handle });

    const account_id = try account_svc.create(1, "测试公众号", "wechat");
    _ = try account_svc.upsertWechat(1, account_id, .{ .appid = "wx1", .secret = "s", .token = "tokm", .encoding_aes_key = "", .verified = false });
    _ = try module_svc.bind(1, account_id, "demo", "active");

    const token = "tokm";
    var ts_buf: [16]u8 = undefined;
    const ts = try std.fmt.bufPrint(&ts_buf, "{d}", .{zigmodu.time.wallClockSeconds(std.testing.io)});
    const nonce = "n-menu";
    const sig = try zwechat.util.signature.signature(allocator, &[_][]const u8{ token, ts, nonce });
    defer allocator.free(sig);

    // 菜单点击事件（CLICK + EventKey）→ receiver 响应。
    const click_xml = "<xml><ToUserName><![CDATA[gh]]></ToUserName><FromUserName><![CDATA[o_m]]></FromUserName><CreateTime>1</CreateTime><MsgType><![CDATA[event]]></MsgType><Event><![CDATA[CLICK]]></Event><EventKey><![CDATA[VOTE_ENTRY]]></EventKey></xml>";
    const reply = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, click_xml);
    defer allocator.free(reply);
    try std.testing.expect(std.mem.indexOf(u8, reply, "进入投票") != null);

    // 未绑定 → 事件不触发 receiver（仅记录，返回 success）。
    const other_id = try account_svc.create(1, "另一个号", "wechat");
    _ = try account_svc.upsertWechat(1, other_id, .{ .appid = "wx2", .secret = "s", .token = "tokn", .encoding_aes_key = "", .verified = false });
    var ts2: [16]u8 = undefined;
    const ts2_s = try std.fmt.bufPrint(&ts2, "{d}", .{zigmodu.time.wallClockSeconds(std.testing.io)});
    const sig2 = try zwechat.util.signature.signature(allocator, &[_][]const u8{ "tokn", ts2_s, nonce });
    defer allocator.free(sig2);
    const plain = try wechat_svc.handleCallback(allocator, "tokn", .{ .signature = sig2, .timestamp = ts2_s, .nonce = nonce }, click_xml);
    defer allocator.free(plain);
    try std.testing.expectEqualStrings("success", plain);
}

test "message: default reply + AI-flag fallback without provider" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var account_store = account.persistence.AccountStore.init(allocator, env.client);
    var account_svc = account.service.AccountService.init(allocator, std.testing.io, &account_store);
    var rule_store = rule.persistence.RuleStore.init(allocator, env.client);
    var rule_svc = rule.service.RuleService.init(allocator, std.testing.io, &rule_store);
    var fan_store = member.persistence.FanStore.init(allocator, env.client);
    var member_svc = member.service.MemberService.init(allocator, std.testing.io, &fan_store);
    var setting_store = setting.persistence.SettingStore.init(allocator, env.client);
    var message_store = message.persistence.MessageStore.init(allocator, env.client);
    var wechat_svc = message.service.WechatService.init(allocator, std.testing.io, &account_svc, &rule_svc, &member_svc, &setting_store, &message_store);
    // 无 ai_svc：AI 自动回复不可用，应优雅回退默认回复。

    const account_id = try account_svc.create(1, "测试公众号", "wechat");
    _ = try account_svc.upsertWechat(1, account_id, .{ .appid = "wx1", .secret = "s", .token = "tok2", .encoding_aes_key = "", .verified = false });
    const rule_id = try rule_svc.createRule(1, account_id, "问候");
    _ = try rule_svc.addKeyword(1, account_id, rule_id, "你好", "full");
    _ = try rule_svc.addReply(1, account_id, rule_id, "text", "你好呀", "", "", "", "");

    // 默认回复
    _ = try setting_store.set(1, "wechat_default_reply", "抱歉，暂未找到相关信息", 100);
    // 开启 AI 自动回复（无 provider，应回退默认）
    _ = try setting_store.set(1, "wechat_ai_auto_reply", "1", 101);

    const token = "tok2";
    var ts_buf: [16]u8 = undefined;
    const ts = try std.fmt.bufPrint(&ts_buf, "{d}", .{zigmodu.time.wallClockSeconds(std.testing.io)});
    const nonce = "n1";
    const sig = try zwechat.util.signature.signature(allocator, &[_][]const u8{ token, ts, nonce });
    defer allocator.free(sig);

    // 未命中规则 → AI 无 provider → 默认回复
    const miss_xml = "<xml><ToUserName><![CDATA[gh]]></ToUserName><FromUserName><![CDATA[o_2]]></FromUserName><CreateTime>1700000000</CreateTime><MsgType><![CDATA[text]]></MsgType><Content><![CDATA[随便聊聊]]></Content></xml>";
    const miss_reply = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, miss_xml);
    defer allocator.free(miss_reply);
    try std.testing.expect(std.mem.indexOf(u8, miss_reply, "抱歉，暂未找到相关信息") != null);

    // 命中规则 → 规则回复优先于 AI/默认
    const hit_xml = "<xml><ToUserName><![CDATA[gh]]></ToUserName><FromUserName><![CDATA[o_2]]></FromUserName><CreateTime>1700000000</CreateTime><MsgType><![CDATA[text]]></MsgType><Content><![CDATA[你好]]></Content></xml>";
    const hit_reply = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, hit_xml);
    defer allocator.free(hit_reply);
    try std.testing.expect(std.mem.indexOf(u8, hit_reply, "你好呀") != null);
}

test "material: news + file CRUD, kind validation" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var material_store = material.persistence.MaterialStore.init(allocator, env.client);
    var account_store = account.persistence.AccountStore.init(allocator, env.client);
    var account_svc = account.service.AccountService.init(allocator, std.testing.io, &account_store);
    var token_cache = try zwechat.cache.Memory.create(allocator);
    defer allocator.destroy(token_cache);
    defer token_cache.deinit();
    var material_svc = material.service.MaterialService.init(allocator, std.testing.io, &material_store, &account_svc, token_cache);

    // news CRUD
    const nid = try material_svc.createNews(1, 5, "今日头条", "小编", "摘要", "正文内容", "thumb_1", "http://t/x.png", "http://a/x");
    const row = (try material_svc.getNews(nid)).?;
    defer row.free(allocator);
    try std.testing.expectEqualStrings("今日头条", row.title);
    try std.testing.expectEqualStrings("http://a/x", row.url);

    try material_svc.updateNews(nid, "今日头条V2", "小编", "新摘要", "新正文", "thumb_1", "http://t/x.png", "http://a/y");
    const updated = (try material_svc.getNews(nid)).?;
    defer updated.free(allocator);
    try std.testing.expectEqualStrings("今日头条V2", updated.title);

    // 空标题拒绝
    try std.testing.expectError(error.InvalidTitle, material_svc.createNews(1, 5, "   ", "", "", "", "", "", ""));

    var news = try material_svc.listNews(1, 20, 1, 5, "");
    defer news.free(allocator);
    try std.testing.expectEqual(@as(i64, 1), news.total);

    // files CRUD + kind filter
    const fid = try material_svc.createFile(1, 5, "image", "img_abc", "http://cdn/x.png");
    _ = fid;
    _ = try material_svc.createFile(1, 5, "video", "vid_abc", "http://cdn/v.mp4");
    try std.testing.expectError(error.InvalidKind, material_svc.createFile(1, 5, "gif", "", ""));

    var imgs = try material_svc.listFiles(1, 20, 1, 5, "image");
    defer imgs.free(allocator);
    try std.testing.expectEqual(@as(i64, 1), imgs.total);
    try std.testing.expectEqualStrings("img_abc", imgs.items[0].media_id);

    try material_svc.deleteNews(nid);
    try std.testing.expect((try material_svc.getNews(nid)) == null);
}

test "material: sync upsert idempotent by media_id" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var material_store = material.persistence.MaterialStore.init(allocator, env.client);

    // 图文：同 media_id 两次 upsert → 同 id，字段更新。
    const n1 = try material_store.upsertNews(1, 5, "news_1", "标题A", "作者", "摘要", "正文", "thumb_1", "", "http://a/1", 100);
    const n2 = try material_store.upsertNews(1, 5, "news_1", "标题B", "作者", "摘要", "正文", "thumb_1", "", "http://a/1", 101);
    try std.testing.expectEqual(n1, n2);
    const news = (try material_store.getNewsByMediaId(1, 5, "news_1")).?;
    defer news.free(allocator);
    try std.testing.expectEqualStrings("标题B", news.title);

    // 不同 media_id → 新行。
    const n3 = try material_store.upsertNews(1, 5, "news_2", "另一篇", "", "", "", "", "", "", 102);
    try std.testing.expect(n3 != n1);

    // 文件：同 media_id 幂等。
    const f1 = try material_store.upsertFile(1, 5, "image", "img_1", "http://cdn/1.png", 100);
    const f2 = try material_store.upsertFile(1, 5, "image", "img_1", "http://cdn/1.png", 101);
    try std.testing.expectEqual(f1, f2);
    const frow = (try material_store.getFileByMediaId(1, 5, "img_1")).?;
    defer frow.free(allocator);
    try std.testing.expectEqualStrings("image", frow.kind);
    try std.testing.expectEqualStrings("http://cdn/1.png", frow.url);
}

test "menu: save/get + parseButtons JSON→Button conversion" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var menu_store = menu.persistence.MenuStore.init(allocator, env.client);
    var account_store = account.persistence.AccountStore.init(allocator, env.client);
    var account_svc = account.service.AccountService.init(allocator, std.testing.io, &account_store);
    var token_cache = try zwechat.cache.Memory.create(allocator);
    defer allocator.destroy(token_cache);
    defer token_cache.deinit();
    var menu_svc = menu.service.MenuService.init(allocator, std.testing.io, &menu_store, &account_svc, token_cache);

    // parseButtons: JSON → zwechat Button（含子菜单，字段深拷贝）。
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const json = "[{\"type\":\"click\",\"name\":\"按钮1\",\"key\":\"K1\"},{\"name\":\"菜单\",\"sub_button\":[{\"type\":\"view\",\"name\":\"子1\",\"url\":\"http://x\"}]}]";
    const buttons = try menu.service.parseButtons(arena.allocator(), json);
    try std.testing.expectEqual(@as(usize, 2), buttons.len);
    try std.testing.expectEqualStrings("click", buttons[0].type_);
    try std.testing.expectEqualStrings("K1", buttons[0].key);
    try std.testing.expectEqual(@as(usize, 1), buttons[1].sub_button.len);
    try std.testing.expectEqualStrings("view", buttons[1].sub_button[0].type_);
    try std.testing.expectEqualStrings("http://x", buttons[1].sub_button[0].url);

    // 非法 JSON 拒绝。
    try std.testing.expectError(error.InvalidJson, menu.service.parseButtons(arena.allocator(), "not-json"));

    // save（含 JSON 校验）+ get（DB）。
    const id1 = try menu_svc.save(1, 7, json);
    const row = (try menu_svc.get(1, 7)).?;
    defer row.free(allocator);
    try std.testing.expectEqual(id1, row.id);
    try std.testing.expectEqualStrings(json, row.menu_json);

    // 非法 JSON 保存被拒。
    try std.testing.expectError(error.InvalidJson, menu_svc.save(1, 7, "oops"));

    // upsert 幂等（同账号更新）。
    const id2 = try menu_svc.save(1, 7, "[]");
    try std.testing.expectEqual(id1, id2);
    const row2 = (try menu_svc.get(1, 7)).?;
    defer row2.free(allocator);
    try std.testing.expectEqualStrings("[]", row2.menu_json);
}
