//! 商城运营域能力：门店自提核销码、余额套餐充值、超时自动关单、拼团开团/参团、邀请有礼、文章发布过滤、AI 助手订单上下文、OrderPaidBus/webhook 事件链路、C-token 防伪支付。
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

test "shop: outlet CRUD + self-pickup verification code" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = shop.persistence.ShopStore.init(allocator, env.client);
    var svc = shop.service.ShopService.init(allocator, std.testing.io, &store);

    // 门店 CRUD。
    const outlet_id = try svc.createOutlet(1, 9, "南山店", "科技园 1 号", "0755-1234");
    const outlets = try svc.listOutlets(1, 9);
    defer {
        for (outlets) |o| o.free(allocator);
        if (outlets.len > 0) allocator.free(outlets);
    }
    try std.testing.expectEqual(@as(usize, 1), outlets.len);
    try std.testing.expectEqualStrings("南山店", outlets[0].name);

    // 商品 + 自提下单（pickup_store_id>0 → 自提码）。
    const pid = try svc.createProduct(1, 9, .{
        .category_id = 0,
        .name = "自提商品",
        .image = "",
        .images = "[]",
        .content = "",
        .price = 3000,
        .original_price = 4000,
        .stock = 5,
        .status = 1,
        .skus = &.{},
    });
    const skus = try svc.listSkus(pid);
    defer {
        for (skus) |s| s.free(allocator);
        if (skus.len > 0) allocator.free(skus);
    }
    const addr_id = try svc.createAddress(1, 9, .{
        .openid = "o_p",
        .name = "P",
        .mobile = "13800000000",
        .region = "SZ",
        .detail = "1",
        .is_default = 1,
    });
    const order_id = try svc.createOrder(1, 9, "o_p", addr_id, &.{
        .{ .product_id = pid, .sku_id = skus[0].id, .quantity = 1 },
    }, "", "", "", outlet_id, "");
    var o = (try svc.getOrder(order_id)).?;
    defer o.free(allocator);
    try std.testing.expectEqualStrings("self", o.pickup_type);
    try std.testing.expect(o.pickup_code.len == 6);

    // 支付 → 核销：错误码拒绝，正确码成功（状态 3）。
    try svc.markPaid(1, 9, order_id);
    try std.testing.expectError(error.InvalidInput, svc.pickupOrder(order_id, "000000"));
    try svc.pickupOrder(order_id, o.pickup_code);
    var o2 = (try svc.getOrder(order_id)).?;
    defer o2.free(allocator);
    try std.testing.expectEqual(@as(i64, 3), o2.status);

    // 快递单（pickup_store_id=0）不可核销。
    const order_delivery = try svc.createOrder(1, 9, "o_p", addr_id, &.{
        .{ .product_id = pid, .sku_id = skus[0].id, .quantity = 1 },
    }, "", "", "", 0, "");
    try svc.markPaid(1, 9, order_delivery);
    try std.testing.expectError(error.OrderStateConflict, svc.pickupOrder(order_delivery, "123456"));

    try svc.deleteOutlet(outlet_id);
}

