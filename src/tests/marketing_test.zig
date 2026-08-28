//! 营销增长：积分兑换、签到、抽奖（权重+日限）、卡券生命周期与领券回调、投票、秒杀（原子库存）、会员卡（等级成长）、分销三级佣金与提现。
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

test "points: redeem deducts points + stock, rejects insufficient/out-of-stock" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var fan_store = member.persistence.FanStore.init(allocator, env.client);
    var points_store = points.persistence.PointsStore.init(allocator, env.client);
    var svc = points.service.PointsService.init(allocator, std.testing.io, &points_store, &fan_store);

    // 粉丝 + 发 100 积分。
    _ = try fan_store.upsert(1, 5, "o_p", "", "", "", true, 100, 100);
    const newp = try fan_store.adjustPoints(1, 5, "o_p", 100, 101);
    try std.testing.expectEqual(@as(i64, 100), newp);

    // 商品（100 积分，库存 5）。
    const pid = try svc.createProduct(1, 5, "马克杯", 100, 5);

    // 兑换成功：积分 100→0，库存 5→4，订单 1 条。
    const order_id = try svc.redeem(1, 5, "o_p", pid);
    _ = order_id;
    const fan = (try fan_store.getByOpenid(1, 5, "o_p")).?;
    defer fan.free(allocator);
    try std.testing.expectEqual(@as(i64, 0), fan.points);
    const prod = (try svc.getProduct(pid)).?;
    defer prod.free(allocator);
    try std.testing.expectEqual(@as(i64, 4), prod.stock);
    const orders = try svc.listOrders(1, 5, null);
    defer {
        for (orders) |o| o.free(allocator);
        allocator.free(orders);
    }
    try std.testing.expectEqual(@as(usize, 1), orders.len);
    try std.testing.expectEqual(@as(i64, 100), orders[0].points_spent);

    // 积分不足 → 拒绝。
    try std.testing.expectError(error.InsufficientPoints, svc.redeem(1, 5, "o_p", pid));

    // 库存清空 → OutOfStock。
    _ = try svc.adjustPoints(1, 5, "o_p", 100);
    try svc.updateProduct(pid, "马克杯", 100, 0);
    try std.testing.expectError(error.OutOfStock, svc.redeem(1, 5, "o_p", pid));

    // 粉丝不存在 → FanNotFound（用有库存的商品）。
    const pid2 = try svc.createProduct(1, 5, "新商品", 50, 1);
    try std.testing.expectError(error.FanNotFound, svc.redeem(1, 5, "o_nobody", pid2));
}

test "checkin: module receiver handles 签到 + per-account config" {
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
    var checkin_store = checkin.persistence.CheckinStore.init(allocator, env.client);
    var checkin_svc = checkin.service.CheckinService.init(allocator, std.testing.io, &checkin_store);

    var wechat_svc = message.service.WechatService.init(allocator, std.testing.io, &account_svc, &rule_svc, &member_svc, &setting_store, &message_store);
    wechat_svc.module_svc = &module_svc;
    var checkin_ctx = checkin.service.ReceiverCtx{ .module_svc = &module_svc, .checkin_svc = &checkin_svc, .io = std.testing.io };
    try wechat_svc.registerReceiver(.{ .module_name = "checkin", .ctx = &checkin_ctx, .handle = checkin.service.receiverHandle });

    const account_id = try account_svc.create(1, "测试公众号", "wechat");
    _ = try account_svc.upsertWechat(1, account_id, .{ .appid = "wx1", .secret = "s", .token = "tokc", .encoding_aes_key = "", .verified = false });

    // 绑定 checkin 模块 + 配置每次签到奖励 5 积分。
    _ = try module_svc.bind(1, account_id, "checkin", "active");
    _ = try module_svc.setConfig(1, account_id, "checkin", "5");

    const token = "tokc";
    var ts_buf: [16]u8 = undefined;
    const ts = try std.fmt.bufPrint(&ts_buf, "{d}", .{zigmodu.time.wallClockSeconds(std.testing.io)});
    const nonce = "n1";
    const sig = try zwechat.util.signature.signature(allocator, &[_][]const u8{ token, ts, nonce });
    defer allocator.free(sig);

    const text_xml = "<xml><ToUserName><![CDATA[gh]]></ToUserName><FromUserName><![CDATA[o_9]]></FromUserName><CreateTime>1700000000</CreateTime><MsgType><![CDATA[text]]></MsgType><Content><![CDATA[签到]]></Content></xml>";

    // 首次签到 → receiver 回复「签到成功」+ 积分。
    const r1 = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, text_xml);
    defer allocator.free(r1);
    try std.testing.expect(std.mem.indexOf(u8, r1, "签到成功") != null);
    try std.testing.expect(std.mem.indexOf(u8, r1, "5 积分") != null);

    // 同一天重复签到 → 幂等回复「已经签到」。
    const r2 = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, text_xml);
    defer allocator.free(r2);
    try std.testing.expect(std.mem.indexOf(u8, r2, "已经签到") != null);

    // 记录落库：仅一条，积分为 5。
    var list = try checkin_svc.list(1, 20, 1, account_id);
    defer list.free(allocator);
    try std.testing.expectEqual(@as(i64, 1), list.total);
    try std.testing.expectEqual(@as(i64, 5), list.items[0].points);

    // config 读写回环。
    const cfg = (try module_svc.getConfig(allocator, 1, account_id, "checkin")).?;
    defer allocator.free(cfg);
    try std.testing.expectEqualStrings("5", cfg);
}

