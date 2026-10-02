//! zent schema-as-code — background task queue (backlite-style).
//!
//! `Task` rows are durable work items: `pending` rows are claimed by the
//! dispatcher, retried with backoff up to `max_attempts`, and end in
//! `done` / `failed` / `canceled`.
//!
//! `claim_owner` / `claimed_until` 是 fencing 字段:claim 时写入 owner token
//! 与租约截止时间,requeue/mark 都以它们做谓词,前任 worker 迟到的收尾
//! 写入会被拒。存量行迁移默认值为 "" / 0(视为已过期,可被 requeue 回收)。

const zent = @import("zent");
const field = zent.core.field;
const Schema = zent.core.schema.Schema;

pub const Task = Schema("Task", .{
    .fields = &.{
        field.String("name"),
        field.String("payload").Default(""),
        field.String("status").Default("pending"),
        field.Int("tenant_id").Default(0),
        field.Int("attempts").Default(0),
        field.Int("max_attempts").Default(3),
        field.String("last_error").Default(""),
        field.Int("available_at").Default(0),
        field.Int("started_at").Default(0),
        field.Int("finished_at").Default(0),
        field.String("claim_owner").Default(""),
        field.Int("claimed_until").Default(0),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});

/// 多副本互斥的 cron 锁表( ScheduledRunner 用)。`name` 是唯一键(锁名,
/// 如 job 名),`owner` 是持锁者 token:自己上轮的租约未过期可直接续期,
/// 他人租约未过期则让位;`expires_at` 是租约到期时间戳(秒),过期即可被
/// CAS 抢占。无 TimeMixin:锁行只有抢占/过期语义,不需要审计时间戳。
pub const CronLock = Schema("CronLock", .{
    .table_name = "cron_locks",
    .fields = &.{
        field.String("name").Unique(),
        field.String("owner").Default(""),
        field.Int("expires_at").Default(0),
    },
});