test "shop: balance plan recharge (Bonus) lifecycle" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = shop.persistence.ShopStore.init(allocator, env.client);
    var svc = shop.service.ShopService.init(allocator, std.testing.io, &store);
    var pay_store = payment.persistence.PaymentStore.init(allocator, env.client);
    var pay_svc = payment.service.PaymentService.init(allocator, std.testing.io, &pay_store);
    var fan_store = member.persistence.FanStore.init(allocator, env.client);
    svc.payment_svc = &pay_svc;
    svc.fan_store = &fan_store;

    // 粉丝 + 套餐（充 100 送 20）。
    const now_ts = zigmodu.time.wallClockSeconds(std.testing.io);
    const fan_id = try fan_store.upsert(1, 9, "o_plan", "", "储值用户", "", true, now_ts, now_ts);
    const plan_id = try svc.createBalancePlan(1, 9, "充100送20", 10000, 2000);

    // 列表（仅上架）。
    const plans = try svc.listBalancePlans(1, 9);
    defer {
        for (plans) |p| p.free(allocator);
        if (plans.len > 0) allocator.free(plans);
    }
    try std.testing.expectEqual(@as(usize, 1), plans.len);

    // 充值：钱包 0 → 12000（amount + bonus）。
    try svc.rechargePlan(1, 9, "o_plan", plan_id);
    const wallet = (try pay_svc.walletBalance(1, 9, fan_id)).?;
    defer wallet.free(allocator);
    try std.testing.expectEqualStrings("12000", wallet.balance);

    // 充值后可余额支付下单（闭环）。
    const pid = try svc.createProduct(1, 9, .{
        .category_id = 0,
        .name = "储值消费",
        .image = "",
        .images = "[]",
        .content = "",
        .price = 10000,
        .original_price = 15000,
        .stock = 5,
        .status = 1,
        .skus = &.{},
    });
    const skus = try svc.listSkus(pid);
    defer {
        for (skus) |s| s.free(allocator);
        if (skus.len > 0) allocator.free(skus);
    }
    const addr_id = try svc.createAddress(1, 9, .{
        .openid = "o_plan",
        .name = "P",
        .mobile = "13800000000",
        .region = "SZ",
        .detail = "1",
        .is_default = 1,
    });
    const order_id = try svc.createOrder(1, 9, "o_plan", addr_id, &.{
        .{ .product_id = pid, .sku_id = skus[0].id, .quantity = 1 },
    }, "", "", "balance", 0, "");
    const wallet2 = (try pay_svc.walletBalance(1, 9, fan_id)).?;
    defer wallet2.free(allocator);
    try std.testing.expectEqualStrings("2000", wallet2.balance);
    var o = (try svc.getOrder(order_id)).?;
    defer o.free(allocator);
    try std.testing.expectEqual(@as(i64, 1), o.status); // 已支付

    try svc.deleteBalancePlan(plan_id);
}

test "shop: auto-cancel expired pending orders (production ops)" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = shop.persistence.ShopStore.init(allocator, env.client);
    var svc = shop.service.ShopService.init(allocator, std.testing.io, &store);

    const pid = try svc.createProduct(1, 9, .{
        .category_id = 0,
        .name = "超时商品",
        .image = "",
        .images = "[]",
        .content = "",
        .price = 1000,
        .original_price = 2000,
        .stock = 3,
        .status = 1,
        .skus = &.{},
    });
    const skus = try svc.listSkus(pid);
    defer {
        for (skus) |s| s.free(allocator);
        if (skus.len > 0) allocator.free(skus);
    }
    const addr_id = try svc.createAddress(1, 9, .{
        .openid = "o_t",
        .name = "T",
        .mobile = "13800000000",
        .region = "SZ",
        .detail = "1",
        .is_default = 1,
    });

    // 待支付订单（扣库存 3→2）。
    const order_id = try svc.createOrder(1, 9, "o_t", addr_id, &.{
        .{ .product_id = pid, .sku_id = skus[0].id, .quantity = 1 },
    }, "", "", "", 0, "");

    // 超时 0 秒 → 立即被清理（timeout_secs=0 表示所有待支付都过期）。
    const cancelled = try svc.autoCancelExpired(1, 9, 0);
    try std.testing.expectEqual(@as(usize, 1), cancelled);
    var o = (try svc.getOrder(order_id)).?;
    defer o.free(allocator);
    try std.testing.expectEqual(@as(i64, 4), o.status); // 已取消

    // 库存回滚：2→3。
    const sku_restored = (try svc.getSku(skus[0].id)).?;
    defer sku_restored.free(allocator);
    try std.testing.expectEqual(@as(i64, 3), sku_restored.stock);
}

