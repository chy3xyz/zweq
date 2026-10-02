//! Prometheus HTTP metrics — request counter, status buckets, latency
//! (avg/max gauge + duration histogram) and uptime, collected by our
//! middleware on top of zigmodu's HttpMetricsCollector, plus
//! dispatcher / rate-limit / DB-pool counters bound from main.

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const task_service = @import("../modules/task/service.zig");
const db_mod = @import("../db.zig");
const rate_limit = @import("rate_limit.zig");

/// 请求耗时直方图桶边界（秒，Prometheus 惯例）。le 标签用 comptime 字符串
/// 常量导出，保证格式稳定（`0.1` 而非 `0.100000`）。
const duration_bucket_bounds = [_]f64{ 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10 };
const duration_bucket_labels = [_][]const u8{ "0.005", "0.01", "0.025", "0.05", "0.1", "0.25", "0.5", "1", "2.5", "5", "10" };

/// 仅含算术运算的微小临界区互斥锁（镜像 zigmodu core/SpinLock 的形制）：
/// 自旋短暂后让出时间片，不烧核。observe/snapshot 只累加计数，临界区
/// 不会阻塞，无需 futex 版的 std.Io.Mutex（其 lock/unlock 要传 Io，这里
/// 拿不到）。
const HistLock = struct {
    state: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    fn lock(self: *HistLock) void {
        var spins: u32 = 0;
        while (self.state.cmpxchgWeak(false, true, .acquire, .monotonic) != null) {
            spins += 1;
            if (spins < 32) {
                std.atomic.spinLoopHint();
            } else {
                std.Thread.yield() catch {};
            }
        }
    }

    fn unlock(self: *HistLock) void {
        self.state.store(false, .release);
    }
};

/// 进程内请求耗时直方图。zigmodu 的 HttpMetricsCollector 只保留
/// total/min/max，拿不到分桶所需的历史样本，所以由我们自己的
/// middleware 同点双写（见 metricsMiddleware）；导出时照 Prometheus
/// 惯例输出 `_bucket{le=...}` / `_sum` / `_count`，与上方 avg/max
/// gauge 互补。
pub const DurationHistogram = struct {
    /// counts[i] = 耗时 <= duration_bucket_bounds[i] 的请求数（累积）。
    counts: [duration_bucket_bounds.len]u64 = @splat(0),
    sum_seconds: f64 = 0,
    count: u64 = 0,
    mutex: HistLock = .{},

    pub fn observe(self: *DurationHistogram, duration_seconds: f64) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.count += 1;
        self.sum_seconds += duration_seconds;
        for (&self.counts, duration_bucket_bounds) |*c, bound| {
            if (duration_seconds <= bound) c.* += 1;
        }
    }

    pub const Snapshot = struct {
        counts: [duration_bucket_bounds.len]u64,
        sum_seconds: f64,
        count: u64,
    };

    pub fn snapshot(self: *DurationHistogram) Snapshot {
        self.mutex.lock();
        defer self.mutex.unlock();
        return .{ .counts = self.counts, .sum_seconds = self.sum_seconds, .count = self.count };
    }
};

/// 与 zigmodu httpMetricsMiddleware 同构，但耗时同时双写直方图。不用
/// zigmodu 版中间件的原因是它的 elapsed 是整秒截断的（i64 秒差），
/// 亚秒桶全挤进 le=0.005 一档；这里用 monotonicNow() 纳秒自己算，
/// begin/end 仍写 HttpMetricsCollector（avg/max gauge、状态分布不变）。
fn metricsMiddleware(ctx: *http.Context, next: http.HandlerFn, user_data: ?*anyopaque) anyerror!void {
    const self: *Metrics = @ptrCast(@alignCast(user_data orelse return error.InternalError));
    const start_ns = zigmodu.time.monotonicNow();
    self.collector.beginRequest();
    next(ctx) catch |err| {
        const elapsed = elapsedSeconds(start_ns);
        self.collector.endRequest(500, elapsed);
        self.hist.observe(elapsed);
        return err;
    };
    const status: u16 = if (ctx.responded) ctx.status_code else 200;
    const elapsed = elapsedSeconds(start_ns);
    self.collector.endRequest(status, elapsed);
    self.hist.observe(elapsed);
}

fn elapsedSeconds(start_ns: i64) f64 {
    return @as(f64, @floatFromInt(zigmodu.time.monotonicNow() - start_ns)) / std.time.ns_per_s;
}

