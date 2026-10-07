//! `-Ddb=` 驱动面解析（build-scripts only）。驱动链接本身走 zent 上游的
//! `zent_build.linkDrivers`（target-aware 探测，0.81.1+）——本文件不再有
//! 镜像探测副本。

const std = @import("std");

pub const Features = struct {
    sqlite: bool = false,
    postgres: bool = false,
    mysql: bool = false,

    pub const all: Features = .{ .sqlite = true, .postgres = true, .mysql = true };
    pub const sqlite_only: Features = .{ .sqlite = true, .postgres = false, .mysql = false };

    pub fn any(self: Features) bool {
        return self.sqlite or self.postgres or self.mysql;
    }
};

pub const ParseError = error{InvalidDbOption};

/// Parse `-Ddb=` value: `all` | `sqlite` | `postgres` | `mysql` | comma-list.
pub fn parseDb(s: []const u8) ParseError!Features {
    const trimmed = std.mem.trim(u8, s, " \t\r\n");
    if (trimmed.len == 0) return error.InvalidDbOption;
    if (std.mem.eql(u8, trimmed, "all")) return Features.all;

    var features: Features = .{};
    var it = std.mem.splitScalar(u8, trimmed, ',');
    var saw_any = false;
    while (it.next()) |raw| {
        const part = std.mem.trim(u8, raw, " \t");
        if (part.len == 0) continue;
        saw_any = true;
        if (std.mem.eql(u8, part, "all")) {
            return Features.all;
        } else if (std.mem.eql(u8, part, "sqlite")) {
            features.sqlite = true;
        } else if (std.mem.eql(u8, part, "postgres") or std.mem.eql(u8, part, "postgresql") or std.mem.eql(u8, part, "pg")) {
            features.postgres = true;
        } else if (std.mem.eql(u8, part, "mysql") or std.mem.eql(u8, part, "mariadb")) {
            features.mysql = true;
        } else {
            return error.InvalidDbOption;
        }
    }
    if (!saw_any or !features.any()) return error.InvalidDbOption;
    return features;
}
