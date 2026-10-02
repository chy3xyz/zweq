//! 请求预算 → 存储层（审计 P1）：db.zig 桥（execContext/applyDeadline/
//! budgetSpent）、request_budget 闸门、事务入口 Budget 变体的行为测试。

const std = @import("common.zig").std;
const zigmodu = @import("common.zig").zigmodu;
const zent = @import("common.zig").zent;
const db_mod = @import("common.zig").db_mod;
const payment = @import("common.zig").payment;
const member = @import("common.zig").member;
const points = @import("common.zig").points;
const openMemory = @import("common.zig").openMemory;
const request_budget = @import("../middleware/request_budget.zig");
const http = zigmodu.http;

fn monoMs() i64 {
    return @divFloor(zent.sql_driver.monotonicNs(), std.time.ns_per_ms);
}

test "request_budget: execContext 毫秒 deadline 转 zent 纳秒（null 预算 = 无界）" {
    const none = db_mod.execContext(null);
    try std.testing.expect(none.deadline_ns == null);
    const ec = db_mod.execContext(12_345);
    try std.testing.expectEqual(@as(i64, 12_345 * std.time.ns_per_ms), ec.deadline_ns.?);
}

test "request_budget: budgetSpent 判定（null 永不耗尽）" {
    try std.testing.expect(!db_mod.budgetSpent(null));
    try std.testing.expect(db_mod.budgetSpent(monoMs() - 10));
    try std.testing.expect(!db_mod.budgetSpent(monoMs() + 60_000));
}

test "request_budget: applyDeadline 盖进 zent builder，null 预算不触碰" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var q = env.client.recharge_order.Query();
    defer q.deinit();
    try std.testing.expect(q.execution_context.deadline_ns == null);
    db_mod.applyDeadline(&q, null);
    try std.testing.expect(q.execution_context.deadline_ns == null);
    db_mod.applyDeadline(&q, 777);
    try std.testing.expectEqual(@as(i64, 777 * std.time.ns_per_ms), q.execution_context.deadline_ns.?);
}

test "request_budget: 事务入口预算耗尽前置拒绝，充足预算正常入账" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var payment_store = payment.persistence.PaymentStore.init(allocator, env.client);
    var payment_svc = payment.service.PaymentService.init(allocator, std.testing.io, &payment_store);

    const order = try payment_svc.createRechargeOrder(allocator, 1, 5, 42, 1000);
    defer order.free(allocator);

    // 已耗尽的预算：不启动事务，直接 RequestTimeout（订单仍 pending、钱包未入账）。
    try std.testing.expectError(error.RequestTimeout, payment_svc.completeRechargeBudget(1, order.order_no, monoMs() - 1));
    const pending = (try payment_store.getOrderByNo(1, order.order_no)).?;
    defer pending.free(allocator);
    try std.testing.expectEqualStrings("pending", pending.status);

    // 充足预算：事务正常获取并提交。
    try std.testing.expect(try payment_svc.completeRechargeBudget(1, order.order_no, monoMs() + 60_000));
    const wallet = (try payment_svc.walletBalance(1, 5, 42)).?;
    defer wallet.free(allocator);
    try std.testing.expectEqualStrings("1000", wallet.balance);
}

test "request_budget: 列表查询 Budget 变体（null/充足预算结果一致）" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var payment_store = payment.persistence.PaymentStore.init(allocator, env.client);
    var payment_svc = payment.service.PaymentService.init(allocator, std.testing.io, &payment_store);

    const order = try payment_svc.createRechargeOrder(allocator, 1, 5, 42, 500);
    defer order.free(allocator);

    var r0 = try payment_svc.listOrders(1, 10, 1, 5);
    defer r0.free(allocator);
    var r1 = try payment_svc.listOrdersBudget(1, 10, 1, 5, monoMs() + 60_000);
    defer r1.free(allocator);
    try std.testing.expectEqual(@as(i64, 1), r0.total);
    try std.testing.expectEqual(r0.total, r1.total);
    try std.testing.expectEqualStrings(r0.items[0].order_no, r1.items[0].order_no);
}

test "request_budget: points 列表 Budget 变体（null/充足预算结果一致）" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var fan_store = member.persistence.FanStore.init(allocator, env.client);
    var points_store = points.persistence.PointsStore.init(allocator, env.client);
    var points_svc = points.service.PointsService.init(allocator, std.testing.io, &points_store, &fan_store);

    _ = try points_svc.createProduct(1, 5, "保温杯", 100, 10, 1, "", "");
    _ = try points_store.createOrder(1, 5, "openid-1", 1, "保温杯", 100, 0);

    // 积分产品分页列表：原方法（null 预算）与 Budget 变体（充足预算）结果一致。
    var p0 = try points_svc.listProducts(1, 10, 1, 5, "", -1);
    defer p0.free(allocator);
    var p1 = try points_svc.listProductsBudget(1, 10, 1, 5, "", -1, monoMs() + 60_000);
    defer p1.free(allocator);
    try std.testing.expectEqual(@as(i64, 1), p0.total);
    try std.testing.expectEqual(p0.total, p1.total);
    try std.testing.expectEqualStrings(p0.items[0].name, p1.items[0].name);

    // 兑换订单列表：行/数组由 store 分配器分配，用拥有者释放。
    const o0 = try points_svc.listOrders(1, 5, null);
    defer {
        for (o0) |r| r.free(allocator);
        allocator.free(o0);
    }
    const o1 = try points_svc.listOrdersBudget(1, 5, null, monoMs() + 60_000);
    defer {
        for (o1) |r| r.free(allocator);
        allocator.free(o1);
    }
    try std.testing.expectEqual(o0.len, o1.len);
    try std.testing.expectEqualStrings(o0[0].product_name, o1[0].product_name);
}