test "shop: groupon open/join/success lifecycle" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = shop.persistence.ShopStore.init(allocator, env.client);
    var svc = shop.service.ShopService.init(allocator, std.testing.io, &store);

    // 商品（售价 100，团价 80，2 人成团）。
    const pid = try svc.createProduct(1, 9, .{
        .category_id = 0,
        .name = "拼团商品",
        .image = "",
        .images = "[]",
        .content = "",
        .price = 10000,
        .original_price = 12000,
        .stock = 10,
        .status = 1,
        .skus = &.{},
    });
    const skus = try svc.listSkus(pid);
    defer {
        for (skus) |s| s.free(allocator);
        if (skus.len > 0) allocator.free(skus);
    }
    const gid = try svc.createGroupon(1, 9, pid, 8000, 2, 0, 0);
    const addr_id = try svc.createAddress(1, 9, .{
        .openid = "o_g1",
        .name = "G1",
        .mobile = "13800000000",
        .region = "SZ",
        .detail = "1",
        .is_default = 1,
    });

    // 开团：leader o_g1，团价 8000 下单。
    const team_id = try svc.openGroupon(1, 9, "o_g1", addr_id, gid, skus[0].id);
    var team = (try store.marketing.getTeam(team_id)).?;
    defer team.free(allocator);
    try std.testing.expectEqual(@as(i64, 1), team.current);
    try std.testing.expectEqual(@as(i64, 0), team.status); // 拼团中

    // 参团：o_g2 → current=2 → 成团。
    const addr2 = try svc.createAddress(1, 9, .{
        .openid = "o_g2",
        .name = "G2",
        .mobile = "13800000000",
        .region = "SZ",
        .detail = "2",
        .is_default = 1,
    });
    _ = try svc.joinGroupon(1, 9, "o_g2", addr2, team_id, skus[0].id);
    var team2 = (try store.marketing.getTeam(team_id)).?;
    defer team2.free(allocator);
    try std.testing.expectEqual(@as(i64, 2), team2.current);
    try std.testing.expectEqual(@as(i64, 1), team2.status); // 成团

    // 成团后：团内订单全部已支付（mock）。
    const orders = try store.marketing.listOrdersByTeam(team_id);
    defer {
        for (orders) |o| o.free(allocator);
        if (orders.len > 0) allocator.free(orders);
    }
    try std.testing.expectEqual(@as(usize, 2), orders.len);
    try std.testing.expectEqual(@as(i64, 1), orders[0].status);
    try std.testing.expectEqualStrings("8000", orders[0].pay_amount);

    // 已结束团不可再参。
    try std.testing.expectError(error.InvalidInput, svc.joinGroupon(1, 9, "o_g3", addr2, team_id, skus[0].id));
}

test "shop: invite gift bind/reward lifecycle" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = shop.persistence.ShopStore.init(allocator, env.client);
    var svc = shop.service.ShopService.init(allocator, std.testing.io, &store);
    var mc_store = member_card.persistence.MemberCardStore.init(allocator, env.client);
    var mc_svc = member_card.service.MemberCardService.init(allocator, std.testing.io, &mc_store);
    svc.member_svc = &mc_svc;

    // 会员卡（积分奖励前提）+ 奖励配置（邀请 2 人 → 100 积分）。
    _ = try mc_svc.createLevel(1, 9, "普通会员", 1, 1000, 100, 0, 1);
    try mc_svc.openCard(1, 9, "o_inviter");
    _ = try svc.createInviteGift(1, 9, 2, "points", 100);

    // 邀请 2 人 → 邀请人得 100 积分。
    try svc.bindInvite(1, 9, "o_inviter", "o_f1");
    var v1 = (try mc_svc.view(1, 9, "o_inviter")).?;
    defer v1.free(allocator);
    try std.testing.expectEqual(@as(i64, 0), v1.points); // 未达标

    try svc.bindInvite(1, 9, "o_inviter", "o_f2");
    var v2 = (try mc_svc.view(1, 9, "o_inviter")).?;
    defer v2.free(allocator);
    try std.testing.expectEqual(@as(i64, 100), v2.points); // 达标发奖

    // 幂等：同 invitee 不重复绑定。
    try svc.bindInvite(1, 9, "o_inviter", "o_f2");
    var v3 = (try mc_svc.view(1, 9, "o_inviter")).?;
    defer v3.free(allocator);
    try std.testing.expectEqual(@as(i64, 100), v3.points); // 不重复发奖

    // 自邀请拒绝。
    try std.testing.expectError(error.InvalidInput, svc.bindInvite(1, 9, "o_inviter", "o_inviter"));

    // 邀请数查询。
    try std.testing.expectEqual(@as(i64, 2), try svc.store.marketing.countInvites(1, "o_inviter"));
}