test "lucky_draw: weighted pick + draw records + daily_limit" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = lucky_draw.persistence.DrawStore.init(allocator, env.client);
    var svc = lucky_draw.service.DrawService.init(allocator, std.testing.io, &store);

    // pickPrize：加权边界（roll 落在各区间的确定性结果）。
    const prizes = [_]lucky_draw.service.Prize{
        .{ .name = "A", .weight = 50, .points = 10 },
        .{ .name = "B", .weight = 30, .points = 20 },
        .{ .name = "C", .weight = 20, .points = 0 },
    };
    try std.testing.expectEqual(@as(usize, 0), lucky_draw.service.DrawService.pickPrize(&prizes, 0));
    try std.testing.expectEqual(@as(usize, 0), lucky_draw.service.DrawService.pickPrize(&prizes, 49));
    try std.testing.expectEqual(@as(usize, 1), lucky_draw.service.DrawService.pickPrize(&prizes, 50));
    try std.testing.expectEqual(@as(usize, 2), lucky_draw.service.DrawService.pickPrize(&prizes, 99));

    // parseConfig：合法 JSON + 缺 prizes 兜底。
    var cfg = svc.parseConfig(allocator, "{\"cost\":5,\"daily_limit\":3,\"prizes\":[{\"name\":\"10积分\",\"weight\":50,\"points\":10},{\"name\":\"谢谢参与\",\"weight\":50,\"points\":0}]}");
    defer cfg.free(allocator);
    try std.testing.expectEqual(@as(i64, 5), cfg.cost);
    try std.testing.expectEqual(@as(i64, 3), cfg.daily_limit);
    try std.testing.expectEqual(@as(usize, 2), cfg.prizes.len);

    // draw：落库 + 返回中奖。
    const result = try svc.draw(allocator, 1, 9, "o_luck", &cfg);
    defer allocator.free(result.prize_name);
    var list = try svc.list(1, 20, 1, 9);
    defer list.free(allocator);
    try std.testing.expectEqual(@as(i64, 1), list.total);
    try std.testing.expectEqualStrings("o_luck", list.items[0].openid);

    // daily_limit=1：第二次 draw → DailyLimit。
    var cfg1 = svc.parseConfig(allocator, "{\"daily_limit\":1,\"prizes\":[{\"name\":\"X\",\"weight\":1,\"points\":0}]}");
    defer cfg1.free(allocator);
    const r1 = try svc.draw(allocator, 1, 9, "o_lim", &cfg1);
    defer allocator.free(r1.prize_name);
    try std.testing.expectError(error.DailyLimit, svc.draw(allocator, 1, 9, "o_lim", &cfg1));
}

