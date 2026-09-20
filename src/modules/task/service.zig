//! Task service + dispatcher — durable background task queue.
//!
//! `TaskService` is the write/query API (enqueue, retry, cancel, purge);
//! `Dispatcher` is the background loop that claims due tasks, runs their
//! registered handler and finalizes them (done / failed / scheduled retry).

const std = @import("std");
const zigmodu = @import("zigmodu");
const persist = @import("persistence.zig");
const scheduled = @import("../../scheduled.zig");

pub const TaskRow = persist.TaskRow;
pub const TaskListResult = persist.TaskListResult;
pub const StatusCounts = persist.StatusCounts;

pub const TaskService = struct {
    store: *persist.TaskStore,
    io: std.Io,
    max_attempts: i64,

    pub fn init(store: *persist.TaskStore, io: std.Io, max_attempts: i64) TaskService {
        return .{ .store = store, .io = io, .max_attempts = max_attempts };
    }

    /// Enqueue a task for immediate or delayed execution. Returns the new id.
    pub fn enqueue(self: *TaskService, name: []const u8, payload: []const u8, available_at: i64, tenant_id: i64) !i64 {
        const now = self.nowSeconds();
        return self.store.createTask(name, payload, "pending", tenant_id, 0, self.max_attempts, "", available_at, now);
    }

    pub fn enqueueNow(self: *TaskService, name: []const u8, payload: []const u8, tenant_id: i64) !i64 {
        return self.enqueue(name, payload, 0, tenant_id);
    }

    pub fn list(self: *TaskService, page: usize, page_size: usize, status: ?[]const u8) !TaskListResult {
        return self.store.listTasks(page, page_size, status);
    }

    pub fn get(self: *TaskService, id: i64) !?TaskRow {
        return self.store.getTaskById(id);
    }

    pub fn retry(self: *TaskService, id: i64) !bool {
        return self.store.retryTask(id, self.nowSeconds());
    }

    pub fn cancel(self: *TaskService, id: i64) !bool {
        return self.store.cancelTask(id, self.nowSeconds());
    }

    pub fn purge(self: *TaskService) !usize {
        return self.store.purgeFinished();
    }

    pub fn counts(self: *TaskService) !StatusCounts {
        return self.store.countByStatus();
    }

    pub fn delete(self: *TaskService, id: i64) !void {
        try self.store.deleteTask(id);
    }

    fn nowSeconds(self: *TaskService) i64 {
        return zigmodu.time.wallClockSeconds(self.io);
    }
};

// ── Dispatcher ─────────────────────────────────────────────────────

/// Task handler: `ctx` is the registered handler context (e.g. the Mailer),
/// `payload` is the JSON/plain string stored on the task row. Returning an
/// error marks the task failed/retryable via `markFailedOrRetry` instead of
/// silently treating it as done. `anyerror` because the registry is open to
/// future handlers whose failure modes this queue cannot enumerate.
pub const TaskHandler = *const fn (ctx: ?*anyopaque, allocator: std.mem.Allocator, io: std.Io, payload: []const u8) anyerror!void;

pub const Handler = struct {
    name: []const u8,
    ctx: ?*anyopaque,
    run: TaskHandler,
};

