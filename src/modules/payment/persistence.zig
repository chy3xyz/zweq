//! Persistence over the zent Client — wallet, recharge orders, withdraws.

const std = @import("std");
const zent = @import("zent");
const crud = zent.crud_helpers;
const model = @import("model.zig");
const schema = @import("../../schema.zig");

const graph = zent.codegen.graph.buildGraph(&.{ model.Wallet, model.RechargeOrder, model.Withdraw });
pub const infos = graph.types;
/// Shared, application-wide typed client (all schemas registered in schema.zig).
pub const Client = schema.Client;
pub const WalletInfo = infos[0];
pub const RechargeOrderInfo = infos[1];
pub const WithdrawInfo = infos[2];

pub const WalletRow = struct {
    id: i64,
    tenant_id: i64,
    account_id: i64,
    fan_id: i64,
    balance: []const u8,
    updated_at: i64,

    pub fn free(self: WalletRow, allocator: std.mem.Allocator) void {
        allocator.free(self.balance);
    }
};

pub const RechargeOrderRow = struct {
    id: i64,
    tenant_id: i64,
    account_id: i64,
    order_no: []const u8,
    fan_id: i64,
    amount: []const u8,
    channel: []const u8,
    status: []const u8,
    paid_at: i64,
    created_at: i64,

    pub fn free(self: RechargeOrderRow, allocator: std.mem.Allocator) void {
        allocator.free(self.order_no);
        allocator.free(self.amount);
        allocator.free(self.channel);
        allocator.free(self.status);
    }
};

pub const RechargeOrderListResult = struct {
    items: []RechargeOrderRow,
    total: i64,

    pub fn free(self: *RechargeOrderListResult, allocator: std.mem.Allocator) void {
        for (self.items) |r| r.free(allocator);
        allocator.free(self.items);
    }
};

pub const WithdrawRow = struct {
    id: i64,
    tenant_id: i64,
    account_id: i64,
    fan_id: i64,
    amount: []const u8,
    status: []const u8,
    created_at: i64,

    pub fn free(self: WithdrawRow, allocator: std.mem.Allocator) void {
        allocator.free(self.amount);
        allocator.free(self.status);
    }
};

pub const WithdrawListResult = struct {
    items: []WithdrawRow,
    total: i64,

    pub fn free(self: *WithdrawListResult, allocator: std.mem.Allocator) void {
        for (self.items) |r| r.free(allocator);
        allocator.free(self.items);
    }
};