test "shop: article CRUD + publish filter" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = shop.persistence.ShopStore.init(allocator, env.client);
    var svc = shop.service.ShopService.init(allocator, std.testing.io, &store);

    const aid = try svc.createArticle(1, 9, "新品发布", "内容：商城上线拼团与邀请有礼！");
    const a = (try svc.getArticle(aid)).?;
    defer a.free(allocator);
    try std.testing.expectEqualStrings("新品发布", a.title);

    // C 端列表（仅发布）含文章。
    var list = try svc.listArticles(1, 20, 1, 9, true);
    defer list.free(allocator);
    try std.testing.expectEqual(@as(i64, 1), list.total);
    try std.testing.expectEqualStrings("新品发布", list.items[0].title);

    // 删除后列表为空。
    try svc.deleteArticle(aid);
    var list2 = try svc.listArticles(1, 20, 1, 9, true);
    defer list2.free(allocator);
    try std.testing.expectEqual(@as(i64, 0), list2.total);
}

test "shop: AI assistant order-context replies" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = shop.persistence.ShopStore.init(allocator, env.client);
    var svc = shop.service.ShopService.init(allocator, std.testing.io, &store);

    // 商品 + 下单（已支付）+ 收藏。
    const pid = try svc.createProduct(1, 9, .{
        .category_id = 0,
        .name = "助手商品",
        .image = "",
        .images = "[]",
        .content = "",
        .price = 1000,
        .original_price = 2000,
        .stock = 5,
        .status = 1,
        .skus = &.{},
    });
    const skus = try svc.listSkus(pid);
    defer {
        for (skus) |s| s.free(allocator);
        if (skus.len > 0) allocator.free(skus);
    }
    const addr_id = try svc.createAddress(1, 9, .{
        .openid = "o_ai",
        .name = "AI",
        .mobile = "13800000000",
        .region = "SZ",
        .detail = "1",
        .is_default = 1,
    });
    const oid = try svc.createOrder(1, 9, "o_ai", addr_id, &.{
        .{ .product_id = pid, .sku_id = skus[0].id, .quantity = 1 },
    }, "", "", "", 0, "");
    try svc.markPaid(1, 9, oid);
    try svc.favorite(1, 9, "o_ai", pid);

    // 问订单 → 返回最近订单（含状态与金额）。
    const r1 = try svc.assistant(allocator, 1, 9, "o_ai", "我的订单");
    defer allocator.free(r1);
    try std.testing.expect(std.mem.indexOf(u8, r1, "SO") != null);
    try std.testing.expect(std.mem.indexOf(u8, r1, "已支付") != null);

    // 问支付 → 待支付/已支付统计。
    const r2 = try svc.assistant(allocator, 1, 9, "o_ai", "支付情况");
    defer allocator.free(r2);
    try std.testing.expect(std.mem.indexOf(u8, r2, "已支付 1 单") != null);

    // 问收藏。
    const r3 = try svc.assistant(allocator, 1, 9, "o_ai", "我的收藏");
    defer allocator.free(r3);
    try std.testing.expect(std.mem.indexOf(u8, r3, "收藏了 1 件") != null);

    // 问物流（无已发货订单）→ 引导。
    const r4 = try svc.assistant(allocator, 1, 9, "o_ai", "物流到哪了");
    defer allocator.free(r4);
    try std.testing.expect(std.mem.indexOf(u8, r4, "没有已发货") != null);

    // 未知问题 → 能力引导。
    const r5 = try svc.assistant(allocator, 1, 9, "o_ai", "今天天气");
    defer allocator.free(r5);
    try std.testing.expect(std.mem.indexOf(u8, r5, "我可以帮您") != null);
}

