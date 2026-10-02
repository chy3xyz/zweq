//! Persistence over the zent Client — durable background tasks.

const std = @import("std");
const zent = @import("zent");
const crud = zent.crud_helpers;
const model = @import("model.zig");
const schema = @import("../../schema.zig");

const graph = zent.codegen.graph.buildGraph(&.{ model.Task, model.CronLock });
pub const infos = graph.types;
pub const Client = schema.Client;
pub const TaskInfo = infos[0];
pub const CronLockInfo = infos[1];

pub const TaskRow = struct {
    id: i64,
    name: []const u8,
    payload: []const u8,
    status: []const u8,
    tenant_id: i64,
    attempts: i64,
    max_attempts: i64,
    last_error: []const u8,
    available_at: i64,
    started_at: i64,
    finished_at: i64,
    created_at: i64,
    updated_at: i64,
    claim_owner: []const u8,
    claimed_until: i64,

    pub fn free(self: TaskRow, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.payload);
        allocator.free(self.status);
        allocator.free(self.last_error);
        allocator.free(self.claim_owner);
    }
};

pub const CronLockRow = struct {
    id: i64,
    name: []const u8,
    owner: []const u8,
    expires_at: i64,

    pub fn free(self: CronLockRow, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.owner);
    }
};

pub const TaskListResult = struct {
    items: []TaskRow,
    total: i64,

    pub fn free(self: *TaskListResult, allocator: std.mem.Allocator) void {
        for (self.items) |r| r.free(allocator);
        allocator.free(self.items);
    }
};

pub const StatusCounts = struct {
    pending: i64 = 0,
    claimed: i64 = 0,
    done: i64 = 0,
    failed: i64 = 0,
    canceled: i64 = 0,
};

