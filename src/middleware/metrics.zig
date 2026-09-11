//! Prometheus HTTP metrics — request counter, status buckets, latency and
//! uptime, collected by zigmodu's HttpMetricsCollector middleware.

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const task_service = @import("../modules/task/service.zig");

pub const Metrics = struct {
    collector: http.HttpMetricsCollector,
    started_at: i64,
    /// Dispatcher 计数器来源(可选,main 里绑定);不持有所有权。
    dispatcher: ?*task_service.Dispatcher = null,

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
        return buf.toOwnedSlice(allocator);
    }
};