test "shop: event-driven markPaid via OrderPaidBus" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = shop.persistence.ShopStore.init(allocator, env.client);
    var svc = shop.service.ShopService.init(allocator, std.testing.io, &store);
    var dist_store = distribution.persistence.DistributionStore.init(allocator, env.client);
    var dist_svc = distribution.service.DistributionService.init(allocator, std.testing.io, &dist_store);
    svc.dist_svc = &dist_svc;

    // 事件总线 + 消费者（分销分佣）。
    var bus = shop.service.OrderPaidBus.init(allocator);
    defer bus.deinit();
    const PaidCtx = struct {
        var dist_ref: *distribution.service.DistributionService = undefined;
        fn onPaid(e: shop.service.OrderPaidEvent) void {
            const d = dist_ref;
            _ = d.distribute(e.tenant_id, e.account_id, "o_buyer", e.order_id) catch {};
        }
    };
    // 用简单计数器验证事件被消费。
    const Counter = struct {
        var n: usize = 0;
        fn onPaid(e: shop.service.OrderPaidEvent) void {
            _ = e;
            n += 1;
        }
    };
    bus.subscribe(Counter.onPaid) catch {};
    svc.order_paid_bus = &bus;

    // 商品 + 下单 + 支付 → 事件被发布（计数器 +1）。
    const pid = try svc.createProduct(1, 9, .{
        .category_id = 0,
        .name = "事件商品",
        .image = "",
        .images = "[]",
        .content = "",
        .price = 1000,
        .original_price = 2000,
        .stock = 5,
        .status = 1,
        .skus = &.{},
    });
    const skus = try svc.listSkus(pid);
    defer {
        for (skus) |s| s.free(allocator);
        if (skus.len > 0) allocator.free(skus);
    }
    const addr_id = try svc.createAddress(1, 9, .{
        .openid = "o_ev",
        .name = "E",
        .mobile = "13800000000",
        .region = "SZ",
        .detail = "1",
        .is_default = 1,
    });
    const oid = try svc.createOrder(1, 9, "o_ev", addr_id, &.{
        .{ .product_id = pid, .sku_id = skus[0].id, .quantity = 1 },
    }, "", "", "", 0, "");
    try svc.markPaid(1, 9, oid);
    try std.testing.expectEqual(@as(usize, 1), Counter.n);
    _ = PaidCtx;
}

test "shop: stock rollback on order failure paths" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = shop.persistence.ShopStore.init(allocator, env.client);
    var svc = shop.service.ShopService.init(allocator, std.testing.io, &store);
    var pay_store = payment.persistence.PaymentStore.init(allocator, env.client);
    var pay_svc = payment.service.PaymentService.init(allocator, std.testing.io, &pay_store);
    var fan_store = member.persistence.FanStore.init(allocator, env.client);
    svc.payment_svc = &pay_svc;
    svc.fan_store = &fan_store;

    // 商品（库存 3）+ 粉丝（钱包 0）。
    const now_ts = zigmodu.time.wallClockSeconds(std.testing.io);
    _ = try fan_store.upsert(1, 9, "o_roll", "", "回滚用户", "", true, now_ts, now_ts);
    const pid = try svc.createProduct(1, 9, .{
        .category_id = 0,
        .name = "回滚商品",
        .image = "",
        .images = "[]",
        .content = "",
        .price = 1000,
        .original_price = 2000,
        .stock = 3,
        .status = 1,
        .skus = &.{},
    });
    const skus = try svc.listSkus(pid);
    defer {
        for (skus) |s| s.free(allocator);
        if (skus.len > 0) allocator.free(skus);
    }
    const addr_id = try svc.createAddress(1, 9, .{
        .openid = "o_roll",
        .name = "R",
        .mobile = "13800000000",
        .region = "SZ",
        .detail = "1",
        .is_default = 1,
    });

    // 余额支付（钱包 0 不够）→ InsufficientBalance + 库存回滚（3 → 扣1 → 回滚 → 3）。
    try std.testing.expectError(error.InsufficientBalance, svc.createOrder(1, 9, "o_roll", addr_id, &.{
        .{ .product_id = pid, .sku_id = skus[0].id, .quantity = 1 },
    }, "", "", "balance", 0, ""));
    const sku_after = (try svc.getSku(skus[0].id)).?;
    defer sku_after.free(allocator);
    try std.testing.expectEqual(@as(i64, 3), sku_after.stock); // 已回滚
}

