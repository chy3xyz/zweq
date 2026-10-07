const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zigmodu_dep = b.dependency("zigmodu", .{ .target = target, .optimize = optimize, .db = "sqlite,postgres" });
    const zent_dep = b.dependency("zent", .{
        .target = target,
        .optimize = optimize,
        // 与主站一致：zent 0.76+ 按选项收窄 translate-c 驱动绑定（postgres 选项名是 pg）。
        .sqlite = true,
        .pg = true,
        .mysql = false,
    });
    // zent 0.81.1+ 的官方驱动链接（target-aware 探测），替代镜像的 db_link.link。
    const zent_build = b.lazyImport(@This(), "zent").?;
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
    zent_build.linkDrivers(b, exe_mod, target, .{ .sqlite = true, .pg = true, .mysql = false });

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
    zent_build.linkDrivers(b, tests_mod, target, .{ .sqlite = true, .pg = true, .mysql = false });

    const tests = b.addTest(.{ .root_module = tests_mod });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
