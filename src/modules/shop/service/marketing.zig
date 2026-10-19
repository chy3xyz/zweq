//! 营销域服务：储值套餐 / 邀请有礼 / 拼团开团参团（拆分自原 ShopService 单体，方法正文逐字搬运）。
const std = @import("std");
const zigmodu = @import("zigmodu");
const zent = @import("zent");
const persist = @import("../persistence.zig");
const schema = @import("../../../schema.zig");
const crud = zent.crud_helpers;
const coupon_service = @import("../../coupon/service.zig");
const member_persist = @import("../../member/persistence.zig");
const task_service = @import("../../task/service.zig");
const db_mod = @import("../../../db.zig");
const host = @import("../service.zig");

// 宿主符号沿用原名（方法正文逐字搬运、零改动）。
const ShopService = host.ShopService;
const ShopError = host.ShopError;
const ProductInput = host.ProductInput;
const SkuInput = host.SkuInput;
const OrderItemInput = host.OrderItemInput;
const AddressInput = host.AddressInput;
const OrderSummary = host.OrderSummary;
const OrderStats = host.OrderStats;
const FanOrderOverview = host.FanOrderOverview;
const ShopCategoryRow = host.ShopCategoryRow;
const ShopProductRow = host.ShopProductRow;
const ShopSkuRow = host.ShopSkuRow;
const CategoryListResult = host.CategoryListResult;
const ProductListResult = host.ProductListResult;
const ShopCartRow = host.ShopCartRow;
const ShopAddressRow = host.ShopAddressRow;
const ShopOrderRow = host.ShopOrderRow;
const ShopOrderProductRow = host.ShopOrderProductRow;
const OrderListResult = host.OrderListResult;
const ShopRefundRow = host.ShopRefundRow;
const ShopCommentRow = host.ShopCommentRow;
const RefundListResult = host.RefundListResult;
const ShopFavoriteRow = host.ShopFavoriteRow;
const ShopOutletRow = host.ShopOutletRow;
const ShopBalancePlanRow = host.ShopBalancePlanRow;
const ShopGrouponRow = host.ShopGrouponRow;
const ShopGrouponTeamRow = host.ShopGrouponTeamRow;
const ShopInviteGiftRow = host.ShopInviteGiftRow;
const ShopInviteRecordRow = host.ShopInviteRecordRow;
const ShopArticleRow = host.ShopArticleRow;
const ArticleListResult = host.ArticleListResult;
const ShopWebhookRow = host.ShopWebhookRow;

pub fn createBalancePlan(self: *ShopService, tenant_id: i64, account_id: i64, name: []const u8, amount: i64, bonus: i64) ShopError!i64 {
    if (std.mem.trim(u8, name, " \t").len == 0 or amount <= 0 or bonus < 0) return error.InvalidInput;
    return self.store.marketing.createBalancePlan(tenant_id, account_id, name, amount, bonus, self.now()) catch error.Unexpected;
}

pub fn listBalancePlans(self: *ShopService, tenant_id: i64, account_id: i64) ShopError![]ShopBalancePlanRow {
    return self.store.marketing.listBalancePlans(tenant_id, account_id) catch error.Unexpected;
}

pub fn deleteBalancePlan(self: *ShopService, id: i64) ShopError!void {
    _ = self.store.marketing.deleteBalancePlan(id) catch return error.Unexpected;
}