test "lucky_draw: module receiver handles 抽奖" {
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
    var draw_store = lucky_draw.persistence.DrawStore.init(allocator, env.client);
    var draw_svc = lucky_draw.service.DrawService.init(allocator, std.testing.io, &draw_store);

    var wechat_svc = message.service.WechatService.init(allocator, std.testing.io, &account_svc, &rule_svc, &member_svc, &setting_store, &message_store);
    wechat_svc.module_svc = &module_svc;
    var draw_ctx = lucky_draw.service.ReceiverCtx{ .module_svc = &module_svc, .draw_svc = &draw_svc, .io = std.testing.io };
    try wechat_svc.registerReceiver(.{ .module_name = "lucky_draw", .ctx = &draw_ctx, .handle = lucky_draw.service.receiverHandle });

    const account_id = try account_svc.create(1, "抽奖测试号", "wechat");
    _ = try account_svc.upsertWechat(1, account_id, .{ .appid = "wx1", .secret = "s", .token = "tokl", .encoding_aes_key = "", .verified = false });
    _ = try module_svc.bind(1, account_id, "lucky_draw", "active");
    _ = try module_svc.setConfig(1, account_id, "lucky_draw", "{\"prizes\":[{\"name\":\"10积分\",\"weight\":1,\"points\":10}]}");

    const token = "tokl";
    var ts_buf: [16]u8 = undefined;
    const ts = try std.fmt.bufPrint(&ts_buf, "{d}", .{zigmodu.time.wallClockSeconds(std.testing.io)});
    const nonce = "n2";
    const sig = try zwechat.util.signature.signature(allocator, &[_][]const u8{ token, ts, nonce });
    defer allocator.free(sig);

    const text_xml = "<xml><ToUserName><![CDATA[gh]]></ToUserName><FromUserName><![CDATA[o_draw]]></FromUserName><CreateTime>1700000000</CreateTime><MsgType><![CDATA[text]]></MsgType><Content><![CDATA[抽奖]]></Content></xml>";
    const r = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, text_xml);
    defer allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "抽中") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "10积分") != null);

    // 中奖记录落库。
    var list = try draw_svc.list(1, 20, 1, account_id);
    defer list.free(allocator);
    try std.testing.expectEqual(@as(i64, 1), list.total);
}

test "coupon: create/claim/use lifecycle + stock/limit" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = coupon.persistence.CouponStore.init(allocator, env.client);
    var svc = coupon.service.CouponService.init(allocator, std.testing.io, &store);

    // 建券：总量 2，每人限领 1。
    const cid = try svc.createCoupon(1, 9, "满100减20", 2000, 10000, 2, 1, 0, 0);
    const c = (try svc.getCoupon(cid)).?;
    defer c.free(allocator);
    try std.testing.expectEqualStrings("满100减20", c.title);
    try std.testing.expectEqualStrings("2000", c.amount);

    // 领券：券码 CP- 前缀。
    const code1 = try svc.claimCoupon(allocator, 1, 9, "o_a", cid);
    defer allocator.free(code1);
    try std.testing.expect(std.mem.startsWith(u8, code1, "CP-"));

    // 每人限领 1：同用户再领 → LimitReached。
    try std.testing.expectError(error.LimitReached, svc.claimCoupon(allocator, 1, 9, "o_a", cid));

    // 库存：总量 2，已发 1，再发 1 给另一用户 → 成功；第 3 个 → OutOfStock。
    const code2 = try svc.claimCoupon(allocator, 1, 9, "o_b", cid);
    defer allocator.free(code2);
    try std.testing.expectError(error.OutOfStock, svc.claimCoupon(allocator, 1, 9, "o_c", cid));

    // 核销：unused→used 幂等。
    try svc.useCoupon(code1);
    try std.testing.expectError(error.AlreadyUsed, svc.useCoupon(code1));

    // 领取记录落库。
    var list = try svc.listUserCoupons(1, 20, 1, 9, null);
    defer list.free(allocator);
    try std.testing.expectEqual(@as(i64, 2), list.total);

    // 过期券：end_at 已过 → Expired。
    const cid2 = try svc.createCoupon(1, 9, "过期券", 100, 0, 0, 1, 0, 1000);
    try std.testing.expectError(error.Expired, svc.claimCoupon(allocator, 1, 9, "o_d", cid2));
}

