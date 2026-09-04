//! 商城核心域：分类/商品/SKU 规格、购物车/地址/订单交易闭环、退款审核/评论、券抵扣+积分累加、取消幂等与库存回补、收藏与订单统计、余额支付。
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

test "shop: category CRUD + product lifecycle (Phase1)" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = shop.persistence.ShopStore.init(allocator, env.client);
    var svc = shop.service.ShopService.init(allocator, std.testing.io, &store);

    // 分类：创建两个 + 列表 + 删除。
    const cat_id = try svc.createCategory(1, 9, "数码", 0, 1);
    _ = try svc.createCategory(1, 9, "服饰", 0, 2);
    var cats = try svc.listCategories(1, 9);
    defer cats.free(allocator);
    try std.testing.expectEqual(@as(usize, 2), cats.items.len);

    // 商品（默认单 SKU）。
    const pid = try svc.createProduct(1, 9, .{
        .category_id = cat_id,
        .name = "蓝牙耳机",
        .image = "/img/x.png",
        .images = "[]",
        .content = "好耳机",
        .price = 9900,
        .original_price = 19900,
        .stock = 100,
        .status = 1,
        .skus = &.{},
    });
    const p = (try svc.getProduct(pid)).?;
    defer p.free(allocator);
    try std.testing.expectEqualStrings("蓝牙耳机", p.name);
    try std.testing.expectEqualStrings("9900", p.price);

    // 详情含默认 SKU。
    const skus = try svc.listSkus(pid);
    defer {
        for (skus) |s| s.free(allocator);
        if (skus.len > 0) allocator.free(skus);
    }
    try std.testing.expectEqual(@as(usize, 1), skus.len);
    try std.testing.expectEqualStrings("9900", skus[0].price);

    // C 端列表（仅上架）含商品。
    var list = try svc.listProducts(1, 20, 1, 9, 0, "", 1);
    defer list.free(allocator);
    try std.testing.expectEqual(@as(i64, 1), list.total);

    // 下架后 C 端不可见。
    _ = try svc.updateProduct(1, 9, pid, .{
        .category_id = cat_id,
        .name = "蓝牙耳机",
        .image = "/img/x.png",
        .images = "[]",
        .content = "",
        .price = 9900,
        .original_price = 19900,
        .stock = 100,
        .status = 0,
        .skus = &.{},
    });
    var list2 = try svc.listProducts(1, 20, 1, 9, 0, "", 1);
    defer list2.free(allocator);
    try std.testing.expectEqual(@as(i64, 0), list2.total);

    // 删除商品 + 分类。
    try svc.deleteProduct(pid);
    try std.testing.expect((try svc.getProduct(pid)) == null);
    try svc.deleteCategory(cat_id);
}

test "shop: product with multi-SKU specs" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = shop.persistence.ShopStore.init(allocator, env.client);
    var svc = shop.service.ShopService.init(allocator, std.testing.io, &store);

    const pid = try svc.createProduct(1, 9, .{
        .category_id = 0,
        .name = "定制T恤",
        .image = "",
        .images = "[]",
        .content = "",
        .price = 5900,
        .original_price = 9900,
        .stock = 200,
        .status = 1,
        .skus = &.{
            .{ .spec_json = "[{\"k\":\"颜色\",\"v\":\"红\"}]", .image = "", .price = 5900, .stock = 100 },
            .{ .spec_json = "[{\"k\":\"颜色\",\"v\":\"蓝\"}]", .image = "", .price = 6900, .stock = 100 },
        },
    });

    const skus = try svc.listSkus(pid);
    defer {
        for (skus) |s| s.free(allocator);
        if (skus.len > 0) allocator.free(skus);
    }
    try std.testing.expectEqual(@as(usize, 2), skus.len);
    try std.testing.expect(std.mem.indexOf(u8, skus[0].spec_json, "红") != null or std.mem.indexOf(u8, skus[1].spec_json, "红") != null);
}