/// 充值：mock 即时入账（amount + bonus 进钱包）；真实走 payment v3。
pub fn rechargePlan(self: *ShopService, tenant_id: i64, account_id: i64, openid: []const u8, plan_id: i64) ShopError!void {
    const plan_opt = self.store.marketing.getBalancePlan(plan_id) catch return error.Unexpected;
    const plan = plan_opt orelse return error.NotFound;
    defer plan.free(self.allocator);
    if (self.payment_svc) |ps| {
        if (self.fan_store) |fs| {
            const fan_opt = fs.getByOpenid(tenant_id, account_id, openid) catch return error.Unexpected;
            const fan = fan_opt orelse return error.NotFound;
            defer fan.free(self.allocator);
            const pay_mod = @import("../../payment/service.zig");
            const psvc: *pay_mod.PaymentService = @ptrCast(@alignCast(ps));
            const now_secs = self.now();
            const amount = std.fmt.parseInt(i64, plan.amount, 10) catch return error.Unexpected;
            const bonus = std.fmt.parseInt(i64, plan.bonus, 10) catch return error.Unexpected;
            _ = psvc.store.creditWallet(tenant_id, account_id, fan.id, amount + bonus, now_secs) catch return error.Unexpected;
        }
    }
}

// ── 订单超时自动取消（生产运维） ─────────────────────

pub fn createInviteGift(self: *ShopService, tenant_id: i64, account_id: i64, target_count: i64, reward_type: []const u8, reward_value: i64) ShopError!i64 {
    if (target_count <= 0 or reward_value <= 0) return error.InvalidInput;
    if (!std.mem.eql(u8, reward_type, "points") and !std.mem.eql(u8, reward_type, "coupon")) return error.InvalidInput;
    return self.store.marketing.createInviteGift(tenant_id, account_id, target_count, reward_type, reward_value, self.now()) catch error.Unexpected;
}

pub fn listInviteGifts(self: *ShopService, tenant_id: i64, account_id: i64) ShopError![]ShopInviteGiftRow {
    return self.store.marketing.listInviteGifts(tenant_id, account_id) catch error.Unexpected;
}

pub fn deleteInviteGift(self: *ShopService, id: i64) ShopError!void {
    _ = self.store.marketing.deleteInviteGift(id) catch return error.Unexpected;
}

/// 绑定邀请关系：新粉丝带邀请人 openid → 记录（幂等）；邀请人达标 → 发奖励。
pub fn bindInvite(self: *ShopService, tenant_id: i64, account_id: i64, inviter_openid: []const u8, invitee_openid: []const u8) ShopError!void {
    if (std.mem.eql(u8, inviter_openid, invitee_openid)) return error.InvalidInput;
    if (!(self.store.marketing.bindInvite(tenant_id, account_id, inviter_openid, invitee_openid, self.now()) catch return error.Unexpected)) return; // 已绑定
    // 达标判定：任一配置满足即发奖（按 target_count 匹配）。
    const gifts = self.store.marketing.listInviteGifts(tenant_id, account_id) catch return;
    defer {
        for (gifts) |g| g.free(self.allocator);
        if (gifts.len > 0) self.allocator.free(gifts);
    }
    const invited = self.store.marketing.countInvites(tenant_id, inviter_openid) catch return;
    for (gifts) |g| {
        if (g.target_count == invited) {
            // 邀请关系已绑定（本函数返回成功）；奖励发放失败只影响邀请人收益，留痕对账。
            self.grantInviteReward(tenant_id, account_id, inviter_openid, g) catch |err| std.log.err("[shop] 邀请达标奖励发放失败 openid={s} reward_type={s} err={s}", .{ inviter_openid, g.reward_type, @errorName(err) });
        }
    }
}

/// 发放奖励：points → 会员积分；coupon → 领券。
pub fn grantInviteReward(self: *ShopService, tenant_id: i64, account_id: i64, openid: []const u8, g: ShopInviteGiftRow) !void {
    if (std.mem.eql(u8, g.reward_type, "points")) {
        if (self.member_svc) |ms| {
            const mc_mod = @import("../../member_card/service.zig");
            const msvc: *mc_mod.MemberCardService = @ptrCast(@alignCast(ms));
            // 奖励积分入账失败则邀请人少得积分（无其它可观测渠道），留痕对账。
            _ = msvc.adjust(tenant_id, account_id, openid, g.reward_value) catch |err| std.log.err("[shop] 邀请奖励积分入账失败 openid={s} points={d} err={s}", .{ openid, g.reward_value, @errorName(err) });
        }
    } else if (std.mem.eql(u8, g.reward_type, "coupon")) {
        if (self.coupon_svc) |cs| {
            const csvc: *coupon_service.CouponService = @ptrCast(@alignCast(cs));
            // 同上：发券失败则邀请人拿不到券，留痕对账。
            _ = csvc.claimCoupon(self.allocator, tenant_id, account_id, openid, g.reward_value) catch |err| std.log.err("[shop] 邀请奖励发券失败 openid={s} coupon_id={d} err={s}", .{ openid, g.reward_value, @errorName(err) });
        }
    }
}