pub const TaskStore = struct {
    allocator: std.mem.Allocator,
    client: Client,

    pub fn init(allocator: std.mem.Allocator, client: Client) TaskStore {
        return .{ .allocator = allocator, .client = client };
    }

    fn dupTask(self: *TaskStore, e: anytype) !TaskRow {
        const name = try self.allocator.dupe(u8, e.name);
        errdefer self.allocator.free(name);
        const payload = try self.allocator.dupe(u8, e.payload);
        errdefer self.allocator.free(payload);
        const status = try self.allocator.dupe(u8, e.status);
        errdefer self.allocator.free(status);
        const last_error = try self.allocator.dupe(u8, e.last_error);
        errdefer self.allocator.free(last_error);
        const claim_owner = try self.allocator.dupe(u8, e.claim_owner);
        errdefer self.allocator.free(claim_owner);
        return .{
            .id = e.id,
            .name = name,
            .payload = payload,
            .status = status,
            .tenant_id = e.tenant_id,
            .attempts = e.attempts,
            .max_attempts = e.max_attempts,
            .last_error = last_error,
            .available_at = e.available_at,
            .started_at = e.started_at,
            .finished_at = e.finished_at,
            .created_at = e.created_at orelse 0,
            .updated_at = e.updated_at orelse 0,
            .claim_owner = claim_owner,
            .claimed_until = e.claimed_until,
        };
    }

    pub fn createTask(
        self: *TaskStore,
        name: []const u8,
        payload: []const u8,
        status: []const u8,
        tenant_id: i64,
        attempts: i64,
        max_attempts: i64,
        last_error: []const u8,
        available_at: i64,
        now: i64,
    ) !i64 {
        var row = try crud.create(self.client.task, .{
            .name = name,
            .payload = payload,
            .status = status,
            .tenant_id = tenant_id,
            .attempts = attempts,
            .max_attempts = max_attempts,
            .last_error = last_error,
            .available_at = available_at,
            .started_at = @as(i64, 0),
            .finished_at = @as(i64, 0),
            .created_at = now,
            .updated_at = now,
        });
        defer self.client.task.deinitRow(&row);
        return row.id;
    }

    pub fn getTaskById(self: *TaskStore, id: i64) !?TaskRow {
        const preds = self.client.task.predicates;
        var entity = (try crud.first(self.client.task, .{preds.idEQ(.{ .int = id })})) orelse return null;
        defer self.client.task.deinitRow(&entity);
        return try self.dupTask(entity);
    }

    pub fn listTasks(self: *TaskStore, page: usize, page_size: usize, status: ?[]const u8) !TaskListResult {
        const preds = self.client.task.predicates;
        const status_pred = if (status) |s| if (s.len > 0) preds.statusEQ(.{ .string = s }) else null else null;

        var q = self.client.task.Query();
        defer q.deinit();
        if (status_pred) |sp| _ = try q.Where(.{sp});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderAsc("id")});

        var paged = try q.paged(page, page_size);
        defer paged.deinit();

        var out = try self.allocator.alloc(TaskRow, paged.items.items.len);
        var n: usize = 0;
        errdefer {
            for (out[0..n]) |r| r.free(self.allocator);
            self.allocator.free(out);
        }
        for (paged.items.items) |e| {
            out[n] = try self.dupTask(e);
            n += 1;
        }
        return .{ .items = out, .total = paged.total };
    }

    /// Oldest due task (`pending` and `available_at <= now`), or null.
    /// Claims with a fencing token: `owner` (dispatcher 实例 token) is written
    /// to `claim_owner` and the lease `claimed_until = now + stale_after`, so
    /// a worker that dies mid-run can only lose its lease, never its writes.
    pub fn claimNext(self: *TaskStore, now: i64, owner: []const u8, stale_after: i64) !?TaskRow {
        var q = self.client.task.Query();
        defer q.deinit();
        const preds = self.client.task.predicates;
        _ = try q.Where(.{preds.statusEQ(.{ .string = "pending" })});
        _ = try q.Where(.{preds.available_atLTE(.{ .int = now })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderAsc("id")});
        _ = q.Limit(1);
        const entity_opt = try q.First();
        var entity = entity_opt orelse return null;
        defer self.client.task.deinitRow(&entity);

        // Mark claimed atomically-ish: only a row still pending may be claimed.
        var upd = self.client.task.Update();
        defer upd.deinit();
        _ = try upd.set("status", .{ .string = "claimed" });
        _ = try upd.setFieldValue("attempts", entity.attempts + 1);
        _ = try upd.setFieldValue("started_at", now);
        _ = try upd.setFieldValue("updated_at", now);
        _ = try upd.set("claim_owner", .{ .string = owner });
        _ = try upd.setFieldValue("claimed_until", now + stale_after);
        _ = try upd.Where(.{preds.idEQ(.{ .int = entity.id })});
        _ = try upd.Where(.{preds.statusEQ(.{ .string = "pending" })});
        const affected = try upd.Save();
        // 并发抢单时另一 worker 已把该行改出 pending，UPDATE 命中 0 行。
        // 返回 null（语义同「没有可领任务」），避免多 worker 重复执行同一任务。
        if (affected == 0) return null;

        // Re-read so the returned row reflects the claimed state.
        return try self.getTaskById(entity.id);
    }

    /// Finalize a claimed task as done. The `owner` fencing token must still
    /// own the row — a late write from a worker whose claim was requeued away
    /// matches 0 rows and returns false（写穿被 fencing 谓词拦下）。
    pub fn markDone(self: *TaskStore, id: i64, owner: []const u8, now: i64) !bool {
        const preds = self.client.task.predicates;
        var upd = self.client.task.Update();
        defer upd.deinit();
        _ = try upd.set("status", .{ .string = "done" });
        _ = try upd.setFieldValue("finished_at", now);
        _ = try upd.setFieldValue("updated_at", now);
        _ = try upd.Where(.{preds.idEQ(.{ .int = id })});
        _ = try upd.Where(.{preds.statusEQ(.{ .string = "claimed" })});
        _ = try upd.Where(.{preds.claim_ownerEQ(.{ .string = owner })});
        return (try upd.Save()) > 0;
    }

    /// Mark failed permanently, or schedule a retry (attempts stay as-is;
    /// the next claim increments them again). Same fencing predicate as
    /// `markDone`; returns false when the row is no longer ours.
    pub fn markFailedOrRetry(self: *TaskStore, id: i64, owner: []const u8, attempts: i64, max_attempts: i64, last_error: []const u8, now: i64, retry_interval: i64) !bool {
        const preds = self.client.task.predicates;
        var upd = self.client.task.Update();
        defer upd.deinit();
        if (attempts >= max_attempts) {
            _ = try upd.set("status", .{ .string = "failed" });
            _ = try upd.setFieldValue("finished_at", now);
            _ = try upd.set("last_error", .{ .string = last_error });
        } else {
            _ = try upd.set("status", .{ .string = "pending" });
            _ = try upd.setFieldValue("available_at", now + retry_interval);
            _ = try upd.set("last_error", .{ .string = last_error });
            _ = try upd.setFieldValue("started_at", 0);
        }
        _ = try upd.setFieldValue("updated_at", now);
        // 释放租约:回到 pending / 终态的行不再属于任何 worker。
        _ = try upd.set("claim_owner", .{ .string = "" });
        _ = try upd.setFieldValue("claimed_until", 0);
        _ = try upd.Where(.{preds.idEQ(.{ .int = id })});
        _ = try upd.Where(.{preds.statusEQ(.{ .string = "claimed" })});
        _ = try upd.Where(.{preds.claim_ownerEQ(.{ .string = owner })});
        return (try upd.Save()) > 0;
    }

    /// Re-queue tasks whose lease expired (`claimed` and
    /// `claimed_until < now` — the claim-time deadline, not a re-derived
    /// `started_at` window, so only the claimer-side timeout decides).
    /// Fails tasks past their attempt budget. The reclaim is a
    /// compare-and-swap on the fencing token: if another replica already
    /// reclaimed between our SELECT and UPDATE, the row changed and our
    /// UPDATE hits 0 rows (not counted, not double-requeued).
    /// `stale_after` 保留在签名里(调用方语义不变),判定已改用 claimed_until。
    pub fn requeueStale(self: *TaskStore, now: i64, stale_after: i64) !usize {
        _ = stale_after;
        const preds = self.client.task.predicates;
        var q = self.client.task.Query();
        defer q.deinit();
        _ = try q.Where(.{preds.statusEQ(.{ .string = "claimed" })});
        _ = try q.Where(.{preds.claimed_untilLT(.{ .int = now })});
        var found = try q.All();
        defer self.client.task.deinitRows(&found);

        var count: usize = 0;
        for (found.items) |e| {
            if (e.attempts >= e.max_attempts) {
                // 借 markFailedOrRetry 的 fencing 谓词:claim_owner 已变则放弃。
                if (try self.markFailedOrRetry(e.id, e.claim_owner, e.attempts, e.max_attempts, "stale (worker died)", now, 0)) count += 1;
            } else {
                var upd = self.client.task.Update();
                defer upd.deinit();
                _ = try upd.set("status", .{ .string = "pending" });
                _ = try upd.setFieldValue("available_at", now);
                _ = try upd.setFieldValue("started_at", 0);
                _ = try upd.setFieldValue("updated_at", now);
                _ = try upd.set("claim_owner", .{ .string = "" });
                _ = try upd.setFieldValue("claimed_until", 0);
                _ = try upd.Where(.{preds.idEQ(.{ .int = e.id })});
                _ = try upd.Where(.{preds.claim_ownerEQ(.{ .string = e.claim_owner })});
                _ = try upd.Where(.{preds.claimed_untilEQ(.{ .int = e.claimed_until })});
                if ((try upd.Save()) > 0) count += 1;
            }
        }
        return count;
    }

    pub fn retryTask(self: *TaskStore, id: i64, now: i64) !bool {
        const preds = self.client.task.predicates;
        var upd = self.client.task.Update();
        defer upd.deinit();
        _ = try upd.set("status", .{ .string = "pending" });
        _ = try upd.setFieldValue("attempts", 0);
        _ = try upd.set("last_error", .{ .string = "" });
        _ = try upd.setFieldValue("available_at", now);
        _ = try upd.setFieldValue("started_at", 0);
        _ = try upd.setFieldValue("finished_at", 0);
        _ = try upd.setFieldValue("updated_at", now);
        _ = try upd.Where(.{preds.idEQ(.{ .int = id })});
        _ = try upd.Where(.{preds.statusNE(.{ .string = "pending" })});
        _ = try upd.Save();
        return true;
    }

    pub fn cancelTask(self: *TaskStore, id: i64, now: i64) !bool {
        const preds = self.client.task.predicates;
        var upd = self.client.task.Update();
        defer upd.deinit();
        _ = try upd.set("status", .{ .string = "canceled" });
        _ = try upd.setFieldValue("finished_at", now);
        _ = try upd.setFieldValue("updated_at", now);
        _ = try upd.Where(.{preds.idEQ(.{ .int = id })});
        _ = try upd.Where(.{preds.statusEQ(.{ .string = "pending" })});
        _ = try upd.Save();
        return true;
    }

    pub fn deleteTask(self: *TaskStore, id: i64) !void {
        const preds = self.client.task.predicates;
        var d = self.client.task.Delete();
        defer d.deinit();
        _ = try d.Where(.{preds.idEQ(.{ .int = id })});
        _ = try d.Exec();
    }

    pub fn purgeFinished(self: *TaskStore) !usize {
        const preds = self.client.task.predicates;
        const p1 = preds.statusEQ(.{ .string = "done" });
        const p2 = preds.statusEQ(.{ .string = "failed" });
        const p3 = preds.statusEQ(.{ .string = "canceled" });
        const or12 = zent.sql.Or(&p1, &p2);
        const or_pred = zent.sql.Or(&or12, &p3);
        var d = self.client.task.Delete();
        defer d.deinit();
        _ = try d.Where(.{or_pred});
        _ = try d.Exec();
        return 0;
    }

    pub fn countByStatus(self: *TaskStore) !StatusCounts {
        var counts: StatusCounts = .{};
        const preds = self.client.task.predicates;
        inline for (.{
            .{ "pending", &counts.pending },
            .{ "claimed", &counts.claimed },
            .{ "done", &counts.done },
            .{ "failed", &counts.failed },
            .{ "canceled", &counts.canceled },
        }) |pair| {
            var q = self.client.task.Query();
            defer q.deinit();
            _ = try q.Where(.{preds.statusEQ(.{ .string = pair[0] })});
            pair[1].* = @intCast(try q.Count());
        }
        return counts;
    }
};