test "coupon: module receiver handles 领券" {
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
    var coupon_store = coupon.persistence.CouponStore.init(allocator, env.client);
    var coupon_svc = coupon.service.CouponService.init(allocator, std.testing.io, &coupon_store);

    var wechat_svc = message.service.WechatService.init(allocator, std.testing.io, &account_svc, &rule_svc, &member_svc, &setting_store, &message_store);
    wechat_svc.module_svc = &module_svc;
    var coupon_ctx = coupon.service.ReceiverCtx{ .module_svc = &module_svc, .coupon_svc = &coupon_svc, .io = std.testing.io };
    try wechat_svc.registerReceiver(.{ .module_name = "coupon", .ctx = &coupon_ctx, .handle = coupon.service.receiverHandle });

    const account_id = try account_svc.create(1, "券测试号", "wechat");
    _ = try account_svc.upsertWechat(1, account_id, .{ .appid = "wx1", .secret = "s", .token = "tokcp", .encoding_aes_key = "", .verified = false });
    _ = try module_svc.bind(1, account_id, "coupon", "active");
    _ = try coupon_svc.createCoupon(1, account_id, "新人券", 500, 0, 10, 1, 0, 0);

    const token = "tokcp";
    var ts_buf: [16]u8 = undefined;
    const ts = try std.fmt.bufPrint(&ts_buf, "{d}", .{zigmodu.time.wallClockSeconds(std.testing.io)});
    const nonce = "ncp";
    const sig = try zwechat.util.signature.signature(allocator, &[_][]const u8{ token, ts, nonce });
    defer allocator.free(sig);

    const text_xml = "<xml><ToUserName><![CDATA[gh]]></ToUserName><FromUserName><![CDATA[o_cp]]></FromUserName><CreateTime>1700000000</CreateTime><MsgType><![CDATA[text]]></MsgType><Content><![CDATA[领券]]></Content></xml>";
    const r = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, text_xml);
    defer allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "领券成功") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "CP-") != null);

    // 已领满（每人限领 1）→ 回复「已领完」。
    const r2 = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, text_xml);
    defer allocator.free(r2);
    try std.testing.expect(std.mem.indexOf(u8, r2, "已领完") != null);
}

test "vote: create/vote/tally lifecycle + dedup" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = vote.persistence.VoteStore.init(allocator, env.client);
    var svc = vote.service.VoteService.init(allocator, std.testing.io, &store);

    const vid = try svc.createVote(1, 9, "最喜欢的语言", "[\"Zig\",\"Rust\",\"Go\"]", 0);
    const v = (try svc.getVote(vid)).?;
    defer v.free(allocator);
    try std.testing.expectEqualStrings("最喜欢的语言", v.title);

    // 投票：o_a 投 0（Zig），o_b 投 1（Rust），o_c 投 0。
    try svc.vote(1, 9, "o_a", vid, 0);
    try svc.vote(1, 9, "o_b", vid, 1);
    try svc.vote(1, 9, "o_c", vid, 0);

    // 防重：o_a 再投 → AlreadyVoted。
    try std.testing.expectError(error.AlreadyVoted, svc.vote(1, 9, "o_a", vid, 1));

    // 计票：Zig=2, Rust=1, Go=0。
    const tally = try svc.tally(allocator, vid);
    defer allocator.free(tally);
    try std.testing.expectEqual(@as(i64, 2), tally[0]);
    try std.testing.expectEqual(@as(i64, 1), tally[1]);
    try std.testing.expectEqual(@as(i64, 0), tally[2]);

    // 非法选项 → InvalidOption。
    try std.testing.expectError(error.InvalidOption, svc.vote(1, 9, "o_d", vid, 99));
}

test "vote: module receiver handles 投票 + 投N" {
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
    var vote_store = vote.persistence.VoteStore.init(allocator, env.client);
    var vote_svc = vote.service.VoteService.init(allocator, std.testing.io, &vote_store);

    var wechat_svc = message.service.WechatService.init(allocator, std.testing.io, &account_svc, &rule_svc, &member_svc, &setting_store, &message_store);
    wechat_svc.module_svc = &module_svc;
    var vote_ctx = vote.service.ReceiverCtx{ .module_svc = &module_svc, .vote_svc = &vote_svc, .io = std.testing.io };
    try wechat_svc.registerReceiver(.{ .module_name = "vote", .ctx = &vote_ctx, .handle = vote.service.receiverHandle });

    const account_id = try account_svc.create(1, "投票测试号", "wechat");
    _ = try account_svc.upsertWechat(1, account_id, .{ .appid = "wx1", .secret = "s", .token = "tokv", .encoding_aes_key = "", .verified = false });
    _ = try module_svc.bind(1, account_id, "vote", "active");
    _ = try vote_svc.createVote(1, account_id, "今晚吃什么", "[\"火锅\",\"烧烤\"]", 0);

    const token = "tokv";
    var ts_buf: [16]u8 = undefined;
    const ts = try std.fmt.bufPrint(&ts_buf, "{d}", .{zigmodu.time.wallClockSeconds(std.testing.io)});
    const nonce = "nv";
    const sig = try zwechat.util.signature.signature(allocator, &[_][]const u8{ token, ts, nonce });
    defer allocator.free(sig);

    // 「投票」→ 列题目 + 选项。
    const q_xml = "<xml><ToUserName><![CDATA[gh]]></ToUserName><FromUserName><![CDATA[o_v]]></FromUserName><CreateTime>1700000000</CreateTime><MsgType><![CDATA[text]]></MsgType><Content><![CDATA[投票]]></Content></xml>";
    const r1 = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, q_xml);
    defer allocator.free(r1);
    try std.testing.expect(std.mem.indexOf(u8, r1, "今晚吃什么") != null);
    try std.testing.expect(std.mem.indexOf(u8, r1, "火锅") != null);

    // 「投1」→ 投票成功。
    const v_xml = "<xml><ToUserName><![CDATA[gh]]></ToUserName><FromUserName><![CDATA[o_v]]></FromUserName><CreateTime>1700000000</CreateTime><MsgType><![CDATA[text]]></MsgType><Content><![CDATA[投1]]></Content></xml>";
    const r2 = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, v_xml);
    defer allocator.free(r2);
    try std.testing.expect(std.mem.indexOf(u8, r2, "投票成功") != null);

    // 再「投2」→ 已投过。
    const v2_xml = "<xml><ToUserName><![CDATA[gh]]></ToUserName><FromUserName><![CDATA[o_v]]></FromUserName><CreateTime>1700000000</CreateTime><MsgType><![CDATA[text]]></MsgType><Content><![CDATA[投2]]></Content></xml>";
    const r3 = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, v2_xml);
    defer allocator.free(r3);
    try std.testing.expect(std.mem.indexOf(u8, r3, "已经投过") != null);
}

