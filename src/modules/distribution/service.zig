//! Distribution service — 三级分销业务 + message 模块 Receiver 接入。
//!
//! 分销员注册（可带上级）→ 消费时沿上级链最多 3 级按比例分佣 → 佣金提现。
//! 分佣比例默认 10%/5%/3%，可用模块 config JSON 覆盖
//! （`{"level1":0.10,"level2":0.05,"level3":0.03}`，小数比例）。

const std = @import("std");
const zigmodu = @import("zigmodu");
const zent = @import("zent");
const persist = @import("persistence.zig");
const message_mod = @import("../message/service.zig");

pub const DistributorRow = persist.DistributorRow;
pub const CommissionRow = persist.CommissionRow;
pub const DistributorListResult = persist.DistributorListResult;
pub const CommissionListResult = persist.CommissionListResult;

pub const DistributionError = error{
    InvalidInput,
    NotFound,
    AlreadyDistributor,
    InsufficientBalance,
    InvalidParent,
    Unexpected,
};

pub const DEFAULT_RATES = [3]f64{ 0.10, 0.05, 0.03 };

pub const DistributionService = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    store: *persist.DistributionStore,
    rates: [3]f64 = DEFAULT_RATES,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, store: *persist.DistributionStore) DistributionService {
        return .{ .allocator = allocator, .io = io, .store = store };
    }

    fn now(self: *DistributionService) i64 {
        return zigmodu.time.wallClockSeconds(self.io);
    }

    /// 设置分佣比例（JSON，如 `{"level1":0.10,"level2":0.05,"level3":0.03}`）。
    pub fn setRatesJson(self: *DistributionService, json: []const u8) void {
        if (json.len == 0) {
            self.rates = DEFAULT_RATES;
            return;
        }
        var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, json, .{}) catch {
            self.rates = DEFAULT_RATES;
            return;
        };
        defer parsed.deinit();
        switch (parsed.value) {
            .object => |obj| {
                inline for (0..3) |i| {
                    const key = comptime "level" ++ std.fmt.comptimePrint("{d}", .{i + 1});
                    if (obj.get(key)) |v| {
                        switch (v) {
                            .float => |f| self.rates[i] = @max(0, @min(1, f)),
                            .integer => |n| self.rates[i] = @max(0, @min(1, @as(f64, @floatFromInt(n)))),
                            else => {},
                        }
                    }
                }
            },
            else => {},
        }
    }

    pub fn listDistributors(self: *DistributionService, page: usize, page_size: usize, tenant_id: i64, account_id: i64) DistributionError!DistributorListResult {
        return self.store.listDistributors(page, page_size, tenant_id, account_id) catch error.Unexpected;
    }

    pub fn listCommissions(self: *DistributionService, page: usize, page_size: usize, tenant_id: i64, account_id: i64) DistributionError!CommissionListResult {
        return self.store.listCommissions(page, page_size, tenant_id, account_id) catch error.Unexpected;
    }

    pub fn getDistributor(self: *DistributionService, tenant_id: i64, account_id: i64, openid: []const u8) DistributionError!?DistributorRow {
        return self.store.getByOpenid(tenant_id, account_id, openid) catch error.Unexpected;
    }

    /// 加盟：成为分销员；parent_openid 非空时校验其必须是有效分销员（且不能是自己）。
    pub fn becomeDistributor(self: *DistributionService, tenant_id: i64, account_id: i64, openid: []const u8, parent_openid: []const u8) DistributionError!void {
        if (std.mem.trim(u8, openid, " \t").len == 0) return error.InvalidInput;
        if (self.store.getByOpenid(tenant_id, account_id, openid) catch return error.Unexpected) |existing| {
            existing.free(self.allocator);
            return error.AlreadyDistributor;
        }
        const parent = std.mem.trim(u8, parent_openid, " \t");
        if (parent.len > 0) {
            if (std.mem.eql(u8, parent, openid)) return error.InvalidParent;
            const p_opt = self.store.getByOpenid(tenant_id, account_id, parent) catch return error.Unexpected;
            const p = p_opt orelse return error.InvalidParent;
            p.free(self.allocator);
        }
        _ = self.store.createDistributor(tenant_id, account_id, openid, parent, self.now()) catch return error.Unexpected;
    }

    /// 三级分佣：购买者消费 order_amount（分），沿上级链最多 3 级按比例入账。
    /// 返回分佣笔数。
    pub fn distribute(self: *DistributionService, tenant_id: i64, account_id: i64, buyer_openid: []const u8, order_amount: i64) DistributionError!usize {
        if (order_amount <= 0) return error.InvalidInput;
        var count: usize = 0;
        var level: usize = 0;
        var current: []const u8 = std.mem.trim(u8, buyer_openid, " \t");
        var owned: ?[]u8 = null;
        defer if (owned) |o| self.allocator.free(o);

        // 沿上级链逐级找分销员（buyer 自己不是分销员时从上级开始）。
        while (level < 3) {
            const parent_opt = self.parentOf(tenant_id, account_id, current) catch return error.Unexpected;
            const parent = parent_opt orelse break;
            defer parent.free(self.allocator);

            const amount_i: i64 = @intFromFloat(@as(f64, @floatFromInt(order_amount)) * self.rates[level]);
            if (amount_i > 0) {
                if (self.store.addCommission(self.allocator, parent.id, amount_i) catch false) {
                    _ = self.store.createCommission(tenant_id, account_id, parent.openid, buyer_openid, @intCast(level + 1), amount_i, self.now()) catch {};
                    count += 1;
                }
            }

            if (level == 2) break; // 最多 3 级
            if (owned) |o| self.allocator.free(o);
            owned = self.allocator.dupe(u8, parent.openid) catch break;
            current = owned.?;
            level += 1;
        }
        return count;
    }

    /// 提现：余额充足则扣减并生成佣金记录（status=0 pending）。
    pub fn withdraw(self: *DistributionService, tenant_id: i64, account_id: i64, openid: []const u8, amount: i64) DistributionError!void {
        if (amount <= 0) return error.InvalidInput;
        const d_opt = self.store.getByOpenid(tenant_id, account_id, openid) catch return error.Unexpected;
        const d = d_opt orelse return error.NotFound;
        defer d.free(self.allocator);
        if (d.commission_balance < amount) return error.InsufficientBalance;
        if (!(self.store.deductCommission(self.allocator, d.id, amount) catch return error.Unexpected)) return error.InsufficientBalance;
        _ = self.store.createCommission(tenant_id, account_id, openid, "", 0, -amount, self.now()) catch {};
    }

    /// 某 openid 的上级分销员（openid 可能是分销员或普通购买者）。
    fn parentOf(self: *DistributionService, tenant_id: i64, account_id: i64, openid: []const u8) !?DistributorRow {
        const d_opt = self.store.getByOpenid(tenant_id, account_id, openid) catch return error.Unexpected;
        const d = d_opt orelse return null;
        defer d.free(self.allocator);
        if (d.parent_openid.len == 0) return null;
        return self.store.getByOpenid(tenant_id, account_id, d.parent_openid) catch error.Unexpected;
    }
};

