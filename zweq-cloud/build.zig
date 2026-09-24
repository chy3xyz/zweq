const std = @import("std");
const db_link = @import("db_link.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 驱动面 = SQLite + PostgreSQL（同主站；postgres 是 zweq-cloud 的运行选项），不含 mysql。
    const features: db_link.Features = .{ .sqlite = true, .postgres = true };

    const zigmodu_dep = b.dependency("zigmodu", .{ .target = target, .optimize = optimize, .db = "sqlite,postgres" });
    const zent_dep = b.dependency("zent", .{
        .target = target,
        .optimize = optimize,
        // 与主站一致：zent 0.76+ 按选项收窄 translate-c 驱动绑定（postgres 选项名是 pg）。
        .sqlite = true,
        .pg = true,
        .mysql = false,
    });
    const zwechat_dep = b.dependency("zwechat", .{
        .target = target,
        .optimize = optimize,
        // 同主站：支付 v2 mTLS 端点仍提供，启用运行时 dlopen 实现（构建期零 C 依赖成本）。
        .mtls = true,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    exe_mod.addImport("zigmodu", zigmodu_dep.module("zigmodu"));
    exe_mod.addImport("zent", zent_dep.module("zent"));
    exe_mod.addImport("zwechat", zwechat_dep.module("zwechat"));
    db_link.link(exe_mod, b, features);

    const exe = b.addExecutable(.{ .name = "zweq-cloud", .root_module = exe_mod });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the zweq-cloud server");
    run_step.dependOn(&run_cmd.step);

    const tests_mod = b.createModule(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    tests_mod.addImport("zigmodu", zigmodu_dep.module("zigmodu"));
    tests_mod.addImport("zent", zent_dep.module("zent"));
    tests_mod.addImport("zwechat", zwechat_dep.module("zwechat"));
    db_link.link(tests_mod, b, features);

    const tests = b.addTest(.{ .root_module = tests_mod });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
