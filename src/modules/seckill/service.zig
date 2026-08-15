//! Seckill service — 秒杀活动 + 原子抢购业务 + message 模块 Receiver 接入。
//!
//! 电商营销核心：限时低价 + 限量抢购。公众号「秒杀」列进行中活动，
//! 「抢N」抢购（时间窗 + 原子库存 + 每人限购）。

const std = @import("std");
const zigmodu = @import("zigmodu");
const persist = @import("persistence.zig");
const message_mod = @import("../message/service.zig");

pub const SeckillActivityRow = persist.SeckillActivityRow;
pub const SeckillListResult = persist.SeckillListResult;

pub const SeckillError = error{
    InvalidInput,
    NotFound,
    NotStarted,
    Ended,
    OutOfStock,
    LimitReached,
    Unexpected,
};

pub const SeckillService = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    store: *persist.SeckillStore,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, store: *persist.SeckillStore) SeckillService {
        return .{ .allocator = allocator, .io = io, .store = store };
    }

    fn now(self: *SeckillService) i64 {
        return zigmodu.time.wallClockSeconds(self.io);
    }

    pub fn createActivity(self: *SeckillService, tenant_id: i64, account_id: i64, title: []const u8, price: i64, original_price: i64, stock: i64, per_user: i64, start_at: i64, end_at: i64) SeckillError!i64 {
        if (std.mem.trim(u8, title, " \t").len == 0 or stock <= 0) return error.InvalidInput;
        if (per_user <= 0) return error.InvalidInput;
        if (start_at > 0 and end_at > 0 and start_at >= end_at) return error.InvalidInput;
        return self.store.createActivity(tenant_id, account_id, title, price, original_price, stock, per_user, start_at, end_at, self.now()) catch error.Unexpected;
    }

    pub fn listActivities(self: *SeckillService, page: usize, page_size: usize, tenant_id: i64, account_id: i64) SeckillError!SeckillListResult {
        return self.store.listActivities(page, page_size, tenant_id, account_id) catch error.Unexpected;
    }

    pub fn getActivity(self: *SeckillService, id: i64) SeckillError!?SeckillActivityRow {
        return self.store.getActivity(id) catch error.Unexpected;
    }

    pub fn listOrders(self: *SeckillService, page: usize, page_size: usize, tenant_id: i64, account_id: i64) SeckillError!persist.SeckillOrderListResult {
        return self.store.listOrders(page, page_size, tenant_id, account_id) catch error.Unexpected;
    }

    /// 抢购：时间窗 → 限购 → 原子库存 → 落单。
    pub fn rush(self: *SeckillService, tenant_id: i64, account_id: i64, openid: []const u8, activity_id: i64, quantity: i64) SeckillError!i64 {
        if (quantity <= 0) return error.InvalidInput;
        const a_opt = self.store.getActivity(activity_id) catch return error.Unexpected;
        const a = a_opt orelse return error.NotFound;
        defer a.free(self.allocator);
        const now_secs = self.now();
        if (a.start_at > 0 and now_secs < a.start_at) return error.NotStarted;
        if (a.end_at > 0 and now_secs > a.end_at) return error.Ended;

        // 限购优先：该 openid 已抢数量 + 本次 <= per_user。
        const already = self.store.countOrdered(tenant_id, activity_id, openid) catch return error.Unexpected;
        if (already + quantity > a.per_user) return error.LimitReached;

        // 库存：sold + 本次 > stock → 售罄。
        if (a.sold + quantity > a.stock) return error.OutOfStock;

        // 原子扣库存（乐观锁），失败即超卖/并发竞争 → 库存不足。
        if (!(self.store.tryConsumeStock(self.allocator, activity_id, quantity) catch return error.Unexpected)) return error.OutOfStock;

        return self.store.createOrder(tenant_id, account_id, openid, activity_id, quantity, now_secs) catch error.Unexpected;
    }
};

/// Receiver context。
pub const ReceiverCtx = struct {
    io: std.Io,
    seckill_svc: *SeckillService,
};

/// `Receiver.handle`：识别「秒杀」（列进行中活动）与「抢N」（抢购）。
pub fn receiverHandle(ctx: ?*anyopaque, allocator: std.mem.Allocator, msg: message_mod.IncomingMessage) anyerror!?message_mod.Reply {
    const c: *ReceiverCtx = @ptrCast(@alignCast(ctx orelse return null));
    if (!std.mem.eql(u8, msg.msg_type, "text")) return null;

    if (std.mem.eql(u8, msg.content, "秒杀")) {
        const a_opt = c.seckill_svc.store.latestActivity(msg.tenant_id, msg.account_id) catch return null;
        const a = a_opt orelse return null;
        defer a.free(allocator);
        var buf = std.ArrayList(u8).empty;
        defer buf.deinit(allocator);
        try buf.appendSlice(allocator, "⚡ 秒杀：");
        try buf.appendSlice(allocator, a.title);
        try buf.appendSlice(allocator, "\n💴 秒杀价 ");
        const price_yuan = @divTrunc(a.price, 100);
        const price_fen = @mod(a.price, 100);
        const price_str = if (price_fen < 10)
            (std.fmt.allocPrint(allocator, "{d}.0{d} 元", .{ price_yuan, price_fen }) catch "?")
        else
            (std.fmt.allocPrint(allocator, "{d}.{d} 元", .{ price_yuan, price_fen }) catch "?");
        defer allocator.free(price_str);
        try buf.appendSlice(allocator, price_str);
        try buf.appendSlice(allocator, "\n🎯 剩余 ");
        const remain = a.stock - a.sold;
        const remain_str = std.fmt.allocPrint(allocator, "{d}", .{remain}) catch "?";
        defer allocator.free(remain_str);
        try buf.appendSlice(allocator, remain_str);
        try buf.appendSlice(allocator, " 件，回复「抢1」开抢！");
        return try message_mod.Reply.text(allocator, buf.items);
    }

    if (std.mem.startsWith(u8, msg.content, "抢")) {
        const num_str = std.mem.trim(u8, msg.content[3..], " \t");
        const n = std.fmt.parseInt(i64, num_str, 10) catch return null;
        const a_opt = c.seckill_svc.store.latestActivity(msg.tenant_id, msg.account_id) catch return null;
        const a = a_opt orelse return null;
        defer a.free(allocator);
        _ = c.seckill_svc.rush(msg.tenant_id, msg.account_id, msg.openid, a.id, n) catch |err| switch (err) {
            error.NotStarted => return try message_mod.Reply.text(allocator, "秒杀还没开始，敬请期待"),
            error.Ended => return try message_mod.Reply.text(allocator, "秒杀已结束"),
            error.OutOfStock => return try message_mod.Reply.text(allocator, "手慢了，已抢光"),
            error.LimitReached => return try message_mod.Reply.text(allocator, "每人限购，不能抢更多啦"),
            else => return null,
        };
        const ok = std.fmt.allocPrint(allocator, "🎉 抢购成功 {d} 件！", .{n}) catch return null;
        defer allocator.free(ok);
        return try message_mod.Reply.text(allocator, ok);
    }
    return null;
}