test "shop: cart/address/order trade lifecycle (Phase2)" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = shop.persistence.ShopStore.init(allocator, env.client);
    var svc = shop.service.ShopService.init(allocator, std.testing.io, &store);

    // 商品 + 默认 SKU。
    const pid = try svc.createProduct(1, 9, .{
        .category_id = 0,
        .name = "测试商品",
        .image = "",
        .images = "[]",
        .content = "",
        .price = 5000,
        .original_price = 8000,
        .stock = 10,
        .status = 1,
        .skus = &.{},
    });
    const skus = try svc.listSkus(pid);
    defer {
        for (skus) |s| s.free(allocator);
        if (skus.len > 0) allocator.free(skus);
    }
    const sku_id = skus[0].id;

    // 购物车：加入 + 累加。
    const cart_id = try svc.addCart(1, 9, "o_buyer", pid, sku_id, 2);
    _ = try svc.addCart(1, 9, "o_buyer", pid, sku_id, 3);
    const carts = try svc.listCarts(1, "o_buyer");
    defer {
        for (carts) |c| c.free(allocator);
        if (carts.len > 0) allocator.free(carts);
    }
    try std.testing.expectEqual(@as(usize, 1), carts.len);
    try std.testing.expectEqual(@as(i64, 5), carts[0].quantity);

    // 地址（默认）。
    const addr_id = try svc.createAddress(1, 9, .{
        .openid = "o_buyer",
        .name = "张三",
        .mobile = "13800138000",
        .region = "广东省深圳市",
        .detail = "科技园 1 号",
        .is_default = 1,
    });
    const addrs = try svc.listAddresses(1, "o_buyer");
    defer {
        for (addrs) |a| a.free(allocator);
        if (addrs.len > 0) allocator.free(addrs);
    }
    try std.testing.expectEqual(@as(usize, 1), addrs.len);

    // 下单：数量 5 → 扣库存 10→5；金额 5000*5。
    const order_id = try svc.createOrder(1, 9, "o_buyer", addr_id, &.{
        .{ .product_id = pid, .sku_id = sku_id, .quantity = 5 },
    }, "", "", "", 0, "");
    var o = (try svc.getOrder(order_id)).?;
    defer o.free(allocator);
    try std.testing.expectEqualStrings("25000", o.total_amount);
    try std.testing.expectEqual(@as(i64, 0), o.status);

    // 库存已扣：SKU stock 10-5=5。
    const sku2 = (try svc.getSku(sku_id)).?;
    defer sku2.free(allocator);
    try std.testing.expectEqual(@as(i64, 5), sku2.stock);

    // 明细。
    const ops = try svc.listOrderProducts(order_id);
    defer {
        for (ops) |op| op.free(allocator);
        if (ops.len > 0) allocator.free(ops);
    }
    try std.testing.expectEqual(@as(usize, 1), ops.len);
    try std.testing.expectEqualStrings("测试商品", ops[0].name);

    // 超库存下单 → OutOfStock。
    try std.testing.expectError(error.OutOfStock, svc.createOrder(1, 9, "o_buyer", addr_id, &.{
        .{ .product_id = pid, .sku_id = sku_id, .quantity = 99 },
    }, "", "", "", 0, ""));

    // 状态流转：支付 → 发货 → 确认收货；待支付取消 → 冲突。
    try svc.markPaid(1, 9, order_id);
    try svc.shipOrder(order_id, "顺丰", "SF123");
    try svc.confirmOrder(order_id);
    var o2 = (try svc.getOrder(order_id)).?;
    defer o2.free(allocator);
    try std.testing.expectEqual(@as(i64, 3), o2.status);
    try std.testing.expectEqualStrings("顺丰", o2.express_company);
    try std.testing.expectError(error.OrderStateConflict, svc.cancelOrder(order_id));

    // 清理购物车/地址。
    try svc.updateCart(cart_id, 1);
    try svc.deleteCart(cart_id);
    try svc.deleteAddress(addr_id);
}