/// Receiver context。
pub const ReceiverCtx = struct {
    io: std.Io,
    dist_svc: *DistributionService,
};

/// `Receiver.handle`：识别「加盟」（注册分销员）与「分销」（查佣金/状态）。
pub fn receiverHandle(ctx: ?*anyopaque, allocator: std.mem.Allocator, msg: message_mod.IncomingMessage) anyerror!?message_mod.Reply {
    const c: *ReceiverCtx = @ptrCast(@alignCast(ctx orelse return null));
    if (!std.mem.eql(u8, msg.msg_type, "text")) return null;

    if (std.mem.eql(u8, msg.content, "加盟")) {
        c.dist_svc.becomeDistributor(msg.tenant_id, msg.account_id, msg.openid, "") catch |err| switch (err) {
            error.AlreadyDistributor => return try message_mod.Reply.text(allocator, "你已经是分销员啦"),
            else => return null,
        };
        return try message_mod.Reply.text(allocator, "🎉 加盟成功！消费返佣自动到账，回复「分销」查看佣金");
    }

    if (std.mem.eql(u8, msg.content, "分销")) {
        const d_opt = c.dist_svc.getDistributor(msg.tenant_id, msg.account_id, msg.openid) catch return null;
        const d = d_opt orelse return try message_mod.Reply.text(allocator, "你还没有开通分销，回复「加盟」免费开通");
        defer d.free(allocator);
        var buf = std.ArrayList(u8).empty;
        defer buf.deinit(allocator);
        try buf.appendSlice(allocator, "💰 我的分销\n佣金余额：");
        const balance = d.commission_balance;
        const balance_yuan = @divTrunc(balance, 100);
        const balance_fen = @mod(balance, 100);
        const bal = if (balance_fen < 10)
            (std.fmt.allocPrint(allocator, "{d}.0{d} 元", .{ balance_yuan, balance_fen }) catch "?")
        else
            (std.fmt.allocPrint(allocator, "{d}.{d} 元", .{ balance_yuan, balance_fen }) catch "?");
        defer allocator.free(bal);
        try buf.appendSlice(allocator, bal);
        try buf.appendSlice(allocator, "\n累计佣金：");
        const total = std.fmt.allocPrint(allocator, "{d}", .{d.total_commission}) catch "?";
        defer allocator.free(total);
        try buf.appendSlice(allocator, total);
        try buf.appendSlice(allocator, " 分\n邀请好友下单，三级返佣自动到账！");
        return try message_mod.Reply.text(allocator, buf.items);
    }
    return null;
}