test "checkin: unbound module declines, falls through to default reply" {
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
    var checkin_store = checkin.persistence.CheckinStore.init(allocator, env.client);
    var checkin_svc = checkin.service.CheckinService.init(allocator, std.testing.io, &checkin_store);

    var wechat_svc = message.service.WechatService.init(allocator, std.testing.io, &account_svc, &rule_svc, &member_svc, &setting_store, &message_store);
    wechat_svc.module_svc = &module_svc;
    var checkin_ctx = checkin.service.ReceiverCtx{ .module_svc = &module_svc, .checkin_svc = &checkin_svc, .io = std.testing.io };
    try wechat_svc.registerReceiver(.{ .module_name = "checkin", .ctx = &checkin_ctx, .handle = checkin.service.receiverHandle });

    const account_id = try account_svc.create(1, "测试公众号", "wechat");
    _ = try account_svc.upsertWechat(1, account_id, .{ .appid = "wx1", .secret = "s", .token = "tokd", .encoding_aes_key = "", .verified = false });
    // 注意：不绑定 checkin 模块 → receiver 不应被分发。
    _ = try setting_store.set(1, "wechat_default_reply", "默认回复", 100);

    const token = "tokd";
    var ts_buf: [16]u8 = undefined;
    const ts = try std.fmt.bufPrint(&ts_buf, "{d}", .{zigmodu.time.wallClockSeconds(std.testing.io)});
    const nonce = "n1";
    const sig = try zwechat.util.signature.signature(allocator, &[_][]const u8{ token, ts, nonce });
    defer allocator.free(sig);

    const text_xml = "<xml><ToUserName><![CDATA[gh]]></ToUserName><FromUserName><![CDATA[o_8]]></FromUserName><CreateTime>1700000000</CreateTime><MsgType><![CDATA[text]]></MsgType><Content><![CDATA[签到]]></Content></xml>";
    const reply = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, text_xml);
    defer allocator.free(reply);
    try std.testing.expect(std.mem.indexOf(u8, reply, "默认回复") != null);
    // 未绑定 → 无签到记录落库。
    var list = try checkin_svc.list(1, 20, 1, account_id);
    defer list.free(allocator);
    try std.testing.expectEqual(@as(i64, 0), list.total);
}

test "seckill: rush lifecycle + atomic stock + dedup" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = seckill.persistence.SeckillStore.init(allocator, env.client);
    var svc = seckill.service.SeckillService.init(allocator, std.testing.io, &store);

    const aid = try svc.createActivity(1, 9, "限时特惠", 9900, 19900, 2, 1, 0, 0);

    // 抢 1 件成功，sold=1。
    _ = try svc.rush(1, 9, "o_a", aid, 1);
    const a1 = (try svc.getActivity(aid)).?;
    defer a1.free(allocator);
    try std.testing.expectEqual(@as(i64, 1), a1.sold);

    // 另一用户抢 1 件，sold=2（库存耗尽）。
    _ = try svc.rush(1, 9, "o_b", aid, 1);
    const a2 = (try svc.getActivity(aid)).?;
    defer a2.free(allocator);
    try std.testing.expectEqual(@as(i64, 2), a2.sold);

    // 第 3 件 → OutOfStock（原子扣减失败）。
    try std.testing.expectError(error.OutOfStock, svc.rush(1, 9, "o_c", aid, 1));

    // 限购：o_a 已抢 1，per_user=1 → 再抢 LimitReached。
    try std.testing.expectError(error.LimitReached, svc.rush(1, 9, "o_a", aid, 1));

    // 不存在活动 → NotFound。
    try std.testing.expectError(error.NotFound, svc.rush(1, 9, "o_x", 9999, 1));
}