test "shop: refund apply/audit + comment + distribution hookup (Phase3)" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = shop.persistence.ShopStore.init(allocator, env.client);
    var svc = shop.service.ShopService.init(allocator, std.testing.io, &store);
    var dist_store = distribution.persistence.DistributionStore.init(allocator, env.client);
    var dist_svc = distribution.service.DistributionService.init(allocator, std.testing.io, &dist_store);
    svc.dist_svc = &dist_svc;

    // 分销链：A(顶) ← B(买家上级)。
    try dist_svc.becomeDistributor(1, 9, "o_A", "");
    try dist_svc.becomeDistributor(1, 9, "o_B", "o_A");

    // 商品 + 下单（mock 支付 markPaid → 触发分佣）。
    const pid = try svc.createProduct(1, 9, .{
        .category_id = 0,
        .name = "佣金商品",
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
    const addr_id = try svc.createAddress(1, 9, .{
        .openid = "o_B",
        .name = "B",
        .mobile = "13800000000",
        .region = "SZ",
        .detail = "1号",
        .is_default = 1,
    });
    const order_id = try svc.createOrder(1, 9, "o_B", addr_id, &.{
        .{ .product_id = pid, .sku_id = skus[0].id, .quantity = 1 },
    }, "", "", "", 0, "");
    try svc.markPaid(1, 9, order_id);

    // 分佣：B 的一级上级 A 得 10% = 1000。
    const a = (try dist_svc.getDistributor(1, 9, "o_A")).?;
    defer a.free(allocator);
    try std.testing.expectEqualStrings("1000", a.commission_balance);

    // 退款：申请（重复申请拒绝）→ 审核同意 → 订单置已取消。
    _ = try svc.applyRefund(1, 9, order_id, "o_B", "不想要了");
    try std.testing.expectError(error.Duplicate, svc.applyRefund(1, 9, order_id, "o_B", "再次申请"));
    var refunds = try svc.listRefunds(1, 20, 1, 9, -1);
    defer refunds.free(allocator);
    try std.testing.expectEqual(@as(i64, 1), refunds.total);
    try svc.auditRefund(order_id, refunds.items[0].id, true);
    var o = (try svc.getOrder(order_id)).?;
    defer o.free(allocator);
    try std.testing.expectEqual(@as(i64, 4), o.status);

    // 评价实名：退款订单（status=4）不可评。
    const ops = try svc.listOrderProducts(order_id);
    defer {
        for (ops) |op| op.free(allocator);
        if (ops.len > 0) allocator.free(ops);
    }
    try std.testing.expectError(error.OrderStateConflict, svc.createComment(1, 9, .{
        .order_product_id = ops[0].id,
        .product_id = pid,
        .openid = "o_B",
        .star = 5,
        .content = "不该能评",
    }));

    // 完整订单（支付→发货→收货）后可评价；非买家不可评。
    const order2 = try svc.createOrder(1, 9, "o_B", addr_id, &.{
        .{ .product_id = pid, .sku_id = skus[0].id, .quantity = 1 },
    }, "", "", "", 0, "");
    try svc.markPaid(1, 9, order2);
    try svc.shipOrder(order2, "顺丰", "SF2");
    try svc.confirmOrder(order2);
    const ops2 = try svc.listOrderProducts(order2);
    defer {
        for (ops2) |op| op.free(allocator);
        if (ops2.len > 0) allocator.free(ops2);
    }
    // 非买家（o_x）评价 → InvalidInput。
    try std.testing.expectError(error.InvalidInput, svc.createComment(1, 9, .{
        .order_product_id = ops2[0].id,
        .product_id = pid,
        .openid = "o_x",
        .star = 5,
        .content = "冒充",
    }));
    _ = try svc.createComment(1, 9, .{
        .order_product_id = ops2[0].id,
        .product_id = pid,
        .openid = "o_B",
        .star = 5,
        .content = "很好用",
    });
    const comments = try svc.listComments(pid);
    defer {
        for (comments) |c| c.free(allocator);
        if (comments.len > 0) allocator.free(comments);
    }
    try std.testing.expectEqual(@as(usize, 1), comments.len);
    try std.testing.expectEqualStrings("很好用", comments[0].content);
}

test "shop: coupon deduction + member points accrual on payment" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = shop.persistence.ShopStore.init(allocator, env.client);
    var svc = shop.service.ShopService.init(allocator, std.testing.io, &store);
    var coupon_store = coupon.persistence.CouponStore.init(allocator, env.client);
    var coupon_svc = coupon.service.CouponService.init(allocator, std.testing.io, &coupon_store);
    var mc_store = member_card.persistence.MemberCardStore.init(allocator, env.client);
    var mc_svc = member_card.service.MemberCardService.init(allocator, std.testing.io, &mc_store);
    svc.coupon_store = &coupon_store;
    svc.member_svc = &mc_svc;

    // 商品 100 元（10000 分）。
    const pid = try svc.createProduct(1, 9, .{
        .category_id = 0,
        .name = "满减测试",
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
    const addr_id = try svc.createAddress(1, 9, .{
        .openid = "o_m",
        .name = "M",
        .mobile = "13800000000",
        .region = "SZ",
        .detail = "1号",
        .is_default = 1,
    });

    // 会员卡（支付后积分累计的前提）：先建等级，开卡自动绑定。
    _ = try mc_svc.createLevel(1, 9, "普通会员", 1, 1000, 100, 0, 1);
    try mc_svc.openCard(1, 9, "o_m");

    // 领券：满 50 减 10（1000 分）。
    const coupon_id = try coupon_svc.createCoupon(1, 9, "满50减10", 1000, 5000, 100, 1, 0, 0, 1);
    const code = try coupon_svc.claimCoupon(allocator, 1, 9, "o_m", coupon_id);
    defer allocator.free(code);

    // 下单用券：100 元 - 10 元 = 90 元实付。
    const order_id = try svc.createOrder(1, 9, "o_m", addr_id, &.{
        .{ .product_id = pid, .sku_id = skus[0].id, .quantity = 1 },
    }, code, "", "", 0, "");
    var o = (try svc.getOrder(order_id)).?;
    defer o.free(allocator);
    try std.testing.expectEqualStrings("10000", o.total_amount);
    try std.testing.expectEqualStrings("9000", o.pay_amount);

    // 券已核销（used）。
    const u = (try coupon_store.getByCode(code)).?;
    defer u.free(allocator);
    try std.testing.expectEqualStrings("used", u.status);

    // 支付 → 会员积分累计：90 元 = 90 积分。
    try svc.markPaid(1, 9, order_id);
    const v = (try mc_svc.view(1, 9, "o_m")).?;
    defer v.free(allocator);
    try std.testing.expectEqual(@as(i64, 90), v.points);

    // 他人券不可用：B 领券，A 下单用 B 的券 → InvalidInput。
    const code_b = try coupon_svc.claimCoupon(allocator, 1, 9, "o_other", coupon_id);
    defer allocator.free(code_b);
    try std.testing.expectError(error.InvalidInput, svc.createOrder(1, 9, "o_m", addr_id, &.{
        .{ .product_id = pid, .sku_id = skus[0].id, .quantity = 1 },
    }, code_b, "", "", 0, ""));
}

test "shop: idempotency + stock restore on cancel (production hardening)" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = shop.persistence.ShopStore.init(allocator, env.client);
    var svc = shop.service.ShopService.init(allocator, std.testing.io, &store);

    const pid = try svc.createProduct(1, 9, .{
        .category_id = 0,
        .name = "回滚测试",
        .image = "",
        .images = "[]",
        .content = "",
        .price = 1000,
        .original_price = 2000,
        .stock = 10,
        .status = 1,
        .skus = &.{},
    });
    const skus = try svc.listSkus(pid);
    defer {
        for (skus) |s| s.free(allocator);
        if (skus.len > 0) allocator.free(skus);
    }
    const addr_id = try svc.createAddress(1, 9, .{
        .openid = "o_r",
        .name = "R",
        .mobile = "13800000000",
        .region = "SZ",
        .detail = "1",
        .is_default = 1,
    });
    const items: []const shop.service.OrderItemInput = &.{.{ .product_id = pid, .sku_id = skus[0].id, .quantity = 3 }};

    // 幂等：同 client_trade_no 重复下单 → 返回同一订单，库存只扣一次（10→7）。
    const o1 = try svc.createOrder(1, 9, "o_r", addr_id, items, "", "CTN-001", "", 0, "");
    const o2 = try svc.createOrder(1, 9, "o_r", addr_id, items, "", "CTN-001", "", 0, "");
    try std.testing.expectEqual(o1, o2);
    const sku_after = (try svc.getSku(skus[0].id)).?;
    defer sku_after.free(allocator);
    try std.testing.expectEqual(@as(i64, 7), sku_after.stock);

    // 取消 → 库存回滚（7→10），销量回退。
    try svc.cancelOrder(o1);
    const sku_restored = (try svc.getSku(skus[0].id)).?;
    defer sku_restored.free(allocator);
    try std.testing.expectEqual(@as(i64, 10), sku_restored.stock);
    const p2 = (try svc.getProduct(pid)).?;
    defer p2.free(allocator);
    try std.testing.expectEqual(@as(i64, 0), p2.sales);
}

test "shop: favorite + order stats (production extras)" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = shop.persistence.ShopStore.init(allocator, env.client);
    var svc = shop.service.ShopService.init(allocator, std.testing.io, &store);

    // 两件商品。
    const pid1 = try svc.createProduct(1, 9, .{
        .category_id = 0,
        .name = "收藏A",
        .image = "",
        .images = "[]",
        .content = "",
        .price = 1000,
        .original_price = 2000,
        .stock = 5,
        .status = 1,
        .skus = &.{},
    });
    const pid2 = try svc.createProduct(1, 9, .{
        .category_id = 0,
        .name = "收藏B",
        .image = "",
        .images = "[]",
        .content = "",
        .price = 2000,
        .original_price = 3000,
        .stock = 5,
        .status = 1,
        .skus = &.{},
    });

    // 收藏：两件 + 幂等（重复收藏不重复）。
    try svc.favorite(1, 9, "o_f", pid1);
    try svc.favorite(1, 9, "o_f", pid1);
    try svc.favorite(1, 9, "o_f", pid2);
    try std.testing.expect(try svc.isFavorite(1, "o_f", pid1));
    const favs = try svc.listFavorites(1, "o_f");
    defer {
        for (favs) |f| f.free(allocator);
        if (favs.len > 0) allocator.free(favs);
    }
    try std.testing.expectEqual(@as(usize, 2), favs.len);

    // 取消收藏一件。
    try svc.unfavorite(favs[0].id);
    try std.testing.expect(!(try svc.isFavorite(1, "o_f", pid1)));

    // 订单统计：2 单（1 支付 1 取消）+ 1 单待支付。
    const s1 = try svc.listSkus(pid1);
    defer {
        for (s1) |x| x.free(allocator);
        if (s1.len > 0) allocator.free(s1);
    }
    const addr_id = try svc.createAddress(1, 9, .{
        .openid = "o_s",
        .name = "S",
        .mobile = "13800000000",
        .region = "SZ",
        .detail = "1",
        .is_default = 1,
    });
    const o1 = try svc.createOrder(1, 9, "o_s", addr_id, &.{
        .{ .product_id = pid1, .sku_id = s1[0].id, .quantity = 2 },
    }, "", "", "", 0, "");
    try svc.markPaid(1, 9, o1); // 已支付 2000
    const o2 = try svc.createOrder(1, 9, "o_s", addr_id, &.{
        .{ .product_id = pid2, .sku_id = s1[0].id, .quantity = 1 },
    }, "", "", "", 0, "");
    try svc.cancelOrder(o2); // 取消
    _ = try svc.createOrder(1, 9, "o_s", addr_id, &.{
        .{ .product_id = pid1, .sku_id = s1[0].id, .quantity = 1 },
    }, "", "", "", 0, ""); // 待支付

    const stats = try svc.orderStats(1, 9);
    try std.testing.expectEqual(@as(i64, 1), stats.pending_pay);
    try std.testing.expectEqual(@as(i64, 1), stats.pending_ship);
    try std.testing.expectEqual(@as(i64, 2000), stats.total_sales);
}