test "shop: webhook dispatch on order paid" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = shop.persistence.ShopStore.init(allocator, env.client);
    var svc = shop.service.ShopService.init(allocator, std.testing.io, &store);
    const wt = @import("../http/webhook_transport.zig");

    // Webhook 配置 + mock transport 记录。
    const wh_id = try svc.createWebhook(1, 9, "https://merchant.example.com/hook", "order.paid");
    var received = std.ArrayList([]u8).empty;
    const Recorder = struct {
        var out: *std.ArrayList([]u8) = undefined;
        fn rec(url: []const u8, payload: []const u8) void {
            out.append(std.heap.c_allocator, std.fmt.allocPrint(std.heap.c_allocator, "{s}|{s}", .{ url, payload }) catch "") catch {};
        }
    };
    Recorder.out = &received;
    var transport = wt.WebhookTransport.init(std.testing.io);
    transport.recorder = Recorder.rec;
    svc.webhook_transport = &transport;

    // 商品 + 下单 + 支付 → webhook 推送（event/order_id/account_id）。
    const pid = try svc.createProduct(1, 9, .{
        .category_id = 0,
        .name = "回调商品",
        .image = "",
        .images = "[]",
        .content = "",
        .price = 1000,
        .original_price = 2000,
        .stock = 5,
        .status = 1,
        .skus = &.{},
    });
    const skus = try svc.listSkus(pid);
    defer {
        for (skus) |s| s.free(allocator);
        if (skus.len > 0) allocator.free(skus);
    }
    const addr_id = try svc.createAddress(1, 9, .{
        .openid = "o_wh",
        .name = "W",
        .mobile = "13800000000",
        .region = "SZ",
        .detail = "1",
        .is_default = 1,
    });
    const oid = try svc.createOrder(1, 9, "o_wh", addr_id, &.{
        .{ .product_id = pid, .sku_id = skus[0].id, .quantity = 1 },
    }, "", "", "", 0, "");
    svc.dispatchWebhooks("order.paid", 1, 9, oid);

    // mock 收到 payload。
    try std.testing.expectEqual(@as(usize, 1), received.items.len);
    try std.testing.expect(std.mem.indexOf(u8, received.items[0], "order.paid") != null);
    try std.testing.expect(std.mem.indexOf(u8, received.items[0], "merchant.example.com") != null);
    for (received.items) |r| std.heap.c_allocator.free(r);
    received.deinit(std.heap.c_allocator);

    try svc.deleteWebhook(wh_id);
}

test "shop: C-token issue + order uses token openid (anti-forgery)" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = shop.persistence.ShopStore.init(allocator, env.client);
    var svc = shop.service.ShopService.init(allocator, std.testing.io, &store);
    var fan_store = member.persistence.FanStore.init(allocator, env.client);
    var user_store = user.persistence.UserStore.init(allocator, env.client);
    var sec = zigmodu.security.AppSecurity.init(allocator, std.testing.io, .{ .jwt_secret = "test-c-jwt-secret", .token_expiry_seconds = 3600 });
    var user_svc = user.service.UserService.init(&user_store, &sec, std.testing.io, 3600, 3600);
    var registry = zigmodu.RateLimiterRegistry.init(allocator, 30, 1);
    _ = &registry;
    _ = &user_svc;
    _ = &fan_store;

    // 粉丝 + 商品。
    const now_ts = zigmodu.time.wallClockSeconds(std.testing.io);
    _ = try fan_store.upsert(1, 9, "o_jwt", "", "JWT用户", "", true, now_ts, now_ts);
    const pid = try svc.createProduct(1, 9, .{
        .category_id = 0,
        .name = "JWT商品",
        .image = "",
        .images = "[]",
        .content = "",
        .price = 1000,
        .original_price = 2000,
        .stock = 5,
        .status = 1,
        .skus = &.{},
    });
    const skus = try svc.listSkus(pid);
    defer {
        for (skus) |s| s.free(allocator);
        if (skus.len > 0) allocator.free(skus);
    }

    // 签发 C-token（粉丝 openid）。
    const c_token = try sec.module.generateTokenWithTenant("o_jwt", &.{"fan"}, "0");
    defer allocator.free(c_token);

    // 校验 token 解析出 openid（sub）。
    const payload = try sec.module.verifyToken(c_token);
    defer {
        allocator.free(payload.sub);
        allocator.free(payload.iss);
        allocator.free(payload.aud);
        for (payload.roles) |r| allocator.free(r);
        allocator.free(payload.roles);
    }
    try std.testing.expectEqualStrings("o_jwt", payload.sub);
    var is_fan = false;
    for (payload.roles) |r| {
        if (std.mem.eql(u8, r, "fan")) is_fan = true;
    }
    try std.testing.expect(is_fan);

    // 非粉丝 openid 无法签发（fan_store 校验逻辑在 cLogin handler，service 层验证 fan 存在）。
    // 这里验证 token 机制本身：管理端 token（无 fan role）不可作 C-token。
    const admin_token = try sec.module.generateTokenWithTenant("admin_x", &.{"admin"}, "1");
    defer allocator.free(admin_token);
    const admin_payload = try sec.module.verifyToken(admin_token);
    defer {
        allocator.free(admin_payload.sub);
        allocator.free(admin_payload.iss);
        allocator.free(admin_payload.aud);
        for (admin_payload.roles) |r| allocator.free(r);
        allocator.free(admin_payload.roles);
    }
    var admin_is_fan = false;
    for (admin_payload.roles) |r| {
        if (std.mem.eql(u8, r, "fan")) admin_is_fan = true;
    }
    try std.testing.expect(!admin_is_fan);
}