// ── 拼团 ─────────────────────────────────────────────
pub fn createGroupon(self: *ShopService, tenant_id: i64, account_id: i64, product_id: i64, group_price: i64, group_size: i64, start_at: i64, end_at: i64) ShopError!i64 {
    if (group_price <= 0 or group_size < 2) return error.InvalidInput;
    const p_opt = self.store.catalog.getProduct(product_id) catch return error.Unexpected;
    const p = p_opt orelse return error.NotFound;
    p.free(self.allocator);
    return self.store.marketing.createGroupon(tenant_id, account_id, product_id, group_price, group_size, start_at, end_at, self.now()) catch error.Unexpected;
}

pub fn listGroupons(self: *ShopService, tenant_id: i64, account_id: i64) ShopError![]ShopGrouponRow {
    return self.store.marketing.listGroupons(tenant_id, account_id) catch error.Unexpected;
}

/// 团价下单（内部）：校验商品 → 扣 SKU 库存 → 团价订单 + 明细。
pub fn grouponOrder(self: *ShopService, tenant_id: i64, account_id: i64, openid: []const u8, address_id: i64, activity: ShopGrouponRow, sku_id: i64, team_id: i64) ShopError!i64 {
    const addr_opt = self.store.trade.getAddress(tenant_id, address_id) catch return error.Unexpected;
    const addr = addr_opt orelse return error.InvalidInput;
    defer addr.free(self.allocator);
    const address_json = std.json.Stringify.valueAlloc(self.allocator, .{
        .name = addr.name,
        .mobile = addr.mobile,
        .region = addr.region,
        .detail = addr.detail,
    }, .{}) catch return error.Unexpected;
    defer self.allocator.free(address_json);

    const sku_opt = self.store.catalog.getSku(sku_id) catch return error.Unexpected;
    const sku = sku_opt orelse return error.NotFound;
    defer sku.free(self.allocator);
    if (!(self.store.catalog.consumeSkuStock(self.allocator, sku_id, 1) catch return error.Unexpected)) return error.OutOfStock;

    const order_no = self.genOrderNo() catch return error.Unexpected;
    defer self.allocator.free(order_no);
    const now_secs = self.now();
    const group_price = std.fmt.parseInt(i64, activity.group_price, 10) catch return error.Unexpected;
    const order_id = self.store.trade.createOrder(tenant_id, account_id, order_no, "", openid, group_price, group_price, address_json, "delivery", "", 0, team_id, now_secs) catch return error.Unexpected;

    const p_opt = self.store.catalog.getProduct(activity.product_id) catch return error.Unexpected;
    const p = p_opt orelse return error.NotFound;
    defer p.free(self.allocator);
    _ = self.store.trade.createOrderProduct(tenant_id, account_id, order_id, .{
        .product_id = activity.product_id,
        .sku_id = sku_id,
        .name = p.name,
        .image = p.image,
        .spec_json = sku.spec_json,
        .price = group_price,
        .quantity = 1,
    }, now_secs) catch return error.Unexpected;
    // 销量为派生统计，累加失败不影响已建订单，但仍留痕供对账。
    self.store.catalog.addProductSales(activity.product_id, 1) catch |err| std.log.err("[shop] 拼团下单累计商品销量失败 product_id={d} err={s}", .{ activity.product_id, @errorName(err) });
    return order_id;
}