test "shop: balance payment via wallet (production extras)" {
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

    // 粉丝 + 充值钱包 200 元（20000 分）。
    const now_ts = zigmodu.time.wallClockSeconds(std.testing.io);
    const fan_id = try fan_store.upsert(1, 9, "o_balance", "", "余额买家", "", true, now_ts, now_ts);
    _ = try pay_store.creditWallet(1, 9, fan_id, 20000, zigmodu.time.wallClockSeconds(std.testing.io));

    // 商品 150 元。
    const pid = try svc.createProduct(1, 9, .{
        .category_id = 0,
        .name = "余额支付商品",
        .image = "",
        .images = "[]",
        .content = "",
        .price = 15000,
        .original_price = 20000,
        .stock = 10,
        .status = 1,
        .skus = &.{},
    });
    const skus = try svc.listSkus(pid);
    defer {
        for (skus) |s| s.free(allocator);
        if (skus.len > 0) allocator.free(skus);
    }
    const addr_id = try svc.createAddress(1, 9, .{
        .openid = "o_balance",
        .name = "B",
        .mobile = "13800000000",
        .region = "SZ",
        .detail = "1",
        .is_default = 1,
    });

    // 余额支付下单：钱包 20000 → 15000，订单已支付。
    const order_id = try svc.createOrder(1, 9, "o_balance", addr_id, &.{
        .{ .product_id = pid, .sku_id = skus[0].id, .quantity = 1 },
    }, "", "", "balance", 0, "");
    var o = (try svc.getOrder(order_id)).?;
    defer o.free(allocator);
    try std.testing.expectEqual(@as(i64, 1), o.status); // 已支付
    const wallet = (try pay_svc.walletBalance(1, 9, fan_id)).?;
    defer wallet.free(allocator);
    try std.testing.expectEqualStrings("5000", wallet.balance);

    // 余额不足（仅 5000）→ 再下单 100 元 → InsufficientBalance。
    try std.testing.expectError(error.InsufficientBalance, svc.createOrder(1, 9, "o_balance", addr_id, &.{
        .{ .product_id = pid, .sku_id = skus[0].id, .quantity = 1 },
    }, "", "", "balance", 0, ""));
}