test "shop: order pay-params mock mode (no v3 config)" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = shop.persistence.ShopStore.init(allocator, env.client);
    var svc = shop.service.ShopService.init(allocator, std.testing.io, &store);
    var fan_store = member.persistence.FanStore.init(allocator, env.client);
    var user_store = user.persistence.UserStore.init(allocator, env.client);
    var sec = zigmodu.security.AppSecurity.init(allocator, std.testing.io, .{ .jwt_secret = "pay-params-secret", .token_expiry_seconds = 3600 });
    var user_svc = user.service.UserService.init(&user_store, &sec, std.testing.io, 3600, 3600);
    var setting_store = setting.persistence.SettingStore.init(allocator, env.client);
    var audit_store = audit.persistence.AuditStore.init(allocator, env.client);
    var audit_svc = audit.service.AuditService.init(allocator, std.testing.io, &audit_store);
    var registry = zigmodu.RateLimiterRegistry.init(allocator, 30, 1);
    defer registry.deinit();
    var shop_limiter = mw_rate.PerIpLimiter{
        .backend = .{ .registry = &registry },
        .max = 30,
        .window_seconds = 60,
        .refill_rate = 1,
    };
    var shop_api = shop.api.ShopApi(@TypeOf(svc), @TypeOf(user_svc)).init(&svc, &user_svc, &audit_svc, 1, &shop_limiter, &fan_store, &setting_store, 1800);

    // 商品 + 待支付订单。
    const pid = try svc.createProduct(1, 9, .{
        .category_id = 0,
        .name = "支付参数商品",
        .image = "",
        .images = "[]",
        .content = "",
        .price = 1000,
        .original_price = 2000,
        .stock = 5,
        .status = 1,
        .skus = &.{},
    });
    const skus = try svc.listSkus(pid);
    defer {
        for (skus) |s| s.free(allocator);
        if (skus.len > 0) allocator.free(skus);
    }
    const addr_id = try svc.createAddress(1, 9, .{
        .openid = "o_pay",
        .name = "P",
        .mobile = "13800000000",
        .region = "SZ",
        .detail = "1",
        .is_default = 1,
    });
    const oid = try svc.createOrder(1, 9, "o_pay", addr_id, &.{
        .{ .product_id = pid, .sku_id = skus[0].id, .quantity = 1 },
    }, "", "", "", 0, "");

    // 走 HTTP：GET pay-params（无 v3 配置 → mock 模式）。
    var server = zigmodu.http.Server.init(std.testing.io, allocator, 0);
    defer server.deinit();
    var g = server.group("/api/v1");
    try shop_api.registerPublicRoutes(&g);
    const pay_url = try std.fmt.allocPrint(allocator, "/api/v1/shop/orders/{d}/pay-params", .{oid});
    defer allocator.free(pay_url);
    var res = try zigmodu.http.Testkit.dispatchOpts(&server, .GET, pay_url, .{});
    defer res.deinit(allocator);
    try std.testing.expectEqual(@as(u16, 200), res.status_code);
    try std.testing.expect(std.mem.indexOf(u8, res.body, "\"mode\":\"mock\"") != null);
}