test "seckill: module receiver handles 秒杀 + 抢N" {
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
    var seckill_store = seckill.persistence.SeckillStore.init(allocator, env.client);
    var seckill_svc = seckill.service.SeckillService.init(allocator, std.testing.io, &seckill_store);

    var wechat_svc = message.service.WechatService.init(allocator, std.testing.io, &account_svc, &rule_svc, &member_svc, &setting_store, &message_store);
    wechat_svc.module_svc = &module_svc;
    var seckill_ctx = seckill.service.ReceiverCtx{ .io = std.testing.io, .seckill_svc = &seckill_svc };
    try wechat_svc.registerReceiver(.{ .module_name = "seckill", .ctx = &seckill_ctx, .handle = seckill.service.receiverHandle });

    const account_id = try account_svc.create(1, "秒杀测试号", "wechat");
    _ = try account_svc.upsertWechat(1, account_id, .{ .appid = "wx1", .secret = "s", .token = "toks", .encoding_aes_key = "", .verified = false });
    _ = try module_svc.bind(1, account_id, "seckill", "active");
    _ = try seckill_svc.createActivity(1, account_id, "周年庆秒杀", 100, 500, 10, 1, 0, 0);

    const token = "toks";
    var ts_buf: [16]u8 = undefined;
    const ts = try std.fmt.bufPrint(&ts_buf, "{d}", .{zigmodu.time.wallClockSeconds(std.testing.io)});
    const nonce = "ns";
    const sig = try zwechat.util.signature.signature(allocator, &[_][]const u8{ token, ts, nonce });
    defer allocator.free(sig);

    // 「秒杀」→ 列活动 + 价格 + 剩余。
    const q_xml = "<xml><ToUserName><![CDATA[gh]]></ToUserName><FromUserName><![CDATA[o_s]]></FromUserName><CreateTime>1700000000</CreateTime><MsgType><![CDATA[text]]></MsgType><Content><![CDATA[秒杀]]></Content></xml>";
    const r1 = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, q_xml);
    defer allocator.free(r1);
    try std.testing.expect(std.mem.indexOf(u8, r1, "周年庆秒杀") != null);
    try std.testing.expect(std.mem.indexOf(u8, r1, "1.00") != null);

    // 「抢1」→ 抢购成功。
    const rush_xml = "<xml><ToUserName><![CDATA[gh]]></ToUserName><FromUserName><![CDATA[o_s]]></FromUserName><CreateTime>1700000000</CreateTime><MsgType><![CDATA[text]]></MsgType><Content><![CDATA[抢1]]></Content></xml>";
    const r2 = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, rush_xml);
    defer allocator.free(r2);
    try std.testing.expect(std.mem.indexOf(u8, r2, "抢购成功") != null);

    // 再抢 → 每人限购。
    const r3 = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, rush_xml);
    defer allocator.free(r3);
    try std.testing.expect(std.mem.indexOf(u8, r3, "每人限购") != null);
}

test "member_card: open/view/adjust lifecycle + auto level-up" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = member_card.persistence.MemberCardStore.init(allocator, env.client);
    var svc = member_card.service.MemberCardService.init(allocator, std.testing.io, &store);

    // 建两个等级：普通（0 积分 9.5 折）+ 黄金（1000 积分 9 折）。
    const normal_id = try svc.createLevel(1, 9, "普通会员", 1, 950, 100, 0);
    const gold_id = try svc.createLevel(1, 9, "黄金会员", 2, 900, 200, 1000);

    // 开卡 → 默认普通等级。
    try svc.openCard(1, 9, "o_m");
    var v1 = (try svc.view(1, 9, "o_m")).?;
    defer v1.free(allocator);
    try std.testing.expectEqualStrings("普通会员", v1.level_name);
    try std.testing.expectEqual(@as(i64, 0), v1.points);
    try std.testing.expectEqual(@as(i64, 950), v1.discount);

    // 重复开卡 → AlreadyOpened。
    try std.testing.expectError(error.AlreadyOpened, svc.openCard(1, 9, "o_m"));

    // 加积分 1200 → 余额 1200 + 自动升级黄金。
    try svc.adjust(1, 9, "o_m", 1200);
    var v2 = (try svc.view(1, 9, "o_m")).?;
    defer v2.free(allocator);
    try std.testing.expectEqualStrings("黄金会员", v2.level_name);
    try std.testing.expectEqual(@as(i64, 1200), v2.points);
    try std.testing.expectEqual(@as(i64, 900), v2.discount);

    // 消耗 1300 → 积分不足拒绝。
    try std.testing.expectError(error.InsufficientPoints, svc.adjust(1, 9, "o_m", -1300));

    // 消耗 500 → 余额 700，等级仍黄金（累计 1200 >= 1000）。
    try svc.adjust(1, 9, "o_m", -500);
    var v3 = (try svc.view(1, 9, "o_m")).?;
    defer v3.free(allocator);
    try std.testing.expectEqual(@as(i64, 700), v3.points);
    try std.testing.expectEqualStrings("黄金会员", v3.level_name);

    // 未办卡 → NotFound。
    try std.testing.expectError(error.NotFound, svc.adjust(1, 9, "o_nobody", 100));
    _ = normal_id;
    _ = gold_id;
}