pub const Dispatcher = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    store: *persist.TaskStore,
    handlers: []const Handler,
    retry_interval_seconds: i64,
    stale_after_seconds: i64,
    scheduled: ?*scheduled.ScheduledRunner = null,
    running: std.atomic.Value(bool),
    thread: ?std.Thread = null,
    tick_interval_ms: u64 = 1000,
    processed: std.atomic.Value(u64),
    failed: std.atomic.Value(u64),

    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        store: *persist.TaskStore,
        handlers: []const Handler,
        retry_interval_seconds: i64,
        stale_after_seconds: i64,
    ) Dispatcher {
        return .{
            .allocator = allocator,
            .io = io,
            .store = store,
            .handlers = handlers,
            .retry_interval_seconds = retry_interval_seconds,
            .stale_after_seconds = stale_after_seconds,
            .running = std.atomic.Value(bool).init(false),
            .thread = null,
            .processed = std.atomic.Value(u64).init(0),
            .failed = std.atomic.Value(u64).init(0),
        };
    }

    pub fn deinit(self: *Dispatcher) void {
        self.stop();
        self.* = undefined;
    }

    pub fn start(self: *Dispatcher) !void {
        if (self.running.load(.monotonic)) return;
        self.running.store(true, .monotonic);
        self.thread = try std.Thread.spawn(.{}, runLoop, .{self});
    }

    pub fn stop(self: *Dispatcher) void {
        self.running.store(false, .monotonic);
        if (self.thread) |t| {
            t.join();
            self.thread = null;
        }
    }

    fn runLoop(self: *Dispatcher) void {
        while (self.running.load(.monotonic)) {
            self.tick();
            // 节拍:std.Io.sleep 只可能返回 error.Canceled,睡眠失败不影响
            // 任务处理正确性,循环是否继续只由 running 标志决定,故直接吞掉。
            std.Io.sleep(self.io, std.Io.Duration.fromMilliseconds(@intCast(self.tick_interval_ms)), .real) catch {};
        }
    }

    /// One scheduling pass: requeue stale claims, then run every due task
    /// (sequentially; SQLite favours a single writer). Each pass and each
    /// job run is timed and logged so a hung job is visible instead of
    /// silently stalling the single worker loop.
    pub fn tick(self: *Dispatcher) void {
        const tick_start = @import("zigmodu").time.monotonicNow();
        const now = @import("zigmodu").time.wallClockSeconds(self.io);
        _ = self.store.requeueStale(now, self.stale_after_seconds) catch |err| {
            std.log.err("[task] requeueStale 失败: {s}", .{@errorName(err)});
        };
        if (self.scheduled) |s| {
            // scheduled.zig 只读:其内部 job 耗时不可见,只能对整个 s.tick
            // 计时——某 cleanup job 挂起时会体现为这里的耗时飙升。
            const sched_start = @import("zigmodu").time.monotonicNow();
            s.tick(now);
            const sched_ms = @divTrunc(@import("zigmodu").time.monotonicNow() - sched_start, std.time.ns_per_ms);
            std.log.info("[task] scheduled tick 完成,耗时 {d}ms", .{sched_ms});
        }
        var ran: usize = 0;
        while (true) {
            const task_opt = self.store.claimNext(now) catch |err| {
                std.log.err("[task] claimNext 失败,本 tick 提前结束: {s}", .{@errorName(err)});
                break;
            };
            const task = task_opt orelse break;
            defer task.free(self.allocator);
            self.runTask(task);
            ran += 1;
        }
        const tick_ms = @divTrunc(@import("zigmodu").time.monotonicNow() - tick_start, std.time.ns_per_ms);
        std.log.info("[task] tick 完成: {d} 个任务,总耗时 {d}ms", .{ ran, tick_ms });
    }

    fn runTask(self: *Dispatcher, task: TaskRow) void {
        var found: ?Handler = null;
        for (self.handlers) |h| {
            if (std.mem.eql(u8, h.name, task.name)) {
                found = h;
                break;
            }
        }
        const handler = found orelse {
            // Unknown handler — fail so the row does not spin forever.
            self.store.markFailedOrRetry(task.id, task.attempts, task.max_attempts, "no handler registered", wallNow(self), 0) catch |mark_err| {
                std.log.err("[task] {s}#{d} 无 handler 标记失败写入失败: {s}", .{ task.name, task.id, @errorName(mark_err) });
            };
            _ = self.failed.fetchAdd(1, .monotonic);
            return;
        };

        const run_start = @import("zigmodu").time.monotonicNow();
        handler.run(handler.ctx, self.allocator, self.io, task.payload) catch |err| {
            // handler 失败(如 mail.send 的 SMTP 投递失败、payload 非法)走
            // 既有 markFailedOrRetry 重试链路:未达 max_attempts 重新排队,
            // 超限标记 failed,任务不再被静默记成功而丢信。
            const elapsed_ms = @divTrunc(@import("zigmodu").time.monotonicNow() - run_start, std.time.ns_per_ms);
            std.log.err("[task] {s}#{d} 执行失败: {s} (耗时 {d}ms)", .{ task.name, task.id, @errorName(err), elapsed_ms });
            self.store.markFailedOrRetry(task.id, task.attempts, task.max_attempts, @errorName(err), wallNow(self), self.retry_interval_seconds) catch |mark_err| {
                std.log.err("[task] {s}#{d} 重试/失败标记写入失败: {s}", .{ task.name, task.id, @errorName(mark_err) });
            };
            _ = self.failed.fetchAdd(1, .monotonic);
            return;
        };
        const elapsed_ms = @divTrunc(@import("zigmodu").time.monotonicNow() - run_start, std.time.ns_per_ms);
        self.store.markDone(task.id, wallNow(self)) catch {
            self.store.markFailedOrRetry(task.id, task.attempts, task.max_attempts, "store error", wallNow(self), self.retry_interval_seconds) catch |mark_err| {
                std.log.err("[task] {s}#{d} markDone 失败后的兜底标记同样失败: {s}", .{ task.name, task.id, @errorName(mark_err) });
            };
            _ = self.failed.fetchAdd(1, .monotonic);
            return;
        };
        std.log.debug("[task] {s}#{d} 执行完成,耗时 {d}ms", .{ task.name, task.id, elapsed_ms });
        _ = self.processed.fetchAdd(1, .monotonic);
    }

    fn wallNow(self: *Dispatcher) i64 {
        return @import("zigmodu").time.wallClockSeconds(self.io);
    }
};
