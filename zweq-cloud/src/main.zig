//! zweq-cloud — 独立云服务（授权码 + 应用市场），与 zweq 同架构
//! （zigmodu + zent 模块化六件套）。
//!
//! 站点端（zweq）通过授权码校验 + 市场包下载与此服务对接。

const std = @import("std");
const zigmodu = @import("zigmodu");
const config_mod = @import("config.zig");
const db_mod = @import("db.zig");
const schema = @import("schema.zig");
const storage_mod = @import("storage.zig");
const license = @import("modules/license/root.zig");
const market = @import("modules/market/root.zig");

// ── 请求上下文感知的 panic 钩子 ─────────────────────────────────────
// 语义同 zigmodu api/PanicHook.zig（panic 前把当事请求 METHOD /path 打到
// stderr 再交回默认 panic）。不直接用 zmodu.panicHook：上游 writeStderr
// 引用了 0.17.0-dev 已移除的 std.posix.write（lazy analysis 漏网），
// 应用根一接线即编译错。zweq-cloud 是独立包（不能 import 主站
// src/middleware/panic_hook.zig），故在此内联同一份实现，改动需双份同步。
const PanicHook = struct {
    const BUF_SIZE = 512;
    threadlocal var request_buf: [BUF_SIZE]u8 = undefined;
    threadlocal var request_len: usize = 0;

    fn setRequestContext(method: []const u8, path: []const u8) void {
        var len: usize = 0;
        const m = method[0..@min(method.len, 16)];
        @memcpy(request_buf[len..][0..m.len], m);
        len += m.len;
        request_buf[len] = ' ';
        len += 1;
        const room = BUF_SIZE - len;
        const p = path[0..@min(path.len, room)];
        @memcpy(request_buf[len..][0..p.len], p);
        len += p.len;
        request_len = len;
    }

    fn clearRequestContext() void {
        request_len = 0;
    }

    fn withRequestContext(msg: []const u8, first_trace_addr: ?usize) noreturn {
        @branchHint(.cold);
        if (request_len > 0) {
            const prefix = "panic while handling request: ";
            var out: [prefix.len + BUF_SIZE + 1]u8 = undefined;
            @memcpy(out[0..prefix.len], prefix);
            @memcpy(out[prefix.len..][0..request_len], request_buf[0..request_len]);
            out[prefix.len + request_len] = '\n';
            writeStderr(out[0 .. prefix.len + request_len + 1]);
        }
        std.debug.defaultPanic(msg, first_trace_addr);
    }

    fn writeStderr(bytes: []const u8) void {
        var rest = bytes;
        while (rest.len > 0) {
            const n = std.posix.system.write(std.posix.STDERR_FILENO, rest.ptr, rest.len);
            if (n <= 0) return;
            rest = rest[@intCast(n)..];
        }
    }

    pub const hook = std.debug.FullPanic(withRequestContext);

    fn recordRequestContext() zigmodu.http.Middleware {
        return .{
            .func = struct {
                fn handle(ctx: *zigmodu.http.Context, next: zigmodu.http.HandlerFn, _: ?*anyopaque) anyerror!void {
                    setRequestContext(ctx.method.toString(), ctx.path);
                    defer clearRequestContext();
                    try next(ctx);
                }
            }.handle,
        };
    }
};

pub const panic = PanicHook.hook;

const ShutdownFlag = struct {
    var requested = std.atomic.Value(bool).init(false);
};

fn onShutdownSignal(_: std.posix.SIG) callconv(.c) void {
    ShutdownFlag.requested.store(true, .release);
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;
    const cfg = config_mod.Config.fromEnv(init.environ_map);

    std.log.info("zweq-cloud starting (db={s}, port={d})", .{ cfg.db_driver, cfg.http_port });

    const kind: db_mod.DriverKind = if (std.mem.eql(u8, cfg.db_driver, "postgres")) .postgres else .sqlite;
    const dsn = if (kind == .postgres) cfg.pg_conninfo else cfg.sqlite_path;
    var store_env = try db_mod.StoreEnv(schema.infos, .{
        license.persistence.infos,
        market.persistence.infos,
    }).open(allocator, kind, dsn);
    defer store_env.deinit();
    std.log.info("[zent] migrated schema via {s}", .{@tagName(kind)});

    var license_store = license.persistence.LicenseStore.init(allocator, store_env.client);
    var license_svc = license.service.LicenseService.init(allocator, io, &license_store);
    var market_store = market.persistence.MarketStore.init(allocator, store_env.client);
    // 产物托管后端：local（默认目录）或 s3（S3-compatible）。
    var local_artifact = storage_mod.LocalArtifactStorage.init(allocator, io, cfg.artifact_dir);
    var s3_artifact = storage_mod.S3ArtifactStorage.init(allocator, .{
        .endpoint = cfg.s3_endpoint,
        .bucket = cfg.s3_bucket,
        .region = cfg.s3_region,
        .access_key = cfg.s3_access_key,
        .secret_key = cfg.s3_secret_key,
    });
    const artifact_storage = if (std.mem.eql(u8, cfg.storage_backend, "s3"))
        s3_artifact.storage()
    else
        local_artifact.storage();
    var market_svc = market.service.MarketService.init(allocator, io, &market_store, artifact_storage);

    var app = try zigmodu.Application.init(io, allocator, "zweq-cloud", .{
        license.module,
        market.module,
    }, .{});
    defer app.deinit();
    try app.start();
    defer app.stop();
    const module_count = app.modules.modules.count();

    var server = zigmodu.http.Server.initWithConfig(io, allocator, .{
        .port = cfg.http_port,
        .name = "zweq-cloud",
        .max_body_size = 16 * 1024 * 1024,
    });
    defer server.deinit();
    try server.addMiddleware(PanicHook.recordRequestContext());

    var v1 = server.group("/api/v1");
    var license_api = license.api.LicenseApi(@TypeOf(license_svc)).init(&license_svc, cfg.admin_token);
    try license_api.registerRoutes(&v1);
    var market_api = market.api.MarketApi(@TypeOf(market_svc)).init(&market_svc, cfg.admin_token);
    try market_api.registerRoutes(&v1);

    // health
    try server.addRoute(.{
        .method = .GET,
        .path = "health/live",
        .handler = struct {
            fn handle(ctx: *zigmodu.http.Context) !void {
                try ctx.json(200, "{\"code\":0,\"msg\":\"ok\",\"data\":{\"status\":\"UP\"}}");
            }
        }.handle,
    });

    std.log.info("zweq-cloud listening on http://127.0.0.1:{d} ({d} modules)", .{ cfg.http_port, module_count });

    // 优雅关闭：SIGINT/SIGTERM → stop accept → 排空在途请求。
    const sig = std.posix.Sigaction{
        .handler = .{ .handler = onShutdownSignal },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.INT, &sig, null);
    std.posix.sigaction(std.posix.SIG.TERM, &sig, null);

    const ServerThread = struct {
        fn run(s: *zigmodu.http.Server) !void {
            try s.start(); // 阻塞；stop() 后返回。
        }
    };
    const server_handle = try std.Thread.spawn(.{ .stack_size = 4 * 1024 * 1024 }, ServerThread.run, .{&server});
    defer server_handle.join();

    const poll = std.posix.timespec{ .sec = 0, .nsec = 100 * std.time.ns_per_ms };
    while (!ShutdownFlag.requested.load(.acquire)) {
        _ = std.c.nanosleep(&poll, null);
    }
    std.log.info("shutdown signal received, draining in-flight requests...", .{});
    server.stop();
    server_handle.join();
}
