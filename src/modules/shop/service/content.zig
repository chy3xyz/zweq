//! 内容与门店域服务：AI 导购助手 / webhook 分发 / 文章 / 门店自提与核销防暴力（拆分自原 ShopService 单体，方法正文逐字搬运）。
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

/// 智能客服：关键词规则解析订单上下文（不依赖 LLM）；返回引导文本。
pub fn assistant(self: *ShopService, allocator: std.mem.Allocator, tenant_id: i64, account_id: i64, openid: []const u8, question: []const u8) ShopError![]const u8 {
    var buf = std.ArrayList(u8).empty;
    errdefer buf.deinit(allocator);
    const q = std.mem.trim(u8, question, " \t\n");

    // 订单状态
    if (std.mem.indexOf(u8, q, "订单") != null or std.mem.indexOf(u8, q, "order") != null) {
        var orders = self.store.trade.listOrders(1, 3, tenant_id, account_id, openid, -1, "") catch return error.Unexpected;
        defer orders.free(self.allocator);
        if (orders.items.len == 0) {
            buf.appendSlice(allocator, "您还没有订单，快去商城逛逛吧～") catch return error.Unexpected;
        } else {
            buf.appendSlice(allocator, "最近订单：\n") catch return error.Unexpected;
            for (orders.items) |o| {
                buf.appendSlice(allocator, o.order_no) catch return error.Unexpected;
                buf.appendSlice(allocator, " · ") catch return error.Unexpected;
                buf.appendSlice(allocator, switch (o.status) {
                    0 => "待支付",
                    1 => "已支付",
                    2 => "已发货",
                    3 => "已完成",
                    else => "已取消",
                }) catch return error.Unexpected;
                buf.appendSlice(allocator, " · ") catch return error.Unexpected;
                const pay = std.fmt.parseInt(i64, o.pay_amount, 10) catch 0;
                const fen = @mod(pay, 100);
                const amt = if (fen < 10)
                    (std.fmt.allocPrint(allocator, "{d}.0{d} 元", .{ @divTrunc(pay, 100), fen }) catch "?")
                else
                    (std.fmt.allocPrint(allocator, "{d}.{d} 元", .{ @divTrunc(pay, 100), fen }) catch "?");
                defer allocator.free(amt);
                buf.appendSlice(allocator, amt) catch return error.Unexpected;
                buf.appendSlice(allocator, "\n") catch return error.Unexpected;
            }
        }
        return buf.toOwnedSlice(allocator) catch return error.Unexpected;
    }

    // 物流
    if (std.mem.indexOf(u8, q, "物流") != null or std.mem.indexOf(u8, q, "快递") != null) {
        var orders = self.store.trade.listOrders(1, 1, tenant_id, account_id, openid, 2, "") catch return error.Unexpected;
        defer orders.free(self.allocator);
        if (orders.items.len == 0) {
            buf.appendSlice(allocator, "您没有已发货的订单") catch return error.Unexpected;
        } else {
            const o = &orders.items[0];
            buf.appendSlice(allocator, "最新物流：") catch return error.Unexpected;
            buf.appendSlice(allocator, o.express_company) catch return error.Unexpected;
            buf.appendSlice(allocator, " 单号 ") catch return error.Unexpected;
            buf.appendSlice(allocator, o.express_no) catch return error.Unexpected;
        }
        return buf.toOwnedSlice(allocator) catch return error.Unexpected;
    }

    // 待支付
    if (std.mem.indexOf(u8, q, "支付") != null or std.mem.indexOf(u8, q, "付款") != null) {
        const pending = self.store.trade.countOrdersByStatus(tenant_id, account_id, 0) catch 0;
        const paid = self.store.trade.countOrdersByStatus(tenant_id, account_id, 1) catch 0;
        const stat = std.fmt.allocPrint(allocator, "待支付 {d} 单，已支付 {d} 单", .{ pending, paid }) catch return error.Unexpected;
        defer allocator.free(stat);
        return self.allocator.dupe(u8, stat) catch error.Unexpected;
    }

    // 收藏
    if (std.mem.indexOf(u8, q, "收藏") != null) {
        const favs = self.store.trade.listFavorites(tenant_id, openid) catch &.{};
        defer {
            for (favs) |f| f.free(self.allocator);
            if (favs.len > 0) self.allocator.free(favs);
        }
        const c = std.fmt.allocPrint(allocator, "您收藏了 {d} 件商品", .{favs.len}) catch "?";
        defer allocator.free(c);
        return self.allocator.dupe(u8, c) catch error.Unexpected;
    }

    // 默认引导
    return self.allocator.dupe(u8, "我可以帮您查询订单、物流、支付状态和收藏。试试问我「我的订单」「物流到哪了」") catch error.Unexpected;
}

// ── Webhook ───────────────────────────────────────────

pub fn createWebhook(self: *ShopService, tenant_id: i64, account_id: i64, url: []const u8, events: []const u8) ShopError!i64 {
    if (std.mem.trim(u8, url, " \t").len == 0 or std.mem.indexOf(u8, url, "http") == null) return error.InvalidInput;
    return self.store.content.createWebhook(tenant_id, account_id, url, events, self.now()) catch error.Unexpected;
}

pub fn listWebhooks(self: *ShopService, tenant_id: i64, account_id: i64) ShopError![]ShopWebhookRow {
    return self.store.content.listWebhooks(tenant_id, account_id) catch error.Unexpected;
}

