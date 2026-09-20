//! Database store lifecycle: open driver (sqlite | postgres) → migrate
//! schema-as-code → make zent client. Driver choice is driven by config
//! at runtime so the same binary works against a local sqlite file or a
//! production Postgres instance.

const std = @import("std");
const zent = @import("zent");

pub const DriverKind = enum {
    sqlite,
    postgres,
};

/// zent ConnPool `stats()` 的驱动无关快照（sqlite / postgres 池字段一致）。
/// 单独定义而不直接暴露 ConnPool 的 Stats：StoreEnv 内部两个池类型是本
/// 文件私有别名，外部（/metrics 导出）只需字段值，不应感知泛型池类型。
pub const PoolStats = struct {
    total: usize,
    in_use: usize,
    available: usize,
    waiters: usize,
    exhausted_total: u64,
    closed: bool,
};

fn fromPoolStats(s: anytype) PoolStats {
    return .{
        .total = s.total,
        .in_use = s.in_use,
        .available = s.available,
        .waiters = s.waiters,
        .exhausted_total = s.exhausted_total,
        .closed = s.closed,
    };
}

/// RAII wrapper over the shared zent store: owns the driver, migrates each
/// schema group (small comptime graphs — zent's migration generator has a
/// per-call branch quota), and exposes one type-safe client for all tables.
///
/// The driver lives on the heap: `makeClient` captures `driver.asDriver()`
/// which is a pointer, so the driver must outlive `open`'s frame (a value
/// copy of `Self` is returned). Heap allocation keeps that pointer stable.
pub fn StoreEnv(comptime ClientInfos: anytype, comptime MigrateGroups: anytype) type {
    return struct {
        allocator: std.mem.Allocator,
        kind: DriverKind,
        sqlite_pool: ?*SqlitePool = null,
        sqlite_ctx: ?*SqliteCtx = null,
        pg_pool: ?*PgPool = null,
        pg_ctx: ?*PgCtx = null,
        client: zent.codegen.client.Client(ClientInfos),

        const Self = @This();

        const SqlitePool = zent.sql_pool.ConnPool(zent.sql_sqlite.SQLiteDriver);
        const SqliteCtx = struct { path: []const u8 };
        fn connectSqlite(ctx: ?*anyopaque, allocator: std.mem.Allocator) anyerror!zent.sql_sqlite.SQLiteDriver {
            const c: *SqliteCtx = @ptrCast(@alignCast(ctx.?));
            var driver = try zent.sql_sqlite.SQLiteDriver.open(allocator, c.path);
            // WAL + 连接池：HTTP 多线程并发查询时单连接会 segfault。
            _ = try driver.exec("PRAGMA journal_mode=WAL", &.{});
            _ = try driver.exec("PRAGMA synchronous=NORMAL", &.{});
            return driver;
        }

        const PgPool = zent.sql_pool.ConnPool(zent.sql_postgres.PostgresDriver);
        const PgCtx = struct { dsn: []const u8 };
        fn connectPg(ctx: ?*anyopaque, allocator: std.mem.Allocator) anyerror!zent.sql_postgres.PostgresDriver {
            const c: *PgCtx = @ptrCast(@alignCast(ctx.?));
            return zent.sql_postgres.PostgresDriver.connect(allocator, c.dsn);
        }

        pub fn asDriver(self: *const Self) zent.sql_driver.Driver {
            return switch (self.kind) {
                .sqlite => self.sqlite_pool.?.asDriver(),
                .postgres => self.pg_pool.?.asDriver(),
            };
        }

        /// 连接池只读快照（供 /metrics 导出）：两种驱动都走 zent ConnPool
        /// （sqlite 非 :memory: 时 max=8），因此 sqlite 也导出池指标；池尚
        /// 未建立时返回 null。stats() 内部持池锁，抓取路径调用即可。
        pub fn poolStats(self: *Self) ?PoolStats {
            switch (self.kind) {
                .sqlite => {
                    const p = self.sqlite_pool orelse return null;
                    return fromPoolStats(p.stats());
                },
                .postgres => {
                    const p = self.pg_pool orelse return null;
                    return fromPoolStats(p.stats());
                },
            }
        }

        pub fn open(allocator: std.mem.Allocator, kind: DriverKind, dsn: []const u8) !Self {
            var self: Self = .{
                .allocator = allocator,
                .kind = kind,
                .client = undefined,
            };
            switch (kind) {
                .sqlite => {
                    // 连接池（mutex + borrow）：与 Postgres 一致，避免并发请求共享单连接崩溃。
                    const pool = try allocator.create(SqlitePool);
                    errdefer allocator.destroy(pool);
                    const ctx = try allocator.create(SqliteCtx);
                    errdefer allocator.destroy(ctx);
                    ctx.* = .{ .path = dsn };
                    const max_conns: usize = if (std.mem.eql(u8, dsn, ":memory:")) 1 else 8;
                    pool.* = try SqlitePool.init(allocator, .{
                        .min_connections = 1,
                        .max_connections = max_conns,
                        .health_check_on_borrow = false,
                        .connect_ctx = ctx,
                        .connectCtx = connectSqlite,
                    });
                    errdefer pool.deinit();
                    const d = pool.asDriver();
                    inline for (MigrateGroups) |gi| {
                        try zent.sql_schema.migrateSchema(allocator, d, gi);
                    }
                    self.sqlite_ctx = ctx;
                    self.sqlite_pool = pool;
                    self.client = zent.codegen.client.makeClient(ClientInfos, allocator, d);
                },
                .postgres => {
                    // PG 连接池（mutex + borrow）：每查询独占连接，多线程安全。
                    // 单连接（max=1）安全但吞吐受限；max=8 为并发吞吐正解。
                    const pool = try allocator.create(PgPool);
                    errdefer allocator.destroy(pool);
                    const ctx = try allocator.create(PgCtx);
                    errdefer allocator.destroy(ctx);
                    ctx.* = .{ .dsn = dsn };
                    pool.* = try PgPool.init(allocator, .{
                        .min_connections = 2,
                        .max_connections = 8,
                        .health_check_on_borrow = false,
                        .connect_ctx = ctx,
                        .connectCtx = connectPg,
                    });
                    errdefer pool.deinit();
                    const d = pool.asDriver();
                    // 迁移锁：pg_advisory_lock 跨实例互斥，防止多实例同时启动
                    // 竞态建表（首个实例拿到锁执行迁移，其余实例阻塞等待；
                    // 连接断开自动释放）。key = "ZEWQ" 的 32 位魔数。
                    _ = try d.exec("SELECT pg_advisory_lock(1515040593)", &.{});
                    // 迁移失败的清理路径:此处解锁失败已无可挽回,而连接随
                    // pool.deinit() 关闭时 PG 会自动释放会话级咨询锁,
                    // 不会挡住后续实例启动,故吞掉。
                    errdefer _ = d.exec("SELECT pg_advisory_unlock(1515040593)", &.{}) catch {};
                    inline for (MigrateGroups) |gi| {
                        try zent.sql_schema.migrateSchema(allocator, d, gi);
                    }
                    _ = try d.exec("SELECT pg_advisory_unlock(1515040593)", &.{});
                    self.pg_ctx = ctx;
                    self.pg_pool = pool;
                    self.client = zent.codegen.client.makeClient(ClientInfos, allocator, d);
                },
            }
            return self;
        }

        pub fn deinit(self: *Self) void {
            switch (self.kind) {
                .sqlite => {
                    if (self.sqlite_pool) |p| {
                        p.deinit();
                        self.allocator.destroy(p);
                    }
                    if (self.sqlite_ctx) |c| {
                        self.allocator.destroy(c);
                    }
                },
                .postgres => {
                    if (self.pg_pool) |p| {
                        p.deinit();
                        self.allocator.destroy(p);
                    }
                    if (self.pg_ctx) |c| {
                        self.allocator.destroy(c);
                    }
                },
            }
            self.* = undefined;
        }
    };
}