/// 开团：leader 以团价下单 + 建团（current=1）。
pub fn openGroupon(self: *ShopService, tenant_id: i64, account_id: i64, openid: []const u8, address_id: i64, activity_id: i64, sku_id: i64) ShopError!i64 {
    const a_opt = self.store.marketing.getGroupon(tenant_id, activity_id) catch return error.Unexpected;
    const a = a_opt orelse return error.NotFound;
    defer a.free(self.allocator);
    if (a.status != 1) return error.InvalidInput;
    const team_id = self.store.marketing.createTeam(tenant_id, account_id, activity_id, openid, self.now()) catch return error.Unexpected;
    _ = self.grouponOrder(tenant_id, account_id, openid, address_id, a, sku_id, team_id) catch |err| {
        return err;
    };
    return team_id;
}

/// 参团：团价下单 + current+1；成团 → 团内订单标记支付（mock）。
pub fn joinGroupon(self: *ShopService, tenant_id: i64, account_id: i64, openid: []const u8, address_id: i64, team_id: i64, sku_id: i64) ShopError!i64 {
    const t_opt = self.store.marketing.getTeam(tenant_id, team_id) catch return error.Unexpected;
    const t = t_opt orelse return error.NotFound;
    defer t.free(self.allocator);
    if (t.status != 0) return error.InvalidInput; // 已结束
    const a_opt = self.store.marketing.getGroupon(tenant_id, t.activity_id) catch return error.Unexpected;
    const a = a_opt orelse return error.NotFound;
    defer a.free(self.allocator);
    // 满员守卫：marketing.joinTeam 的 increment 无 current<group_size 上限条件，
    // 超团只能靠调用方在 join 前拦截。这里重读团（t 是进入接口时的快照，期间
    // 其他参团者可能已把 current 顶满），满员按"已结束"同一语义拒绝——必须先
    // 于 grouponOrder 拦截，否则先建单/扣库存再报错会留下悬空待支付订单。
    // 遗留竞态：重读与 joinTeam 的 increment 之间仍有窗口，严格有序的并发请求
    // 仍可能把 current 顶超 group_size；彻底修法是给 joinTeam 的 increment 加
    // "current + 1 <= group_size" 条件（marketing_store 不在本次改动范围）。
    const fresh_opt = self.store.marketing.getTeam(tenant_id, team_id) catch return error.Unexpected;
    const fresh = fresh_opt orelse return error.NotFound;
    defer fresh.free(self.allocator);
    if (fresh.status != 0 or fresh.current >= a.group_size) return error.InvalidInput; // 已满员/已结束
    const order_id = self.grouponOrder(tenant_id, account_id, openid, address_id, a, sku_id, team_id) catch |err| {
        return err;
    };
    // joinTeam 返回 false 混合了两种不可区分的情形：increment 失败（团行消失/
    // DB 错误，此时订单已建但人数未计入，该成员单可能永远无法成团——遗留风险）
    // 与"未成团"；返回 true 仅表示"本次 increment 后已满员"，触发成团批量支付。
    if (self.store.marketing.joinTeam(self.allocator, tenant_id, team_id, a.group_size) catch false) {
        // 成团：团内全部订单 mock 支付 → 触发分销/积分。
        const orders = self.store.marketing.listOrdersByTeam(team_id) catch &.{};
        defer {
            for (orders) |o| o.free(self.allocator);
            if (orders.len > 0) self.allocator.free(orders);
        }
        for (orders) |o| {
            // 成团即代表团内订单已支付；标记失败会让订单停在待支付（且不触发分佣/积分），留痕。
            self.markPaid(tenant_id, account_id, o.id) catch |err| std.log.err("[shop] 成团后标记订单已支付失败 order_id={d} err={s}", .{ o.id, @errorName(err) });
        }
    }
    return order_id;
}

// ── 门店自提 ──────────────────────────────────────────