test "member_card: module receiver handles 办卡 + 查卡" {
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
    var mc_store = member_card.persistence.MemberCardStore.init(allocator, env.client);
    var mc_svc = member_card.service.MemberCardService.init(allocator, std.testing.io, &mc_store);

    var wechat_svc = message.service.WechatService.init(allocator, std.testing.io, &account_svc, &rule_svc, &member_svc, &setting_store, &message_store);
    wechat_svc.module_svc = &module_svc;
    var mc_ctx = member_card.service.ReceiverCtx{ .io = std.testing.io, .member_svc = &mc_svc };
    try wechat_svc.registerReceiver(.{ .module_name = "member_card", .ctx = &mc_ctx, .handle = member_card.service.receiverHandle });

    const account_id = try account_svc.create(1, "会员卡测试号", "wechat");
    _ = try account_svc.upsertWechat(1, account_id, .{ .appid = "wx1", .secret = "s", .token = "tokm", .encoding_aes_key = "", .verified = false });
    _ = try module_svc.bind(1, account_id, "member_card", "active");
    _ = try mc_svc.createLevel(1, account_id, "普通会员", 1, 950, 100, 0);

    const token = "tokm";
    var ts_buf: [16]u8 = undefined;
    const ts = try std.fmt.bufPrint(&ts_buf, "{d}", .{zigmodu.time.wallClockSeconds(std.testing.io)});
    const nonce = "nm";
    const sig = try zwechat.util.signature.signature(allocator, &[_][]const u8{ token, ts, nonce });
    defer allocator.free(sig);

    // 「办卡」→ 成功。
    const open_xml = "<xml><ToUserName><![CDATA[gh]]></ToUserName><FromUserName><![CDATA[o_mc]]></FromUserName><CreateTime>1700000000</CreateTime><MsgType><![CDATA[text]]></MsgType><Content><![CDATA[办卡]]></Content></xml>";
    const r1 = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, open_xml);
    defer allocator.free(r1);
    try std.testing.expect(std.mem.indexOf(u8, r1, "办卡成功") != null);

    // 「查卡」→ 等级 + 积分 + 折扣。
    const view_xml = "<xml><ToUserName><![CDATA[gh]]></ToUserName><FromUserName><![CDATA[o_mc]]></FromUserName><CreateTime>1700000000</CreateTime><MsgType><![CDATA[text]]></MsgType><Content><![CDATA[查卡]]></Content></xml>";
    const r2 = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, view_xml);
    defer allocator.free(r2);
    try std.testing.expect(std.mem.indexOf(u8, r2, "普通会员") != null);
    try std.testing.expect(std.mem.indexOf(u8, r2, "积分") != null);
    try std.testing.expect(std.mem.indexOf(u8, r2, "9.50 折") != null);

    // 再「办卡」→ 已办过。
    const r3 = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, open_xml);
    defer allocator.free(r3);
    try std.testing.expect(std.mem.indexOf(u8, r3, "已经办过") != null);
}