// ── 闸门中间件 ──────────────────────────────────────────────

var next_calls: usize = 0;

fn countingNext(ctx: *http.Context) anyerror!void {
    _ = ctx;
    next_calls += 1;
}

fn boomNext(ctx: *http.Context) anyerror!void {
    _ = ctx;
    next_calls += 1;
    return error.Boom;
}

fn timeoutNext(ctx: *http.Context) anyerror!void {
    _ = ctx;
    next_calls += 1;
    return error.RequestTimeout;
}

fn initCtx(allocator: std.mem.Allocator) !http.Context {
    return http.Context.init(allocator, .GET, "/api/v1/payments");
}

test "request_budget: 闸门入口快失败——预算耗尽立即 408，next 不执行" {
    const allocator = std.testing.allocator;
    const mw = request_budget.budgetGate(true);
    var ctx = try initCtx(allocator);
    defer ctx.deinit();
    ctx.deadline_ms = monoMs() - 1; // 预算已耗尽

    next_calls = 0;
    try mw.func(&ctx, countingNext, mw.user_data);
    try std.testing.expectEqual(@as(usize, 0), next_calls);
    try std.testing.expect(ctx.responded);
    try std.testing.expectEqual(@as(u16, 408), ctx.status_code);
    try std.testing.expect(std.mem.indexOf(u8, ctx.response_body.items, "请求超时") != null);
}

test "request_budget: 闸门放行——预算充足或无预算时 next 执行" {
    const allocator = std.testing.allocator;
    const mw = request_budget.budgetGate(true);

    var ctx_live = try initCtx(allocator);
    defer ctx_live.deinit();
    ctx_live.deadline_ms = monoMs() + 60_000;
    next_calls = 0;
    try mw.func(&ctx_live, countingNext, mw.user_data);
    try std.testing.expectEqual(@as(usize, 1), next_calls);
    try std.testing.expect(!ctx_live.responded);

    var ctx_unbounded = try initCtx(allocator);
    defer ctx_unbounded.deinit();
    next_calls = 0;
    try mw.func(&ctx_unbounded, countingNext, mw.user_data);
    try std.testing.expectEqual(@as(usize, 1), next_calls);
    try std.testing.expect(!ctx_unbounded.responded);
}

test "request_budget: 闸门关闭时直通（灰度开关）" {
    const allocator = std.testing.allocator;
    const mw = request_budget.budgetGate(false);
    var ctx = try initCtx(allocator);
    defer ctx.deinit();
    ctx.deadline_ms = monoMs() - 1; // 即使预算耗尽也直通

    next_calls = 0;
    try mw.func(&ctx, countingNext, mw.user_data);
    try std.testing.expectEqual(@as(usize, 1), next_calls);
    try std.testing.expect(!ctx.responded);
}

test "request_budget: 下游错误映射——RequestTimeout 或预算耗尽 → 408，其余原样上抛" {
    const allocator = std.testing.allocator;
    const mw = request_budget.budgetGate(true);

    // error.RequestTimeout（存储层显式上报）：预算还有余量也判 408。
    var ctx1 = try initCtx(allocator);
    defer ctx1.deinit();
    ctx1.deadline_ms = monoMs() + 60_000;
    try mw.func(&ctx1, timeoutNext, mw.user_data);
    try std.testing.expect(ctx1.responded);
    try std.testing.expectEqual(@as(u16, 408), ctx1.status_code);

    // 其他错误但预算已耗尽：客户端早已放弃，如实回 408。
    var ctx2 = try initCtx(allocator);
    defer ctx2.deinit();
    ctx2.deadline_ms = monoMs() - 1;
    try mw.func(&ctx2, boomNext, mw.user_data);
    try std.testing.expect(ctx2.responded);
    try std.testing.expectEqual(@as(u16, 408), ctx2.status_code);

    // 其他错误且预算充足：原样上抛给框架（500 路径）。
    var ctx3 = try initCtx(allocator);
    defer ctx3.deinit();
    ctx3.deadline_ms = monoMs() + 60_000;
    try std.testing.expectError(error.Boom, mw.func(&ctx3, boomNext, mw.user_data));
    try std.testing.expect(!ctx3.responded);
}