/// DB 表锁(cron_locks),给 ScheduledRunner 在多副本部署下互斥执行 interval
/// job。协议是「可续租约」而非「抢-放」:
///   1. INSERT 优先(SaveIgnore,撞唯一键即失败);
///   2. 已有锁未过期且 owner 不是自己 → 让位(别的副本正在负责本轮);
///   3. 已过期,或 owner 是自己(上一轮的租约还没到期)→ 按旧 expires_at
///      做 compare-and-swap 续期/抢占,两副本同时动手只有一个 UPDATE 命中。
/// 持锁者跑完不释放:租约自身就是「本轮已有人负责」的标记,下个周期 owner
/// 相同直接续期;crash 则由 TTL 兜底,过期后由其他副本抢走,接管延迟 ≤ TTL。
pub const CronLockStore = struct {
    allocator: std.mem.Allocator,
    client: Client,

    pub fn init(allocator: std.mem.Allocator, client: Client) CronLockStore {
        return .{ .allocator = allocator, .client = client };
    }

    pub fn getLock(self: *CronLockStore, name: []const u8) !?CronLockRow {
        const preds = self.client.cron_lock.predicates;
        var entity = (try crud.first(self.client.cron_lock, .{preds.nameEQ(.{ .string = name })})) orelse return null;
        defer self.client.cron_lock.deinitRow(&entity);
        return .{
            .id = entity.id,
            .name = try self.allocator.dupe(u8, entity.name),
            .owner = try self.allocator.dupe(u8, entity.owner),
            .expires_at = entity.expires_at,
        };
    }

    /// 尝试抢占/续期 `name` 锁,租约 `now + ttl_secs`。返回是否由本 owner 持有。
    pub fn tryLock(self: *CronLockStore, name: []const u8, owner: []const u8, now: i64, ttl_secs: i64) !bool {
        var cb = try self.client.cron_lock.Create();
        defer cb.deinit();
        _ = try cb.setFieldValue("name", name);
        _ = try cb.setFieldValue("owner", owner);
        _ = try cb.setFieldValue("expires_at", now + ttl_secs);
        var row = try cb.SaveIgnore();
        defer self.client.cron_lock.deinitRow(&row);
        // SaveIgnore 撞唯一键时 RETURNING 无行,自增 id 保持 0;插入成功才带回 id。
        if (row.id != 0) return true;

        const existing = (try self.getLock(name)) orelse return false; // 极端竞态:行刚被删
        defer existing.free(self.allocator);
        // 他人持有未过期租约 → 让位;自己的租约(上轮遗留)与过期租约都进入 CAS。
        if (existing.expires_at > now and !std.mem.eql(u8, existing.owner, owner)) return false;

        const preds = self.client.cron_lock.predicates;
        var upd = self.client.cron_lock.Update();
        defer upd.deinit();
        _ = try upd.set("owner", .{ .string = owner });
        _ = try upd.setFieldValue("expires_at", now + ttl_secs);
        _ = try upd.Where(.{preds.idEQ(.{ .int = existing.id })});
        _ = try upd.Where(.{preds.expires_atEQ(.{ .int = existing.expires_at })});
        return (try upd.Save()) > 0;
    }
};