test "distribution: join/3-level commission/withdraw lifecycle" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = distribution.persistence.DistributionStore.init(allocator, env.client);
    var svc = distribution.service.DistributionService.init(allocator, std.testing.io, &store);

    // 三级链：A(顶) ← B(中) ← C(买家分销员)。
    try svc.becomeDistributor(1, 9, "o_A", "");
    try svc.becomeDistributor(1, 9, "o_B", "o_A");
    try svc.becomeDistributor(1, 9, "o_C", "o_B");

    // 重复加盟 → AlreadyDistributor。
    try std.testing.expectError(error.AlreadyDistributor, svc.becomeDistributor(1, 9, "o_B", ""));
    // 上级无效 → InvalidParent（自己不能做自己上级）。
    try std.testing.expectError(error.InvalidParent, svc.becomeDistributor(1, 9, "o_X", "o_X"));
    try std.testing.expectError(error.InvalidParent, svc.becomeDistributor(1, 9, "o_X", "o_NotFound"));

    // C 消费 10000 分 → 一级上级 B 得 10%（1000）、二级上级 A 得 5%（500）。
    const count = try svc.distribute(1, 9, "o_C", 10000);
    try std.testing.expectEqual(@as(usize, 2), count);

    const a = (try svc.getDistributor(1, 9, "o_A")).?;
    defer a.free(allocator);
    const b = (try svc.getDistributor(1, 9, "o_B")).?;
    defer b.free(allocator);
    const c = (try svc.getDistributor(1, 9, "o_C")).?;
    defer c.free(allocator);
    try std.testing.expectEqualStrings("500", a.commission_balance);
    try std.testing.expectEqualStrings("1000", b.commission_balance);
    try std.testing.expectEqualStrings("0", c.commission_balance);

    // B 提现 700 → 余额 300；超额提现拒绝。
    try svc.withdraw(1, 9, "o_B", 700);
    const b2 = (try svc.getDistributor(1, 9, "o_B")).?;
    defer b2.free(allocator);
    try std.testing.expectEqualStrings("300", b2.commission_balance);
    try std.testing.expectError(error.InsufficientBalance, svc.withdraw(1, 9, "o_B", 400));
}

test "distribution: module receiver handles 加盟 + 分销" {
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
    var dist_store = distribution.persistence.DistributionStore.init(allocator, env.client);
    var dist_svc = distribution.service.DistributionService.init(allocator, std.testing.io, &dist_store);

    var wechat_svc = message.service.WechatService.init(allocator, std.testing.io, &account_svc, &rule_svc, &member_svc, &setting_store, &message_store);
    wechat_svc.module_svc = &module_svc;
    var dist_ctx = distribution.service.ReceiverCtx{ .io = std.testing.io, .dist_svc = &dist_svc };
    try wechat_svc.registerReceiver(.{ .module_name = "distribution", .ctx = &dist_ctx, .handle = distribution.service.receiverHandle });

    const account_id = try account_svc.create(1, "分销测试号", "wechat");
    _ = try account_svc.upsertWechat(1, account_id, .{ .appid = "wx1", .secret = "s", .token = "tokd", .encoding_aes_key = "", .verified = false });
    _ = try module_svc.bind(1, account_id, "distribution", "active");

    const token = "tokd";
    var ts_buf: [16]u8 = undefined;
    const ts = try std.fmt.bufPrint(&ts_buf, "{d}", .{zigmodu.time.wallClockSeconds(std.testing.io)});
    const nonce = "nd";
    const sig = try zwechat.util.signature.signature(allocator, &[_][]const u8{ token, ts, nonce });
    defer allocator.free(sig);

    // 「加盟」→ 成功。
    const join_xml = "<xml><ToUserName><![CDATA[gh]]></ToUserName><FromUserName><![CDATA[o_d]]></FromUserName><CreateTime>1700000000</CreateTime><MsgType><![CDATA[text]]></MsgType><Content><![CDATA[加盟]]></Content></xml>";
    const r1 = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, join_xml);
    defer allocator.free(r1);
    try std.testing.expect(std.mem.indexOf(u8, r1, "加盟成功") != null);

    // 「分销」→ 佣金余额 0.00 元。
    const view_xml = "<xml><ToUserName><![CDATA[gh]]></ToUserName><FromUserName><![CDATA[o_d]]></FromUserName><CreateTime>1700000000</CreateTime><MsgType><![CDATA[text]]></MsgType><Content><![CDATA[分销]]></Content></xml>";
    const r2 = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, view_xml);
    defer allocator.free(r2);
    try std.testing.expect(std.mem.indexOf(u8, r2, "佣金余额") != null);
    try std.testing.expect(std.mem.indexOf(u8, r2, "0.00 元") != null);

    // 再「加盟」→ 已是分销员。
    const r3 = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, join_xml);
    defer allocator.free(r3);
    try std.testing.expect(std.mem.indexOf(u8, r3, "已经是分销员") != null);
}
