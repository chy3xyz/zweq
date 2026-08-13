//! DB store lifecycle: open driver (sqlite | postgres) → migrate schema →
//! make zent client. Same pattern as zweq's db.zig (RAII StoreEnv).

const std = @import("std");
const zent = @import("zent");

pub const DriverKind = enum { sqlite, postgres };

pub fn StoreEnv(comptime ClientInfos: anytype, comptime MigrateGroups: anytype) type {
    return struct {
        allocator: std.mem.Allocator,
        kind: DriverKind,
        sqlite: ?*zent.sql_sqlite.SQLiteDriver = null,
        pg: ?*zent.sql_postgres.PostgresDriver = null,
        client: zent.codegen.client.Client(ClientInfos),

        const Self = @This();

        pub fn open(allocator: std.mem.Allocator, kind: DriverKind, dsn: []const u8) !Self {
            var self: Self = .{ .allocator = allocator, .kind = kind, .client = undefined };
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
                    const d = driver.asDriver();
                    _ = try d.exec("SELECT pg_advisory_lock(1515040594)", &.{});
                    errdefer _ = d.exec("SELECT pg_advisory_unlock(1515040594)", &.{}) catch {};
                    inline for (MigrateGroups) |gi| {
                        try zent.sql_schema.migrateSchema(allocator, d, gi);
                    }
                    _ = try d.exec("SELECT pg_advisory_unlock(1515040594)", &.{});
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
