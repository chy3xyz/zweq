//! Lightweight interval scheduler for background housekeeping.
//!
//! zigmodu ships a full cron `Scheduler`, but zent's SQLite driver is a
//! single connection, so all background DB work must stay on ONE thread —
//! the task dispatcher's loop. `ScheduledRunner` is embedded in that loop
//! and runs jobs at fixed intervals (cron semantics for our single-writer
//! constraint). For CPU-only jobs, prefer `zigmodu.cron.Scheduler`.
//!
//! 多副本部署:`last_run` 是进程内字段,每个副本每 tick 都会触发。注入
//! `lock_store`(cron_locks 表锁)后,job 按「可续租约」互斥:抢到锁的副本
//! 执行,未抢到但租约未过期的副本视本轮为「已由他人负责」,同样推进 last_run;
//! 持锁副本下个周期对自有租约直接续期,crash 后租约过期由其他副本接管
//! (接管延迟 ≤ TTL = max(间隔×2, stale_after_secs))。

const std = @import("std");
const zigmodu = @import("zigmodu");
const persist = @import("modules/task/persistence.zig");

pub const ScheduledJob = struct {
    name: []const u8,
    interval_seconds: i64,
    last_run: i64 = 0,
    run: *const fn (ctx: ?*anyopaque) void,
    ctx: ?*anyopaque = null,
};

pub const ScheduledRunner = struct {
    jobs: []ScheduledJob,
    /// DB 表锁;null = 单进程直跑(main.zig 未注入前/测试的默认行为)。
    lock_store: ?*persist.CronLockStore = null,
    /// 锁 TTL 下限(秒);实际 TTL = max(间隔×2, 该值)。
    stale_after_secs: i64 = 300,
    /// 实例标识(进程级唯一),惰性生成;owner token = "sched-{tag}"。
    instance_tag: u64 = 0,

    fn ownerToken(self: *ScheduledRunner, buf: []u8) []const u8 {
        if (self.instance_tag == 0) {
            const ns: u64 = @bitCast(zigmodu.time.monotonicNow());
            self.instance_tag = ns ^ @as(u64, @truncate(@intFromPtr(self)));
        }
        return std.fmt.bufPrint(buf, "sched-{x}", .{self.instance_tag}) catch unreachable;
    }

    pub fn tick(self: *ScheduledRunner, now: i64) void {
        for (self.jobs) |*job| {
            if (now - job.last_run < job.interval_seconds) continue;
            const lock_store = self.lock_store orelse {
                job.run(job.ctx);
                job.last_run = now;
                continue;
            };
            var owner_buf: [40]u8 = undefined;
            const owner = self.ownerToken(&owner_buf);
            const ttl = @max(job.interval_seconds * 2, self.stale_after_secs);
            const acquired = lock_store.tryLock(job.name, owner, now, ttl) catch |err| {
                // 锁表不可用时跳过本轮(不推进 last_run,下个 tick 重试)。
                std.log.err("[scheduled] {s} 抢锁失败,本轮跳过: {s}", .{ job.name, @errorName(err) });
                continue;
            };
            if (!acquired) {
                // 他人持有未过期租约:本轮 job 由别的副本执行,推进 last_run 避免
                // 租约到期后本副本又补跑一次(非幂等 job 会重复执行)。
                job.last_run = now;
                continue;
            }
            job.run(job.ctx);
            job.last_run = now;
            // 不释放锁:租约是「本轮已有人负责」的标记,下轮由自己续期或过期易主。
        }
    }
};
