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
        pg: ?*zent.sql_postgres.PostgresDriver = null,
        client: zent.codegen.client.Client(ClientInfos),

        const Self = @This();

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
                    const driver = try allocator.create(zent.sql_postgres.PostgresDriver);
                    errdefer allocator.destroy(driver);
                    driver.* = try zent.sql_postgres.PostgresDriver.connect(allocator, dsn);
                    errdefer driver.close();
                    // 迁移锁：pg_advisory_lock 跨实例互斥，防止多实例同时启动
                    // 竞态建表（首个实例拿到锁执行迁移，其余实例阻塞等待；
                    // 连接断开自动释放）。key = "ZEWQ" 的 32 位魔数。
                    const d = driver.asDriver();
                    _ = try d.exec("SELECT pg_advisory_lock(1515040593)", &.{});
                    errdefer _ = d.exec("SELECT pg_advisory_unlock(1515040593)", &.{}) catch {};
                    inline for (MigrateGroups) |gi| {
                        try zent.sql_schema.migrateSchema(allocator, d, gi);
                    }
                    _ = try d.exec("SELECT pg_advisory_unlock(1515040593)", &.{});
                    self.pg = driver;
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
                    if (self.pg) |d| {
                        d.close();
                        self.allocator.destroy(d);
                    }
                },
            }
            self.* = undefined;
        }
    };
}