pub const Metrics = struct {
    collector: http.HttpMetricsCollector,
    hist: DurationHistogram = .{},
    started_at: i64,
    /// Dispatcher 计数器来源(可选,main 里绑定);不持有所有权。
    dispatcher: ?*task_service.Dispatcher = null,
    /// 数据库连接池快照来源(可选,main 里绑定):每次导出时回调现取一次
    /// stats(),而非启动期一次性快照。StoreEnv 是泛型类型,metrics 不感知
    /// 其 comptime 参数,故以函数指针注入,只依赖 db.zig 的驱动无关快照
    /// 类型;不持有所有权。
    pool_stats_fn: ?*const fn () ?db_mod.PoolStats = null,

    pub fn init(io: std.Io) Metrics {
        return .{
            .collector = .init(),
            .started_at = zigmodu.time.wallClockSeconds(io),
        };
    }

    pub fn middleware(self: *Metrics) http.Middleware {
        return .{
            .func = metricsMiddleware,
            .user_data = self,
        };
    }

    /// Prometheus text exposition for the `/metrics` endpoint.
    pub fn renderPrometheus(self: *Metrics, allocator: std.mem.Allocator, now: i64) ![]const u8 {
        const c = &self.collector;
        const snap = c.snapshot();
        var buf = std.ArrayList(u8).empty;
        defer buf.deinit(allocator);

        try buf.print(allocator, "# HELP zweq_http_requests_total Total HTTP requests processed.\n", .{});
        try buf.print(allocator, "# TYPE zweq_http_requests_total counter\n", .{});
        try buf.print(allocator, "zweq_http_requests_total {d}\n", .{snap.request_count});
        try buf.print(allocator, "# HELP zweq_http_requests_in_flight Requests currently being processed.\n", .{});
        try buf.print(allocator, "# TYPE zweq_http_requests_in_flight gauge\n", .{});
        try buf.print(allocator, "zweq_http_requests_in_flight {d}\n", .{snap.in_flight});
        inline for (.{
            .{ "2xx", 1 },
            .{ "3xx", 2 },
            .{ "4xx", 3 },
            .{ "5xx", 4 },
        }) |pair| {
            try buf.print(allocator, "zweq_http_requests_{s}{{class=\"{s}\"}} {d}\n", .{ pair[0], pair[0], snap.status_counts[pair[1]] });
        }
        try buf.print(allocator, "# HELP zweq_http_request_duration_seconds Request latency summary.\n", .{});
        try buf.print(allocator, "# TYPE zweq_http_request_duration_seconds gauge\n", .{});
        try buf.print(allocator, "zweq_http_request_duration_seconds_avg {d:.6}\n", .{c.avgDuration()});
        try buf.print(allocator, "zweq_http_request_duration_seconds_max {d:.6}\n", .{if (snap.max_duration_seconds == std.math.floatMax(f64)) 0 else snap.max_duration_seconds});
        // 请求耗时直方图（counter 语义：进程内单调累积的样本计数）。
        const hs = self.hist.snapshot();
        try buf.print(allocator, "# HELP zweq_http_request_duration_seconds Request latency histogram.\n", .{});
        try buf.print(allocator, "# TYPE zweq_http_request_duration_seconds histogram\n", .{});
        inline for (duration_bucket_labels, 0..) |le, i| {
            try buf.print(allocator, "zweq_http_request_duration_seconds_bucket{{le=\"{s}\"}} {d}\n", .{ le, hs.counts[i] });
        }
        try buf.print(allocator, "zweq_http_request_duration_seconds_bucket{{le=\"+Inf\"}} {d}\n", .{hs.count});
        try buf.print(allocator, "zweq_http_request_duration_seconds_sum {d:.6}\n", .{hs.sum_seconds});
        try buf.print(allocator, "zweq_http_request_duration_seconds_count {d}\n", .{hs.count});
        try buf.print(allocator, "# HELP zweq_uptime_seconds Process uptime.\n", .{});
        try buf.print(allocator, "# TYPE zweq_uptime_seconds gauge\n", .{});
        try buf.print(allocator, "zweq_uptime_seconds {d}\n", .{now - self.started_at});
        if (self.dispatcher) |d| {
            try buf.print(allocator, "# HELP zweq_tasks_processed_total Background tasks completed successfully.\n", .{});
            try buf.print(allocator, "# TYPE zweq_tasks_processed_total gauge\n", .{});
            try buf.print(allocator, "zweq_tasks_processed_total {d}\n", .{d.processed.load(.monotonic)});
            try buf.print(allocator, "# HELP zweq_tasks_failed_total Background tasks failed (retryable failures and permanent failures).\n", .{});
            try buf.print(allocator, "# TYPE zweq_tasks_failed_total gauge\n", .{});
            try buf.print(allocator, "zweq_tasks_failed_total {d}\n", .{d.failed.load(.monotonic)});
        }
        // 限流拒绝计数(counter):per-IP 超限、per-openid 超限/无身份拒绝、
        // 后端故障 fail-closed 三类 429 的进程级总和。计数器归
        // rate_limit.zig 所有,本文件只读导出(依赖方向 metrics →
        // rate_limit,不引入反向依赖)。
        try buf.print(allocator, "# HELP zweq_rate_limit_rejections_total Requests rejected with HTTP 429 by the rate limiters.\n", .{});
        try buf.print(allocator, "# TYPE zweq_rate_limit_rejections_total counter\n", .{});
        try buf.print(allocator, "zweq_rate_limit_rejections_total {d}\n", .{rate_limit.rejections_total.load(.monotonic)});
        // 数据库连接池指标:sqlite / postgres 都经 zent ConnPool(见 db.zig,
        // sqlite 非 :memory: 时 max=8),故两种驱动都导出;未注入来源时整段跳过。
        if (self.pool_stats_fn) |poolStats| {
            if (poolStats()) |s| {
                try buf.print(allocator, "# HELP zweq_db_pool_total Connections the pool holds, idle or lent out.\n", .{});
                try buf.print(allocator, "# TYPE zweq_db_pool_total gauge\n", .{});
                try buf.print(allocator, "zweq_db_pool_total {d}\n", .{s.total});
                try buf.print(allocator, "# HELP zweq_db_pool_in_use Connections currently lent out.\n", .{});
                try buf.print(allocator, "# TYPE zweq_db_pool_in_use gauge\n", .{});
                try buf.print(allocator, "zweq_db_pool_in_use {d}\n", .{s.in_use});
                try buf.print(allocator, "# HELP zweq_db_pool_available Idle connections available to borrow.\n", .{});
                try buf.print(allocator, "# TYPE zweq_db_pool_available gauge\n", .{});
                try buf.print(allocator, "zweq_db_pool_available {d}\n", .{s.available});
                try buf.print(allocator, "# HELP zweq_db_pool_waiters Borrowers blocked waiting for a free connection.\n", .{});
                try buf.print(allocator, "# TYPE zweq_db_pool_waiters gauge\n", .{});
                try buf.print(allocator, "zweq_db_pool_waiters {d}\n", .{s.waiters});
                try buf.print(allocator, "# HELP zweq_db_pool_exhausted_total Borrows that gave up because the pool was exhausted.\n", .{});
                try buf.print(allocator, "# TYPE zweq_db_pool_exhausted_total counter\n", .{});
                try buf.print(allocator, "zweq_db_pool_exhausted_total {d}\n", .{s.exhausted_total});
            }
        }
        return buf.toOwnedSlice(allocator);
    }
};

// ─────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────

test "DurationHistogram buckets are cumulative" {
    var h = DurationHistogram{};
    h.observe(0.003); // le=0.005
    h.observe(0.02); // le=0.025
    h.observe(0.4); // le=0.5
    h.observe(30); // 超出最大桶,只计入 +Inf(count)

    const snap = h.snapshot();
    try std.testing.expectEqual(@as(u64, 4), snap.count);
    try std.testing.expect(snap.sum_seconds > 30.4 and snap.sum_seconds < 30.5);
    try std.testing.expectEqual(@as(u64, 1), snap.counts[0]); // le=0.005
    try std.testing.expectEqual(@as(u64, 1), snap.counts[1]); // le=0.01
    try std.testing.expectEqual(@as(u64, 2), snap.counts[2]); // le=0.025
    try std.testing.expectEqual(@as(u64, 2), snap.counts[5]); // le=0.25
    try std.testing.expectEqual(@as(u64, 3), snap.counts[6]); // le=0.5
    try std.testing.expectEqual(@as(u64, 3), snap.counts[10]); // le=10
}