pub const PaymentStore = struct {
    allocator: std.mem.Allocator,
    client: Client,

    pub fn init(allocator: std.mem.Allocator, client: Client) PaymentStore {
        return .{ .allocator = allocator, .client = client };
    }

    fn dupOrder(self: *PaymentStore, e: anytype) !RechargeOrderRow {
        const order_no = try self.allocator.dupe(u8, e.order_no);
        errdefer self.allocator.free(order_no);
        const amount = try self.allocator.dupe(u8, e.amount);
        errdefer self.allocator.free(amount);
        const channel = try self.allocator.dupe(u8, e.channel);
        errdefer self.allocator.free(channel);
        const status = try self.allocator.dupe(u8, e.status);
        errdefer self.allocator.free(status);
        return .{
            .id = e.id,
            .tenant_id = e.tenant_id,
            .account_id = e.account_id,
            .order_no = order_no,
            .fan_id = e.fan_id,
            .amount = amount,
            .channel = channel,
            .status = status,
            .paid_at = e.paid_at,
            .created_at = e.created_at orelse 0,
        };
    }

    fn dupWithdraw(self: *PaymentStore, e: anytype) !WithdrawRow {
        const amount = try self.allocator.dupe(u8, e.amount);
        errdefer self.allocator.free(amount);
        const status = try self.allocator.dupe(u8, e.status);
        errdefer self.allocator.free(status);
        return .{
            .id = e.id,
            .tenant_id = e.tenant_id,
            .account_id = e.account_id,
            .fan_id = e.fan_id,
            .amount = amount,
            .status = status,
            .created_at = e.created_at orelse 0,
        };
    }

    // ── Wallet ────────────────────────────────────────────────────

    pub fn getWallet(self: *PaymentStore, tenant_id: i64, account_id: i64, fan_id: i64) !?WalletRow {
        return self.getWalletOn(self.client, tenant_id, account_id, fan_id);
    }

    /// 事务感知读取，见 `getWallet`。传入 tx.client 时读取的是事务视图。
    pub fn getWalletOn(self: *PaymentStore, client: anytype, tenant_id: i64, account_id: i64, fan_id: i64) !?WalletRow {
        var q = client.wallet.Query();
        defer q.deinit();
        const preds = client.wallet.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.Where(.{preds.fan_idEQ(.{ .int = fan_id })});
        _ = q.Limit(1);
        const entity_opt = try q.First();
        var entity = entity_opt orelse return null;
        defer zent.codegen.deinitEntity(infos, WalletInfo, &entity, self.allocator);
        const balance = try self.allocator.dupe(u8, entity.balance);
        errdefer self.allocator.free(balance);
        return .{
            .id = entity.id,
            .tenant_id = entity.tenant_id,
            .account_id = entity.account_id,
            .fan_id = entity.fan_id,
            .balance = balance,
            .updated_at = entity.updated_at orelse 0,
        };
    }

    /// Create a wallet (balance 0) if absent, return its id.
    pub fn ensureWallet(self: *PaymentStore, tenant_id: i64, account_id: i64, fan_id: i64, now: i64) !i64 {
        return self.ensureWalletOn(self.client, tenant_id, account_id, fan_id, now);
    }

    /// 事务感知版本，见 `ensureWallet`。
    pub fn ensureWalletOn(self: *PaymentStore, client: anytype, tenant_id: i64, account_id: i64, fan_id: i64, now: i64) !i64 {
        const existing = try self.getWalletOn(client, tenant_id, account_id, fan_id);
        if (existing) |w| {
            const id = w.id;
            w.free(self.allocator);
            return id;
        }
        var b = try client.wallet.Create();
        defer b.deinit();
        _ = try b.setFieldValue("tenant_id", tenant_id);
        _ = try b.setFieldValue("account_id", account_id);
        _ = try b.setFieldValue("fan_id", fan_id);
        _ = try b.setFieldValue("balance", "0");
        _ = try b.setFieldValue("created_at", now);
        _ = try b.setFieldValue("updated_at", now);
        var row = try b.Save();
        defer zent.codegen.deinitEntity(infos, WalletInfo, &row, self.allocator);
        return row.id;
    }

    /// 原子扣减钱包（乐观锁：balance >= amount），余额不足返回 false。
    pub fn debitWallet(self: *PaymentStore, allocator: std.mem.Allocator, tenant_id: i64, account_id: i64, fan_id: i64, amount: i64, now: i64) !bool {
        _ = allocator;
        const wid = try self.ensureWallet(tenant_id, account_id, fan_id, now);
        const preds = self.client.wallet.predicates;
        // 余额守卫参数化（zent.sql.RawArgs）：amount 走绑定参数而非拼进 SQL 文本。
        const amount_str = try std.fmt.allocPrint(self.allocator, "{d}", .{amount});
        defer self.allocator.free(amount_str);
        var upd = self.client.wallet.Update();
        defer upd.deinit();
        _ = try upd.setExprArgs("balance", "balance - ?", &.{.{ .string = amount_str }});
        _ = try upd.setFieldValue("updated_at", now);
        _ = try upd.Where(.{ preds.idEQ(.{ .int = wid }), zent.sql.RawArgs("CAST(balance AS INTEGER) >= ?", &.{.{ .int = amount }}) });
        const affected = try upd.Save();
        return affected > 0;
    }

    /// Add `delta` cents to a fan's wallet. Returns the new balance.
    pub fn creditWallet(self: *PaymentStore, tenant_id: i64, account_id: i64, fan_id: i64, delta: i64, now: i64) !i64 {
        return self.creditWalletOn(self.client, tenant_id, account_id, fan_id, delta, now);
    }

    /// 事务感知版本，见 `creditWallet`。传入 tx.client 时充值与入账在同一事务内。
    pub fn creditWalletOn(self: *PaymentStore, client: anytype, tenant_id: i64, account_id: i64, fan_id: i64, delta: i64, now: i64) !i64 {
        const wid = try self.ensureWalletOn(client, tenant_id, account_id, fan_id, now);
        const delta_str = try std.fmt.allocPrint(self.allocator, "{d}", .{delta});
        defer self.allocator.free(delta_str);
        const preds = client.wallet.predicates;
        var upd = client.wallet.Update();
        defer upd.deinit();
        _ = try upd.setExprArgs("balance", "balance + ?", &.{.{ .string = delta_str }});
        _ = try upd.setFieldValue("updated_at", now);
        _ = try upd.Where(.{preds.idEQ(.{ .int = wid })});
        _ = try upd.Save();
        const current = (try self.getWalletOn(client, tenant_id, account_id, fan_id)) orelse return error.Unexpected;
        defer current.free(self.allocator);
        return try std.fmt.parseInt(i64, current.balance, 10);
    }

    // ── RechargeOrder ─────────────────────────────────────────────

    pub fn createOrder(self: *PaymentStore, tenant_id: i64, account_id: i64, order_no: []const u8, fan_id: i64, amount: i64, channel: []const u8, now: i64) !i64 {
        const amount_str = try std.fmt.allocPrint(self.allocator, "{d}", .{amount});
        defer self.allocator.free(amount_str);
        var b = try self.client.recharge_order.Create();
        defer b.deinit();
        _ = try b.setFieldValue("tenant_id", tenant_id);
        _ = try b.setFieldValue("account_id", account_id);
        _ = try b.setFieldValue("order_no", order_no);
        _ = try b.setFieldValue("fan_id", fan_id);
        _ = try b.setFieldValue("amount", amount_str);
        _ = try b.setFieldValue("channel", channel);
        _ = try b.setFieldValue("status", "pending");
        _ = try b.setFieldValue("paid_at", @as(i64, 0));
        _ = try b.setFieldValue("created_at", now);
        _ = try b.setFieldValue("updated_at", now);
        var row = try b.Save();
        defer zent.codegen.deinitEntity(infos, RechargeOrderInfo, &row, self.allocator);
        return row.id;
    }

    /// Look up an order by order_no without a tenant filter — used by the
    /// WeChat Pay notify (the notify body carries no tenant id).
    pub fn getOrderByNoAny(self: *PaymentStore, order_no: []const u8) !?RechargeOrderRow {
        var q = self.client.recharge_order.Query();
        defer q.deinit();
        const preds = self.client.recharge_order.predicates;
        _ = try q.Where(.{preds.order_noEQ(.{ .string = order_no })});
        _ = q.Limit(1);
        const entity_opt = try q.First();
        var entity = entity_opt orelse return null;
        defer zent.codegen.deinitEntity(infos, RechargeOrderInfo, &entity, self.allocator);
        return try self.dupOrder(entity);
    }

    pub fn getOrderByNo(self: *PaymentStore, tenant_id: i64, order_no: []const u8) !?RechargeOrderRow {
        return self.getOrderByNoOn(self.client, tenant_id, order_no);
    }

    /// 事务感知读取，见 `getOrderByNo`。
    pub fn getOrderByNoOn(self: *PaymentStore, client: anytype, tenant_id: i64, order_no: []const u8) !?RechargeOrderRow {
        var q = client.recharge_order.Query();
        defer q.deinit();
        const preds = client.recharge_order.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.order_noEQ(.{ .string = order_no })});
        _ = q.Limit(1);
        const entity_opt = try q.First();
        var entity = entity_opt orelse return null;
        defer zent.codegen.deinitEntity(infos, RechargeOrderInfo, &entity, self.allocator);
        return try self.dupOrder(entity);
    }

    /// Atomically flip a pending order to paid. Returns false when the order
    /// was not pending (idempotency guard for duplicate payment notifies).
    pub fn markOrderPaid(self: *PaymentStore, tenant_id: i64, order_no: []const u8, now: i64) !bool {
        return self.markOrderPaidOn(self.client, tenant_id, order_no, now);
    }

    /// 事务感知版本，见 `markOrderPaid`。状态守卫放进 WHERE（条件更新
    /// status='pending'），由数据库保证并发回调只有一个能翻转成功；
    /// affected 为 0 表示订单不存在或非 pending（重复回调），由调用方按幂等成功处理。
    pub fn markOrderPaidOn(_: *PaymentStore, client: anytype, tenant_id: i64, order_no: []const u8, now: i64) !bool {
        const preds = client.recharge_order.predicates;
        var upd = client.recharge_order.Update();
        defer upd.deinit();
        _ = try upd.set("status", .{ .string = "paid" });
        _ = try upd.setFieldValue("paid_at", now);
        _ = try upd.setFieldValue("updated_at", now);
        _ = try upd.Where(.{
            preds.tenant_idEQ(.{ .int = tenant_id }),
            preds.order_noEQ(.{ .string = order_no }),
            preds.statusEQ(.{ .string = "pending" }),
        });
        const affected = try upd.Save();
        return affected > 0;
    }

    pub fn listOrders(self: *PaymentStore, page: usize, page_size: usize, tenant_id: i64, account_id: i64) !RechargeOrderListResult {
        var q = self.client.recharge_order.Query();
        defer q.deinit();
        const preds = self.client.recharge_order.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderDesc("id")});

        var paged = try q.paged(page, page_size);
        defer paged.deinit();

        var out = try self.allocator.alloc(RechargeOrderRow, paged.items.items.len);
        var n: usize = 0;
        errdefer {
            for (out[0..n]) |r| r.free(self.allocator);
            self.allocator.free(out);
        }
        for (paged.items.items) |e| {
            out[n] = try self.dupOrder(e);
            n += 1;
        }
        return .{ .items = out, .total = paged.total };
    }

    // ── Withdraw ──────────────────────────────────────────────────

    pub fn createWithdraw(self: *PaymentStore, tenant_id: i64, account_id: i64, fan_id: i64, amount: i64, now: i64) !i64 {
        const amount_str = try std.fmt.allocPrint(self.allocator, "{d}", .{amount});
        defer self.allocator.free(amount_str);
        var b = try self.client.withdraw.Create();
        defer b.deinit();
        _ = try b.setFieldValue("tenant_id", tenant_id);
        _ = try b.setFieldValue("account_id", account_id);
        _ = try b.setFieldValue("fan_id", fan_id);
        _ = try b.setFieldValue("amount", amount_str);
        _ = try b.setFieldValue("status", "pending");
        _ = try b.setFieldValue("created_at", now);
        var row = try b.Save();
        defer zent.codegen.deinitEntity(infos, WithdrawInfo, &row, self.allocator);
        return row.id;
    }

    pub fn listWithdraws(self: *PaymentStore, page: usize, page_size: usize, tenant_id: i64, account_id: i64) !WithdrawListResult {
        var q = self.client.withdraw.Query();
        defer q.deinit();
        const preds = self.client.withdraw.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderDesc("id")});

        var paged = try q.paged(page, page_size);
        defer paged.deinit();

        var out = try self.allocator.alloc(WithdrawRow, paged.items.items.len);
        var n: usize = 0;
        errdefer {
            for (out[0..n]) |r| r.free(self.allocator);
            self.allocator.free(out);
        }
        for (paged.items.items) |e| {
            out[n] = try self.dupWithdraw(e);
            n += 1;
        }
        return .{ .items = out, .total = paged.total };
    }
};
