const std = @import("std");
const db_link = @import("db_link.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 按需链接 SQL 驱动：本仓库驱动面 = SQLite（开发/测试/默认运行时）+ PostgreSQL（生产），
    // MySQL 从不使用，默认不再链接（少一个部署依赖、少一份攻击面）。需要全量可 -Ddb=all。
    const db_opt = b.option([]const u8, "db", "SQL drivers to link: all|sqlite|postgres|mysql (comma-list)") orelse "sqlite,postgres";
    const features = db_link.parseDb(db_opt) catch {
        @panic("invalid -Ddb= value; use all|sqlite|postgres|mysql (comma-list ok)");
    };

    const zigmodu_dep = b.dependency("zigmodu", .{
        .target = target,
        .optimize = optimize,
        // 同步收窄 zigmodu 自身的驱动链接（它默认 all）。
        .db = db_opt,
    });
    const zent_dep = b.dependency("zent", .{
        .target = target,
        .optimize = optimize,
        // zent 0.76+ 按构建选项收窄 translate-c 驱动绑定（默认"头文件在就翻译"）：
        // 与本仓库 -Ddb 驱动面保持一致，不为不链接的驱动付 ~30s/~590MB 的翻译成本。
        .sqlite = features.sqlite,
        .pg = features.postgres,
        .mysql = features.mysql,
    });
    const zwechat_dep = b.dependency("zwechat", .{
        .target = target,
        .optimize = optimize,
        // v0.5.0 起 mTLS 改为 -Dmtls 可选（默认关，zhttp 依赖已移除）。我们仍提供
        // 支付 v2 退款/转账端点（配置了 cert_p12 时走 mTLS），故保持启用——
        // 实现是运行时 dlopen OpenSSL，构建期不链 C 库、不需要头文件，成本仅 link_libc。
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

    const exe = b.addExecutable(.{ .name = "zweq", .root_module = exe_mod });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the zweq server");
    run_step.dependOn(&run_cmd.step);

    // Admin CLI (create/list administrator accounts)
    const admin_mod = b.createModule(.{
        .root_source_file = b.path("src/admin_cli.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    admin_mod.addImport("zigmodu", zigmodu_dep.module("zigmodu"));
    admin_mod.addImport("zent", zent_dep.module("zent"));
    admin_mod.addImport("zwechat", zwechat_dep.module("zwechat"));
    db_link.link(admin_mod, b, features);

    const admin_exe = b.addExecutable(.{ .name = "zweq-admin", .root_module = admin_mod });
    b.installArtifact(admin_exe);

    const admin_cmd = b.addRunArtifact(admin_exe);
    admin_cmd.step.dependOn(b.getInstallStep());
    const admin_step = b.step("admin", "Admin CLI help; run zig-out/bin/zweq-admin create-admin --email you@example.com");
    admin_step.dependOn(&admin_cmd.step);

    // Unit tests
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

    // 体积门禁：任一 src/**/*.zig 超过行数预算即失败（防巨型单体回潮）。
    const size_check = b.addSystemCommand(&.{ "/bin/sh", "scripts/check_file_size.sh" });
    const lint_size = b.step("lint-size", "Fail if any src/**/*.zig exceeds the line budget");
    lint_size.dependOn(&size_check.step);

    // 分配器归属门禁：拦“用请求 arena 释放长期分配器对象”（arena.free 是 no-op
    // → 静默泄漏）。单元测试抓不到这一类（两侧同为 testing allocator），只能静态查。
    const alloc_check = b.addSystemCommand(&.{ "python3", "scripts/check_alloc_owner.py", "src" });
    const lint_alloc = b.step("lint-alloc", "Fail if an entity is freed with an allocator that does not own it");
    lint_alloc.dependOn(&alloc_check.step);

    // 格式门禁：任一 src/**/*.zig 不符合 zig fmt 即失败（提交前先 `zig fmt src`）。
    const fmt_check = b.addSystemCommand(&.{ b.graph.zig_exe, "fmt", "--check", "src" });
    const lint_fmt = b.step("lint-fmt", "Fail if any src/**/*.zig is not zig-fmt clean");
    lint_fmt.dependOn(&fmt_check.step);
}
