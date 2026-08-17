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
        sqlite: ?*zent.sql_sqlite.SQLiteDriver = null,
        pg_pool: ?*PgPool = null,
        client: zent.codegen.client.Client(ClientInfos),

        const Self = @This();

        const PgPool = zent.sql_pool.ConnPool(zent.sql_postgres.PostgresDriver);
        const PgCtx = struct { dsn: []const u8 };
        fn connectPg(ctx: ?*anyopaque, allocator: std.mem.Allocator) anyerror!zent.sql_postgres.PostgresDriver {
            const c: *PgCtx = @ptrCast(@alignCast(ctx.?));
            return zent.sql_postgres.PostgresDriver.connect(allocator, c.dsn);
        }

        pub fn open(allocator: std.mem.Allocator, kind: DriverKind, dsn: []const u8) !Self {
            var self: Self = .{
                .allocator = allocator,
                .kind = kind,
                .client = undefined,
            };
            switch (kind) {
                .sqlite => {
                    const driver = try allocator.create(zent.sql_sqlite.SQLiteDriver);
                    errdefer allocator.destroy(driver);
                    driver.* = try zent.sql_sqlite.SQLiteDriver.open(allocator, dsn);
                    errdefer driver.close();
                    inline for (MigrateGroups) |gi| {
                        try zent.sql_schema.migrateSchema(allocator, driver.asDriver(), gi);
                    }
                    self.sqlite = driver;
                    self.client = zent.codegen.client.makeClient(ClientInfos, allocator, driver.asDriver());
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
                    errdefer _ = d.exec("SELECT pg_advisory_unlock(1515040593)", &.{}) catch {};
                    inline for (MigrateGroups) |gi| {
                        try zent.sql_schema.migrateSchema(allocator, d, gi);
                    }
                    _ = try d.exec("SELECT pg_advisory_unlock(1515040593)", &.{});
                    self.pg_pool = pool;
                    self.client = zent.codegen.client.makeClient(ClientInfos, allocator, d);
                },
            }
            return self;
        }

        pub fn deinit(self: *Self) void {
            switch (self.kind) {
                .sqlite => {
                    if (self.sqlite) |d| {
                        d.close();
                        self.allocator.destroy(d);
                    }
                },
                .postgres => {
                    if (self.pg_pool) |p| {
                        p.deinit();
                        self.allocator.destroy(p);
                    }
                },
            }
            self.* = undefined;
        }
    };
}
