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

/// 抢购记录视图行 = SeckillOrderRow + `activity_title`（管理端订单列表富化输出）。
pub const SeckillOrderView = struct {
    id: i64,
    account_id: i64,
    openid: []const u8,
    activity_id: i64,
    activity_title: []const u8,
    quantity: i64,
    created_at: i64,

    pub fn free(self: SeckillOrderView, allocator: std.mem.Allocator) void {
        allocator.free(self.openid);
        allocator.free(self.activity_title);
    }
};

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

    pub fn createActivity(self: *SeckillService, tenant_id: i64, account_id: i64, title: []const u8, price: i64, original_price: i64, stock: i64, per_user: i64, start_at: i64, end_at: i64, status: i64) SeckillError!i64 {
        if (std.mem.trim(u8, title, " \t").len == 0 or stock <= 0) return error.InvalidInput;
        if (per_user <= 0) return error.InvalidInput;
        if (start_at > 0 and end_at > 0 and start_at >= end_at) return error.InvalidInput;
        return self.store.createActivity(tenant_id, account_id, title, price, original_price, stock, per_user, start_at, end_at, status, self.now()) catch error.Unexpected;
    }

    /// `status` 为 -1 表示不过滤；0 下架 / 1 上架（C 端固定传 1）。
    pub fn listActivities(self: *SeckillService, page: usize, page_size: usize, tenant_id: i64, account_id: i64, keyword: []const u8, status: i64) SeckillError!SeckillListResult {
        return self.store.listActivities(page, page_size, tenant_id, account_id, keyword, status) catch error.Unexpected;
    }

    /// 上下架：1 上架 / 0 下架。
    pub fn setActivityStatus(self: *SeckillService, id: i64, status: i64) SeckillError!bool {
        return self.store.setActivityStatus(id, status, self.now()) catch error.Unexpected;
    }

    /// 按 id 取单条（tenant 过滤）。测试/内部读取用；管理端走 `getActivityById`。
    pub fn getActivity(self: *SeckillService, tenant_id: i64, id: i64) SeckillError!?SeckillActivityRow {
        return self.store.getActivity(tenant_id, id) catch error.Unexpected;
    }

    /// 按 id 取单条（tenant 过滤）——管理端详情/更新/删除先经此校验存在性
    /// （跨租户不可见，效果同 NotFound）。
    pub fn getActivityById(self: *SeckillService, tenant_id: i64, id: i64) SeckillError!?SeckillActivityRow {
        return self.store.getById(tenant_id, id) catch error.Unexpected;
    }

    /// 整体更新秒杀活动（account 作用域不变：account_id 不参与更新）。
    /// `title` 空 / `stock <= 0` / `per_user < 1` / 时间窗非法 → InvalidInput；
    /// 库存不得小于已售（`stock < sold`）→ InvalidInput；活动不存在或不属于本
    /// tenant → NotFound。store 影响 0 行也视为成功（幂等）。校验规则跟随 `createActivity`。
    pub fn updateActivity(self: *SeckillService, tenant_id: i64, id: i64, title: []const u8, price: i64, original_price: i64, stock: i64, per_user: i64, start_at: i64, end_at: i64, status: i64) SeckillError!void {
        if (std.mem.trim(u8, title, " \t").len == 0 or stock <= 0) return error.InvalidInput;
        if (per_user <= 0) return error.InvalidInput;
        if (start_at > 0 and end_at > 0 and start_at >= end_at) return error.InvalidInput;
        const a_opt = self.store.getById(tenant_id, id) catch return error.Unexpected;
        const a = a_opt orelse return error.NotFound;
        defer a.free(self.allocator);
        if (stock < a.sold) return error.InvalidInput;
        _ = self.store.update(id, title, price, original_price, stock, per_user, start_at, end_at, status, self.now()) catch return error.Unexpected;
    }

    /// 删除活动及其全部抢购记录。活动不存在或不属于本 tenant → NotFound；
    /// 先删抢购记录再删活动（避免孤儿记录）。
    pub fn deleteActivity(self: *SeckillService, tenant_id: i64, id: i64) SeckillError!void {
        const a_opt = self.store.getById(tenant_id, id) catch return error.Unexpected;
        const a = a_opt orelse return error.NotFound;
        defer a.free(self.allocator);
        self.store.deleteOrdersByActivityId(id) catch return error.Unexpected;
        self.store.deleteById(id) catch return error.Unexpected;
    }

    pub fn listOrders(self: *SeckillService, page: usize, page_size: usize, tenant_id: i64, account_id: i64, openid: []const u8, keyword: []const u8) SeckillError!persist.SeckillOrderListResult {
        return self.store.listOrders(page, page_size, tenant_id, account_id, openid, keyword) catch error.Unexpected;
    }

    /// 富化抢购记录：逐行按 activity_id 补齐活动标题（页 ≤ 100，逐行一次小查询
    /// 可接受；活动已删除/跨租户时该行标题为空串）。返回带 `activity_title` 的
    /// 视图行列表（caller 逐行 `free` 后 `allocator.free` 切片）。
    pub fn enrichOrders(self: *SeckillService, allocator: std.mem.Allocator, tenant_id: i64, rows: []const persist.SeckillOrderRow) SeckillError![]SeckillOrderView {
        const out = allocator.alloc(SeckillOrderView, rows.len) catch return error.Unexpected;
        var n: usize = 0;
        errdefer {
            for (out[0..n]) |v| v.free(allocator);
            allocator.free(out);
        }
        for (rows) |r| {
            out[n] = try self.dupOrderView(allocator, tenant_id, r);
            n += 1;
        }
        return out;
    }

    /// 富化 helper：单个订单行 → 视图行（活动已不存在时 `activity_title` 为空串）。
    fn dupOrderView(self: *SeckillService, allocator: std.mem.Allocator, tenant_id: i64, r: persist.SeckillOrderRow) SeckillError!SeckillOrderView {
        const openid = allocator.dupe(u8, r.openid) catch return error.Unexpected;
        errdefer allocator.free(openid);
        const a_opt = self.store.getById(tenant_id, r.activity_id) catch return error.Unexpected;
        var title: []const u8 = undefined;
        if (a_opt) |a| {
            defer a.free(self.allocator);
            title = allocator.dupe(u8, a.title) catch return error.Unexpected;
        } else {
            title = allocator.dupe(u8, "") catch return error.Unexpected;
        }
        errdefer allocator.free(title);
        return .{
            .id = r.id,
            .account_id = r.account_id,
            .openid = openid,
            .activity_id = r.activity_id,
            .activity_title = title,
            .quantity = r.quantity,
            .created_at = r.created_at,
        };
    }

    /// 抢购：时间窗 → 限购（快速路径）→ 原子库存 → 限购复核 → 落单。
    /// 扣库存后落单/复核失败一律回补库存，杜绝「扣了库存没订单」的永久流失。
    pub fn rush(self: *SeckillService, tenant_id: i64, account_id: i64, openid: []const u8, activity_id: i64, quantity: i64) SeckillError!i64 {
        if (quantity <= 0) return error.InvalidInput;
        // tenant 过滤：跨租户活动不可见（效果同 NotFound），杜绝越权抢别租户活动。
        const a_opt = self.store.getActivity(tenant_id, activity_id) catch return error.Unexpected;
        const a = a_opt orelse return error.NotFound;
        defer a.free(self.allocator);
        const now_secs = self.now();
        // 下架活动不可抢：C 端列表与抢购入口都必须挡住。
        if (a.status != 1) return error.NotFound;
        if (a.start_at > 0 and now_secs < a.start_at) return error.NotStarted;
        if (a.end_at > 0 and now_secs > a.end_at) return error.Ended;

        // 限购优先（快速路径）：已超限直接拒绝，不触碰库存。
        const already = self.store.countOrdered(tenant_id, activity_id, openid) catch return error.Unexpected;
        if (already + quantity > a.per_user) return error.LimitReached;

        // 库存：sold + 本次 > stock → 售罄。
        if (a.sold + quantity > a.stock) return error.OutOfStock;

        // 原子扣库存（乐观锁），失败即超卖/并发竞争 → 库存不足。
        if (!(self.store.tryConsumeStock(self.allocator, activity_id, quantity) catch return error.Unexpected)) return error.OutOfStock;

        // 权威限购复核：扣库存成功后、落单前再 count 一次。快速路径与扣库存
        // 之间可能已并发落单，彻底消除该竞态需 (activity_id, openid) 唯一索引或
        // 跨模块事务，本修复把超限窗口收敛到最小；复核不通过须回补已扣库存。
        const ordered = self.store.countOrdered(tenant_id, activity_id, openid) catch {
            self.rollbackConsumedStock(activity_id, quantity);
            return error.Unexpected;
        };
        if (ordered + quantity > a.per_user) {
            self.rollbackConsumedStock(activity_id, quantity);
            return error.LimitReached;
        }

        return self.store.createOrder(tenant_id, account_id, openid, activity_id, quantity, now_secs) catch {
            // 落单失败必须回补已扣库存，否则漏单导致库存永久流失（P0）。
            self.rollbackConsumedStock(activity_id, quantity);
            return error.Unexpected;
        };
    }

    /// 回补 rush 已扣库存；回补失败仅记日志（已扣库存无法自动恢复，需人工对账）。
    fn rollbackConsumedStock(self: *SeckillService, activity_id: i64, quantity: i64) void {
        self.store.restoreStock(activity_id, quantity) catch |err| {
            std.log.err("seckill 回补库存失败: activity_id={d} quantity={d} err={s}", .{ activity_id, quantity, @errorName(err) });
        };
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
        const price_cents = std.fmt.parseInt(i64, a.price, 10) catch return null;
        const price_yuan = @divTrunc(price_cents, 100);
        const price_fen = @mod(price_cents, 100);
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