pub fn deleteWebhook(self: *ShopService, id: i64) ShopError!void {
    _ = self.store.content.deleteWebhook(id) catch return error.Unexpected;
}

/// 推送订单事件到配置的 webhook URL（事件驱动开放出口）。
/// 投递改走持久任务队列（webhook.deliver，见 src/jobs.zig）：此处只
/// 入队，POST 与退避重试由 Dispatcher worker 异步完成，不再在事件
/// 监听里逐个同步 POST 外部 URL。入队失败只记日志（不影响支付主流程）。
pub fn dispatchWebhooks(self: *ShopService, event: []const u8, tenant_id: i64, account_id: i64, order_id: i64) void {
    const ts = self.task_svc orelse return;
    const hooks = self.store.content.listWebhooks(tenant_id, account_id) catch return;
    defer {
        for (hooks) |h| h.free(self.allocator);
        if (hooks.len > 0) self.allocator.free(hooks);
    }
    for (hooks) |h| {
        if (std.mem.indexOf(u8, h.events, event) == null) continue;
        const body = std.fmt.allocPrint(self.allocator, "{{\"event\":\"{s}\",\"order_id\":{d},\"account_id\":{d}}}", .{ event, order_id, account_id }) catch continue;
        defer self.allocator.free(body);
        // 任务参数 JSON 序列化（与 auth/api.zig jsonPayload 同惯例）：
        // payload 本身是 JSON 文本，std.json.fmt 负责转义内嵌引号。
        const task_payload = std.fmt.allocPrint(self.allocator, "{f}", .{std.json.fmt(.{
            .endpoint = h.url,
            .event = event,
            .payload = body,
        }, .{})}) catch continue;
        defer self.allocator.free(task_payload);
        _ = ts.enqueueNow("webhook.deliver", task_payload, tenant_id) catch |err| {
            std.log.warn("[shop] webhook 投递任务入队失败 url={s} err={s}", .{ h.url, @errorName(err) });
        };
    }
}

// ── 文章 ─────────────────────────────────────────────

pub fn createArticle(self: *ShopService, tenant_id: i64, account_id: i64, title: []const u8, content: []const u8) ShopError!i64 {
    if (std.mem.trim(u8, title, " \t").len == 0) return error.InvalidInput;
    return self.store.content.createArticle(tenant_id, account_id, title, content, self.now()) catch error.Unexpected;
}

pub fn listArticles(self: *ShopService, page: usize, page_size: usize, tenant_id: i64, account_id: i64, on_sale: bool) ShopError!ArticleListResult {
    return self.store.content.listArticles(page, page_size, tenant_id, account_id, on_sale) catch error.Unexpected;
}

pub fn getArticle(self: *ShopService, id: i64) ShopError!?ShopArticleRow {
    return self.store.content.getArticle(id) catch error.Unexpected;
}

pub fn deleteArticle(self: *ShopService, id: i64) ShopError!void {
    _ = self.store.content.deleteArticle(id) catch return error.Unexpected;
}

// ── 邀请有礼 ─────────────────────────────────────────

pub fn createOutlet(self: *ShopService, tenant_id: i64, account_id: i64, name: []const u8, address: []const u8, mobile: []const u8) ShopError!i64 {
    if (std.mem.trim(u8, name, " \t").len == 0) return error.InvalidInput;
    return self.store.content.createOutlet(tenant_id, account_id, name, address, mobile, self.now()) catch error.Unexpected;
}

pub fn listOutlets(self: *ShopService, tenant_id: i64, account_id: i64) ShopError![]persist.ShopOutletRow {
    return self.store.content.listOutlets(tenant_id, account_id) catch error.Unexpected;
}

pub fn deleteOutlet(self: *ShopService, id: i64) ShopError!void {
    _ = self.store.content.deleteOutlet(id) catch return error.Unexpected;
}

/// 自提核销：校验自提码 + 已支付（1）→ 状态置已完成（3）。
/// 核销翻转走 租户 + 状态 + 自提 + 码 的原子条件更新，并发重复核销只命中一次。
/// 注意：核销由门店管理员发起（非买家本人），故不加 openid 归属条件。
/// 防暴力：取货码仅 6 位数字（1e6 空间），按订单维度做连续失败锁定
/// （PickupGuard，5 次失败锁 15 分钟）；路由层另有 per-IP 限流双保险。
/// 只对「码不匹配」计数——订单状态类失败不含码信息，无需计入。
pub fn pickupOrder(self: *ShopService, tenant_id: i64, order_id: i64, code: []const u8) ShopError!void {
    const now_ts = self.now();
    if (self.pickup_guard.allow(order_id, now_ts) == .locked) return error.PickupLocked;
    const o_opt = self.store.trade.getOrder(order_id) catch return error.Unexpected;
    const o = o_opt orelse return error.NotFound;
    defer o.free(self.allocator);
    if (o.status != 1) return error.OrderStateConflict;
    if (!std.mem.eql(u8, o.pickup_type, "self")) return error.OrderStateConflict;
    if (o.pickup_code.len == 0 or !std.mem.eql(u8, o.pickup_code, code)) {
        self.pickup_guard.fail(order_id, now_ts);
        return error.InvalidInput;
    }
    // 原子核销：tenant + 已支付 + 自提 + 码一致才翻转；未命中即并发已核销。
    if (!(self.store.trade.pickupOrderOn(tenant_id, order_id, code, self.now()) catch return error.Unexpected)) return error.OrderStateConflict;
    self.pickup_guard.reset(order_id);
}
