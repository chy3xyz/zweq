//! Prometheus HTTP metrics — request counter, status buckets, latency and
//! uptime, collected by zigmodu's HttpMetricsCollector middleware, plus
//! dispatcher / rate-limit / DB-pool counters bound from main.

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const task_service = @import("../modules/task/service.zig");
const db_mod = @import("../db.zig");
const rate_limit = @import("rate_limit.zig");

pub const Metrics = struct {
    collector: http.HttpMetricsCollector,
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
            .func = http.httpMetricsMiddleware(&self.collector),
            .user_data = &self.collector,
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