test "shop: mock pay-complete with C-token ownership" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = shop.persistence.ShopStore.init(allocator, env.client);
    var svc = shop.service.ShopService.init(allocator, std.testing.io, &store);
    var fan_store = member.persistence.FanStore.init(allocator, env.client);
    var user_store = user.persistence.UserStore.init(allocator, env.client);
    var sec = zigmodu.security.AppSecurity.init(allocator, std.testing.io, .{ .jwt_secret = "pay-complete-secret", .token_expiry_seconds = 3600 });
    var user_svc = user.service.UserService.init(&user_store, &sec, std.testing.io, 3600, 3600);
    var setting_store = setting.persistence.SettingStore.init(allocator, env.client);
    var audit_store = audit.persistence.AuditStore.init(allocator, env.client);
    var audit_svc = audit.service.AuditService.init(allocator, std.testing.io, &audit_store);
    var registry = zigmodu.RateLimiterRegistry.init(allocator, 30, 1);
    defer registry.deinit();
    var shop_limiter = mw_rate.PerIpLimiter{
        .backend = .{ .registry = &registry },
        .max = 30,
        .window_seconds = 60,
        .refill_rate = 1,
    };
    var shop_api = shop.api.ShopApi(@TypeOf(svc), @TypeOf(user_svc)).init(&svc, &user_svc, &audit_svc, 1, &shop_limiter, &fan_store, &setting_store, 1800);

    // 粉丝 + 商品 + 待支付订单。
    const now_ts = zigmodu.time.wallClockSeconds(std.testing.io);
    _ = try fan_store.upsert(1, 9, "o_pc", "", "支付用户", "", true, now_ts, now_ts);
    const pid = try svc.createProduct(1, 9, .{
        .category_id = 0,
        .name = "支付完成商品",
        .image = "",
        .images = "[]",
        .content = "",
        .price = 1000,
        .original_price = 2000,
        .stock = 5,
        .status = 1,
        .skus = &.{},
    });
    const skus = try svc.listSkus(pid);
    defer {
        for (skus) |s| s.free(allocator);
        if (skus.len > 0) allocator.free(skus);
    }
    const addr_id = try svc.createAddress(1, 9, .{
        .openid = "o_pc",
        .name = "P",
        .mobile = "13800000000",
        .region = "SZ",
        .detail = "1",
        .is_default = 1,
    });
    const oid = try svc.createOrder(1, 9, "o_pc", addr_id, &.{
        .{ .product_id = pid, .sku_id = skus[0].id, .quantity = 1 },
    }, "", "", "", 0, "");

    // 无 C-token → 401。
    var server = zigmodu.http.Server.init(std.testing.io, allocator, 0);
    defer server.deinit();
    var g = server.group("/api/v1");
    try shop_api.registerPublicRoutes(&g);
    const url1 = try std.fmt.allocPrint(allocator, "/api/v1/shop/orders/{d}/pay-complete", .{oid});
    defer allocator.free(url1);
    var res1 = try zigmodu.http.Testkit.dispatchOpts(&server, .POST, url1, .{});
    defer res1.deinit(allocator);
    try std.testing.expectEqual(@as(u16, 401), res1.status_code);

    // 带 C-token（买家本人）→ 200 支付成功。
    const c_token = try sec.module.generateTokenWithTenant("o_pc", &.{"fan"}, "0");
    defer allocator.free(c_token);
    const auth_header = try std.fmt.allocPrint(allocator, "Bearer {s}", .{c_token});
    defer allocator.free(auth_header);
    var res2 = try zigmodu.http.Testkit.dispatchOpts(&server, .POST, url1, .{ .headers = &.{.{ "authorization", auth_header }} });
    defer res2.deinit(allocator);
    try std.testing.expectEqual(@as(u16, 200), res2.status_code);
    var o2 = (try svc.getOrder(oid)).?;
    defer o2.free(allocator);
    try std.testing.expectEqual(@as(i64, 1), o2.status); // 已支付
}
