//! zweq — a production-grade admin framework built on zigmodu + zent.
//!
//! Single binary serves the JSON admin API; the Solid SPA in `web/`
//! talks to it over `/api/v1`. Run:
//!   zig build run                          # sqlite (zweq.db)
//!   ZWEQ_DB_DRIVER=postgres ZWEQ_PG_CONNINFO='host=... dbname=zweq user=postgres password=...' zig build run
//!   zig build admin -- --email you@example.com   # create the first admin
//!
//! Feature surface:
//!   auth (register/login/logout/reset/verify/me/profile/password), user CRUD,
//!   durable background tasks + dispatcher, email (SMTP + console), cache,
//!   file uploads, notifications, cron housekeeping, access logs, security
//!   headers, health/ready probes, runtime diagnostics.

const std = @import("std");
const zigmodu = @import("zigmodu");
const config_mod = @import("config.zig");
const db_mod = @import("db.zig");
const schema = @import("schema.zig");
const access_log_mod = @import("middleware/access_log.zig");
const sec_headers = @import("middleware/security_headers.zig");
const metrics_mod = @import("middleware/metrics.zig");
const mail = @import("services/mail.zig");
const cache_svc = @import("services/cache.zig");
const jobs = @import("jobs.zig");
const scheduled = @import("scheduled.zig");
const user = @import("modules/user/root.zig");
const auth = @import("modules/auth/root.zig");
const task = @import("modules/task/root.zig");
const file = @import("modules/file/root.zig");
const notify = @import("modules/notify/root.zig");
const system = @import("modules/system/root.zig");
const tenant = @import("modules/tenant/root.zig");
const audit = @import("modules/audit/root.zig");
const mail_template = @import("modules/mail_template/root.zig");
const ai = @import("modules/ai/root.zig");
const account = @import("modules/account/root.zig");
const permission = @import("modules/permission/root.zig");
const setting = @import("modules/setting/root.zig");
const rule = @import("modules/rule/root.zig");
const member = @import("modules/member/root.zig");
const message = @import("modules/message/root.zig");
const appmod = @import("modules/module/root.zig");
const payment = @import("modules/payment/root.zig");
const app_bff = @import("modules/app_bff/root.zig");
const cloud = @import("modules/cloud/root.zig");
const material = @import("modules/material/root.zig");

/// Set by SIGINT/SIGTERM so the main thread can stop the server gracefully.
const ShutdownFlag = struct {
    var requested = std.atomic.Value(bool).init(false);
};

fn onShutdownSignal(_: std.posix.SIG) callconv(.c) void {
    ShutdownFlag.requested.store(true, .release);
}

/// Shared state for scheduled housekeeping jobs (single background thread —
/// zent's SQLite driver is a single connection).
const CleanupCtx = struct {
    io: std.Io,
    user_store: *user.persistence.UserStore,
    notify_store: *notify.persistence.NotificationStore,
    audit_store: *audit.persistence.AuditStore,
    password_token_max_age: i64,
    verification_token_max_age: i64,
    notification_max_age: i64,
    audit_retention_seconds: i64,
};

fn jobTokensCleanup(ctx: ?*anyopaque) void {
    const c: *CleanupCtx = @ptrCast(@alignCast(ctx orelse return));
    const now = zigmodu.time.wallClockSeconds(c.io);
    _ = c.user_store.purgeExpiredPasswordTokens(now, c.password_token_max_age) catch {};
    _ = c.user_store.purgeExpiredEmailVerifications(now, c.verification_token_max_age) catch {};
}

fn jobNotifyPrune(ctx: ?*anyopaque) void {
    const c: *CleanupCtx = @ptrCast(@alignCast(ctx orelse return));
    const now = zigmodu.time.wallClockSeconds(c.io);
    _ = c.notify_store.purgeOlderThan(now, c.notification_max_age) catch {};
}

fn jobAuditPrune(ctx: ?*anyopaque) void {
    const c: *CleanupCtx = @ptrCast(@alignCast(ctx orelse return));
    const now = zigmodu.time.wallClockSeconds(c.io);
    _ = c.audit_store.purgeOlderThan(now, c.audit_retention_seconds) catch {};
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    const cfg = config_mod.Config.fromEnv(init.environ_map);
    // 生产(PostgreSQL)必须显式设置 JWT 密钥,拒绝使用默认值。
    if (!cfg.jwt_secret_explicit and std.mem.eql(u8, cfg.db_driver, "postgres")) {
        std.log.err("ZWEQ_JWT_SECRET must be set explicitly in production (PostgreSQL). Refusing to start with the default dev secret.", .{});
        return error.MissingJwtSecret;
    }
    std.log.info("zweq starting (db={s}, port={d})", .{ cfg.db_driver, cfg.http_port });

    // ── Data store: zent driver + schema-as-code migration ──
    const kind: db_mod.DriverKind = if (std.mem.eql(u8, cfg.db_driver, "postgres")) .postgres else .sqlite;
    const dsn = if (kind == .postgres) cfg.pg_conninfo else cfg.sqlite_path;
    var store_env = try db_mod.StoreEnv(schema.infos, .{
        tenant.persistence.infos,
        user.persistence.infos,
        task.persistence.infos,
        file.persistence.infos,
        notify.persistence.infos,
        audit.persistence.infos,
        mail_template.persistence.infos,
        ai.persistence.provider_infos,
        ai.persistence.session_infos,
        ai.persistence.message_infos,
        ai.persistence.approval_infos,
        ai.persistence.run_infos,
        account.persistence.infos,
        permission.persistence.infos,
        setting.persistence.infos,
        rule.persistence.infos,
        member.persistence.infos,
        message.persistence.infos,
        appmod.persistence.infos,
        payment.persistence.infos,
        cloud.persistence.infos,
        material.persistence.infos,
    }).open(allocator, kind, dsn);
    defer store_env.deinit();
    std.log.info("[zent] migrated schema via {s} ({s})", .{ @tagName(kind), dsn });

    // ── Domain services ──
    var store = user.persistence.UserStore.init(allocator, store_env.client);
    var sec = zigmodu.security.AppSecurity.init(allocator, io, .{
        .jwt_secret = cfg.jwt_secret,
        .token_expiry_seconds = cfg.token_expiry_seconds,
    });
    var mailer = mail.Mailer.init(
        allocator,
        io,
        cfg.smtp_host,
        cfg.smtp_port,
        cfg.smtp_username,
        cfg.smtp_password,
        cfg.smtp_from,
        cfg.smtp_starttls,
        cfg.mail_console,
    );
    defer mailer.deinit();
    var cache = cache_svc.CacheService.init(allocator, cfg.cache_max_entries, cfg.cache_ttl_seconds);
    defer cache.deinit();

    var user_svc = user.service.UserService.init(
        &store,
        &sec,
        io,
        cfg.password_token_expiration_seconds,
        cfg.verification_token_expiration_seconds,
    );
    var task_store = task.persistence.TaskStore.init(allocator, store_env.client);
    var task_svc = task.service.TaskService.init(&task_store, io, cfg.task_max_attempts);
    var notify_store = notify.persistence.NotificationStore.init(allocator, store_env.client);
    var notify_svc = notify.service.NotificationService.init(allocator, io, &notify_store);
    var file_store = file.persistence.FileStore.init(allocator, store_env.client);
    var file_svc = file.service.FileService.init(allocator, io, &file_store, cfg.upload_dir, cfg.upload_max_bytes);
    try file_svc.ensureDir();
    var tenant_store = tenant.persistence.TenantStore.init(allocator, store_env.client);
    var tenant_svc = tenant.service.TenantService.init(allocator, io, &tenant_store);
    const default_tenant_id = try tenant_svc.ensureDefault();
    std.log.info("[tenant] default tenant ready (id={d})", .{default_tenant_id});

    var account_store = account.persistence.AccountStore.init(allocator, store_env.client);
    var account_svc = account.service.AccountService.init(allocator, io, &account_store);
    var role_store = permission.persistence.RoleStore.init(allocator, store_env.client);
    var role_svc = permission.service.RoleService.init(allocator, io, &role_store);
    var setting_store = setting.persistence.SettingStore.init(allocator, store_env.client);
    var setting_svc = setting.service.SettingService.init(allocator, io, &setting_store);
    var rule_store = rule.persistence.RuleStore.init(allocator, store_env.client);
    var rule_svc = rule.service.RuleService.init(allocator, io, &rule_store);
    var fan_store = member.persistence.FanStore.init(allocator, store_env.client);
    var member_svc = member.service.MemberService.init(allocator, io, &fan_store);
    var message_store = message.persistence.MessageStore.init(allocator, store_env.client);
    var wechat_svc = message.service.WechatService.init(allocator, io, &account_svc, &rule_svc, &member_svc, &setting_store, &message_store);
    var app_module_store = appmod.persistence.ModuleStore.init(allocator, store_env.client);
    var module_svc = appmod.service.ModuleService.init(allocator, io, &app_module_store);
    try module_svc.seedBuiltins(default_tenant_id);
    std.log.info("[module] built-in modules seeded", .{});
    var payment_store = payment.persistence.PaymentStore.init(allocator, store_env.client);
    var payment_svc = payment.service.PaymentService.init(allocator, io, &payment_store);
    var cloud_store = cloud.persistence.CloudStore.init(allocator, store_env.client);
    var cloud_svc = cloud.service.CloudService.init(allocator, io, &cloud_store, &module_svc);
    var material_store = material.persistence.MaterialStore.init(allocator, store_env.client);
    var material_svc = material.service.MaterialService.init(allocator, io, &material_store);

    var audit_store = audit.persistence.AuditStore.init(allocator, store_env.client);
    var audit_svc = audit.service.AuditService.init(allocator, io, &audit_store);

    var template_store = mail_template.persistence.TemplateStore.init(allocator, store_env.client);
    var template_svc = mail_template.service.MailTemplateService.init(allocator, io, &template_store);

    var ai_store = ai.persistence.AiStore.init(allocator, store_env.client);
    var ai_svc = try ai.service.AiService.init(allocator, io, &ai_store, .{
        .key_secret = cfg.ai_key_secret,
        .daily_run_limit = cfg.ai_daily_run_limit,
    }, .{
        .user_store = &store,
        .task_store = &task_store,
        .audit_store = &audit_store,
        .tenant_store = &tenant_store,
        .ai_store = &ai_store,
        .notify_svc = &notify_svc,
    });
    defer ai_svc.deinit();
    // Wire the AI assistant into the WeChat callback engine (AI auto-reply).
    wechat_svc.ai_svc = &ai_svc;

    // ── ZigModu module lifecycle (Application API: scan + validate + start/stop) ──
    var app = try zigmodu.Application.init(io, allocator, "zweq", .{
        tenant.module,
        user.module,
        auth.module,
        task.module,
        file.module,
        notify.module,
        system.module,
        audit.module,
        mail_template.module,
        ai.module,
        account.module,
        permission.module,
        setting.module,
        rule.module,
        member.module,
        message.module,
        appmod.module,
        payment.module,
        app_bff.module,
        cloud.module,
        material.module,
    }, .{});
    defer app.deinit();
    try app.start();
    defer app.stop();
    const module_count = app.modules.modules.count();

    // ── Background: task dispatcher + scheduled housekeeping ──
    var cleanup_ctx = CleanupCtx{
        .io = io,
        .user_store = &store,
        .notify_store = &notify_store,
        .audit_store = &audit_store,
        .password_token_max_age = cfg.password_token_expiration_seconds,
        .verification_token_max_age = cfg.verification_token_expiration_seconds,
        .notification_max_age = 30 * 24 * 3600,
        .audit_retention_seconds = cfg.audit_retention_days * 24 * 3600,
    };
    var scheduled_jobs = [_]scheduled.ScheduledJob{
        .{
            .name = "tokens.cleanup",
            .interval_seconds = 3600,
            .run = jobTokensCleanup,
            .ctx = &cleanup_ctx,
        },
        .{
            .name = "notify.prune",
            .interval_seconds = 24 * 3600,
            .run = jobNotifyPrune,
            .ctx = &cleanup_ctx,
        },
        .{
            .name = "audit.prune",
            .interval_seconds = 24 * 3600,
            .run = jobAuditPrune,
            .ctx = &cleanup_ctx,
        },
    };
    var scheduled_runner = scheduled.ScheduledRunner{ .jobs = &scheduled_jobs };

    const handler_registry = jobs.handlers(&mailer);
    var dispatcher = task.service.Dispatcher.init(
        allocator,
        io,
        &task_store,
        &handler_registry,
        cfg.task_retry_interval_seconds,
        300, // stale claim threshold (seconds)
    );
    dispatcher.scheduled = &scheduled_runner;
    try dispatcher.start();
    defer dispatcher.deinit();
    std.log.info("[task] dispatcher started ({d} handlers, {d} workers)", .{ handler_registry.len, cfg.task_workers });

    // ── HTTP API ──
    var login_limiter = try zigmodu.RateLimiter.init(allocator, "auth-public", 20, 1);
    defer login_limiter.deinit();

    var user_api = user.api.UserApi(@TypeOf(user_svc)).init(&user_svc, default_tenant_id, &audit_svc);
    var auth_api = auth.api.AuthApi(@TypeOf(user_svc)).init(&user_svc, cfg.app_host, &login_limiter, &mailer, &task_svc, &notify_svc, &audit_svc, &template_svc, default_tenant_id);
    var task_api = task.api.TaskApi(@TypeOf(task_svc), @TypeOf(user_svc)).init(&task_svc, &user_svc, &audit_svc);
    var file_api = file.api.FileApi(@TypeOf(file_svc), @TypeOf(user_svc)).init(&file_svc, &user_svc, &audit_svc, default_tenant_id);
    var notify_api = notify.api.NotificationApi(@TypeOf(notify_svc), @TypeOf(user_svc)).init(&notify_svc, &user_svc);
    var tenant_api = tenant.api.TenantApi(@TypeOf(tenant_svc), @TypeOf(user_svc)).init(&tenant_svc, &user_svc, &audit_svc);
    var account_api = account.api.AccountApi(@TypeOf(account_svc), @TypeOf(user_svc)).init(&account_svc, &user_svc, &audit_svc, default_tenant_id);
    var permission_api = permission.api.PermissionApi(@TypeOf(role_svc), @TypeOf(user_svc)).init(&role_svc, &user_svc, &audit_svc, default_tenant_id);
    var setting_api = setting.api.SettingApi(@TypeOf(setting_svc), @TypeOf(user_svc)).init(&setting_svc, &user_svc, &audit_svc, default_tenant_id);
    var rule_api = rule.api.RuleApi(@TypeOf(rule_svc), @TypeOf(user_svc)).init(&rule_svc, &user_svc, &audit_svc, default_tenant_id);
    var member_api = member.api.MemberApi(@TypeOf(member_svc), @TypeOf(user_svc)).init(&member_svc, &user_svc, &audit_svc, default_tenant_id);
    var message_api = message.api.MessageApi(@TypeOf(wechat_svc), @TypeOf(user_svc)).init(&wechat_svc, &user_svc, &audit_svc, default_tenant_id);
    var module_api = appmod.api.ModuleApi(@TypeOf(module_svc), @TypeOf(user_svc)).init(&module_svc, &user_svc, &audit_svc, default_tenant_id);
    var payment_api = payment.api.PaymentApi(@TypeOf(payment_svc), @TypeOf(user_svc)).init(&payment_svc, &user_svc, &audit_svc, default_tenant_id, &setting_store);
    var app_bff_api = app_bff.api.AppBffApi(@TypeOf(account_svc), @TypeOf(module_svc), @TypeOf(user_svc)).init(&account_svc, &module_svc, &user_svc, default_tenant_id);
    var cloud_api = cloud.api.CloudApi(@TypeOf(cloud_svc), @TypeOf(user_svc)).init(&cloud_svc, &user_svc, &audit_svc, default_tenant_id);
    var material_api = material.api.MaterialApi(@TypeOf(material_svc), @TypeOf(user_svc)).init(&material_svc, &user_svc, &audit_svc, default_tenant_id);
    var audit_api = audit.api.AuditApi(@TypeOf(audit_svc), @TypeOf(user_svc)).init(&audit_svc, &user_svc);
    var mail_template_api = mail_template.api.MailTemplateApi(@TypeOf(template_svc), @TypeOf(user_svc)).init(&template_svc, &user_svc);
    var ai_api = ai.api.AiApi(@TypeOf(ai_svc), @TypeOf(user_svc)).init(&ai_svc, &user_svc);
    var system_api = system.api.SystemApi(@TypeOf(cache), @TypeOf(task_svc)).init(
        &cache,
        &task_svc,
        &user_svc,
        &store,
        &file_store,
        &notify_store,
        &tenant_store,
        io,
        zigmodu.time.wallClockSeconds(io),
        @tagName(kind),
        cfg.smtp_host.len > 0,
        cfg.mail_console,
        module_count,
    );

    var server = zigmodu.http.Server.initWithConfig(io, allocator, .{
        .port = cfg.http_port,
        .name = "zweq",
        .max_body_size = cfg.upload_max_bytes + 64 * 1024,
    });
    defer server.deinit();

    const origins = try parseCorsOrigins(allocator, cfg.cors_origins);
    defer allocator.free(origins);

    var access_log = access_log_mod.AccessLog.init(allocator, 4096);
    defer access_log.deinit();
    var metrics = metrics_mod.Metrics.init(io);
    try server.addMiddleware(zigmodu.http.tracingMiddleware());
    try server.addMiddleware(metrics.middleware());
    try server.addMiddleware(sec_headers.securityHeaders());
    try server.addMiddleware(access_log.middleware());
    try server.addMiddleware(zigmodu.http.http_middleware.cors(.{ .allow_origins = origins }));

    var v1 = server.group("/api/v1");
    try auth_api.registerRoutes(&v1);
    try user_api.registerRoutes(&v1);
    try task_api.registerRoutes(&v1);
    try file_api.registerRoutes(&v1);
    try notify_api.registerRoutes(&v1);
    try tenant_api.registerRoutes(&v1);
    try account_api.registerRoutes(&v1);
    try permission_api.registerRoutes(&v1);
    try setting_api.registerRoutes(&v1);
    try rule_api.registerRoutes(&v1);
    try member_api.registerRoutes(&v1);
    try message_api.registerAdminRoutes(&v1);
    try module_api.registerRoutes(&v1);
    try payment_api.registerRoutes(&v1);
    try app_bff_api.registerRoutes(&v1);
    try cloud_api.registerRoutes(&v1);
    try material_api.registerRoutes(&v1);
    try audit_api.registerRoutes(&v1);
    try mail_template_api.registerRoutes(&v1);
    try ai_api.registerRoutes(&v1);
    try system_api.registerRoutes(&v1);

    // Health: liveness at the server root (probe convention) and readiness
    // under the API prefix (checks the data store).
    const Ready = struct {
        var user_store_ref: *user.persistence.UserStore = undefined;
    };
    Ready.user_store_ref = &store;
    try server.addRoute(.{
        .method = .GET,
        .path = "health/live",
        .handler = struct {
            fn handle(ctx: *zigmodu.http.Context) !void {
                try ctx.json(200, "{\"code\":0,\"msg\":\"ok\",\"data\":{\"status\":\"UP\"}}");
            }
        }.handle,
    });
    try server.addRoute(.{
        .method = .GET,
        .path = "api/v1/health/live",
        .handler = struct {
            fn handle(ctx: *zigmodu.http.Context) !void {
                try ctx.json(200, "{\"code\":0,\"msg\":\"ok\",\"data\":{\"status\":\"UP\"}}");
            }
        }.handle,
    });
    try server.addRoute(.{
        .method = .GET,
        .path = "api/v1/health/ready",
        .handler = struct {
            fn handle(ctx: *zigmodu.http.Context) !void {
                var probe = Ready.user_store_ref.listUsers(1, 1, null, null, null, false) catch {
                    try ctx.sendErrorResponse(503, 503, "数据库不可用");
                    return;
                };
                defer probe.free(ctx.allocator);
                try ctx.json(200, "{\"code\":0,\"msg\":\"ok\",\"data\":{\"status\":\"READY\"}}");
            }
        }.handle,
    });
    // Prometheus metrics (public, like the health probes).
    const MetricsRoute = struct {
        var metrics_ref: *metrics_mod.Metrics = undefined;
        var allow_ips: []const u8 = "";
    };
    MetricsRoute.metrics_ref = &metrics;
    MetricsRoute.allow_ips = cfg.metrics_allow_ips;
    try server.addRoute(.{
        .method = .GET,
        .path = "metrics",
        .handler = struct {
            fn handle(ctx: *zigmodu.http.Context) !void {
                // /metrics IP 白名单(空 = 允许全部;生产建议限制到监控网段)。
                if (MetricsRoute.allow_ips.len > 0) {
                    const ip = zigmodu.http.RequestUtil.getRealIp(ctx);
                    var allowed = false;
                    var it = std.mem.splitScalar(u8, MetricsRoute.allow_ips, ',');
                    while (it.next()) |a| {
                        if (std.mem.eql(u8, std.mem.trim(u8, a, " \t"), ip)) {
                            allowed = true;
                            break;
                        }
                    }
                    if (!allowed) {
                        try ctx.sendErrorResponse(403, 403, "forbidden");
                        return;
                    }
                }
                const body = try MetricsRoute.metrics_ref.renderPrometheus(ctx.allocator, zigmodu.time.wallClockSeconds(ctx.io orelse return error.InternalError));
                defer ctx.allocator.free(body);
                try ctx.text(200, body);
            }
        }.handle,
    });

    // WeChat Pay v3 payment notify (public — WeChat pushes here).
    const PayNotify = struct {
        var svc: *payment.service.PaymentService = undefined;
        var settings: *setting.persistence.SettingStore = undefined;
    };
    PayNotify.svc = &payment_svc;
    PayNotify.settings = &setting_store;
    try server.addRoute(.{
        .method = .POST,
        .path = "api/pay/v3/notify",
        .handler = struct {
            fn handle(ctx: *zigmodu.http.Context) !void {
                const body = ctx.body orelse "";
                // api_v3_key 从站点设置读取；未配置则拒绝。
                var key_buf: [128]u8 = undefined;
                var api_v3_key: []const u8 = "";
                const key_opt = PayNotify.settings.get(1, "wechat_pay_apiv3_key") catch null;
                if (key_opt) |row| {
                    defer row.free(ctx.allocator);
                    if (row.value.len <= key_buf.len) {
                        @memcpy(key_buf[0..row.value.len], row.value);
                        api_v3_key = key_buf[0..row.value.len];
                    }
                }
                // 平台证书验签：配置了证书则必须验签通过，否则拒绝。
                const cert_opt = PayNotify.settings.get(1, "wechat_pay_platform_cert") catch null;
                if (cert_opt) |cert| {
                    defer cert.free(ctx.allocator);
                    if (cert.value.len > 0) {
                        const sig = ctx.header("Wechatpay-Signature") orelse "";
                        const ts = ctx.header("Wechatpay-Timestamp") orelse "";
                        const nonce = ctx.header("Wechatpay-Nonce") orelse "";
                        const ok = PayNotify.svc.verifyV3NotifySignature(ctx.allocator, cert.value, ts, nonce, sig, body) catch false;
                        if (!ok) {
                            try ctx.json(200, "{\"code\":\"FAIL\",\"message\":\"验签失败\"}");
                            return;
                        }
                    }
                }
                const handled = PayNotify.svc.handleV3Notify(ctx.allocator, api_v3_key, body) catch false;
                if (handled) {
                    try ctx.json(200, "{\"code\":\"SUCCESS\",\"message\":\"成功\"}");
                } else {
                    try ctx.json(200, "{\"code\":\"FAIL\",\"message\":\"处理失败\"}");
                }
            }
        }.handle,
    });

    // WeChat server callback (public, signature-verified inside the service).
    var wx = server.group("/wx");
    try message_api.registerPublicRoutes(&wx);

    // Static hosting: serve the built SPA from web/dist (single binary full stack).
    // A server-level middleware short-circuits routing for non-API GET paths.
    if (cfg.static_dir.len > 0) {
        StaticCtx.dir = cfg.static_dir;
        try server.addMiddleware(staticMiddleware());
        std.log.info("[static] serving SPA from {s}", .{cfg.static_dir});
    }

    std.log.info("zweq listening on http://127.0.0.1:{d} (admin CLI: zig build admin -- --help)", .{cfg.http_port});

    // 优雅关闭:SIGINT/SIGTERM → 停止 accept → 排空在途请求 → 停 modules。
    const sig = std.posix.Sigaction{
        .handler = .{ .handler = onShutdownSignal },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.INT, &sig, null);
    std.posix.sigaction(std.posix.SIG.TERM, &sig, null);

    const ServerThread = struct {
        fn run(s: *zigmodu.http.Server) !void {
            try s.start(); // 阻塞;stop() 后返回(内部 await 在途请求)
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
    std.log.info("server stopped gracefully", .{});
}

/// Parse `ZWEQ_CORS_ORIGINS` ("*" or a comma-separated allow-list) into
/// the `[]const []const u8` slice the CORS middleware expects.
fn parseCorsOrigins(allocator: std.mem.Allocator, spec: []const u8) ![]const []const u8 {
    const trimmed = std.mem.trim(u8, spec, " \t");
    if (std.mem.eql(u8, trimmed, "*") or trimmed.len == 0) {
        return allocator.dupe([]const u8, &.{"*"});
    }
    var out = std.ArrayList([]const u8).empty;
    errdefer out.deinit(allocator);
    var it = std.mem.splitScalar(u8, trimmed, ',');
    while (it.next()) |raw| {
        const origin = std.mem.trim(u8, raw, " \t");
        if (origin.len > 0) try out.append(allocator, origin);
    }
    if (out.items.len == 0) return allocator.dupe([]const u8, &.{"*"});
    return out.toOwnedSlice(allocator);
}

// ── Static hosting (single-binary SPA) ──────────────────────────────────

const StaticCtx = struct {
    var dir: []const u8 = "web/dist";
};

/// Map a file extension to a Content-Type.
fn staticContentType(rel: []const u8) []const u8 {
    const ext = std.fs.path.extension(rel);
    if (std.mem.eql(u8, ext, ".html")) return "text/html; charset=utf-8";
    if (std.mem.eql(u8, ext, ".js")) return "application/javascript; charset=utf-8";
    if (std.mem.eql(u8, ext, ".css")) return "text/css; charset=utf-8";
    if (std.mem.eql(u8, ext, ".json")) return "application/json";
    if (std.mem.eql(u8, ext, ".svg")) return "image/svg+xml";
    if (std.mem.eql(u8, ext, ".png")) return "image/png";
    if (std.mem.eql(u8, ext, ".jpg") or std.mem.eql(u8, ext, ".jpeg")) return "image/jpeg";
    if (std.mem.eql(u8, ext, ".webp")) return "image/webp";
    if (std.mem.eql(u8, ext, ".ico")) return "image/x-icon";
    if (std.mem.eql(u8, ext, ".woff2")) return "font/woff2";
    if (std.mem.eql(u8, ext, ".woff")) return "font/woff";
    if (std.mem.eql(u8, ext, ".ttf")) return "font/ttf";
    if (std.mem.eql(u8, ext, ".map")) return "application/json";
    return "application/octet-stream";
}

/// Serve one file under the static dir as the HTTP response body.
fn serveStaticFile(ctx: *zigmodu.http.Context, io: std.Io, rel: []const u8) !bool {
    const full = try std.fmt.allocPrint(ctx.allocator, "{s}/{s}", .{ StaticCtx.dir, rel });
    defer ctx.allocator.free(full);

    var f = std.Io.Dir.cwd().openFile(io, full, .{}) catch |err| {
        std.log.warn("[static] open {s}: {s}", .{ full, @errorName(err) });
        return false;
    };
    defer f.close(io);

    var body = std.ArrayList(u8).empty;
    defer body.deinit(ctx.allocator);
    var buf: [8192]u8 = undefined;
    while (true) {
        const n = f.readStreaming(io, &.{buf[0..]}) catch |err| {
            // Zig 0.17: EOF surfaces as error.EndOfStream, not n==0.
            if (err == error.EndOfStream) break;
            std.log.warn("[static] read {s}: {s}", .{ full, @errorName(err) });
            return false;
        };
        if (n == 0) break;
        try body.appendSlice(ctx.allocator, buf[0..n]);
        if (body.items.len > 32 * 1024 * 1024) {
            try ctx.sendErrorResponse(413, 413, "File too large");
            return true;
        }
    }
    // Use the proven ctx.text() response path, then override Content-Type.
    try ctx.text(200, body.items);
    try ctx.setHeader("Content-Type", staticContentType(rel));
    return true;
}

/// Server-level middleware: serve the SPA from the static dir and short-circuit
/// routing (no `next`) for non-API paths. API / WeChat / health paths pass
/// through to the router.
fn staticMiddleware() zigmodu.http.Middleware {
    return .{
        .func = struct {
            fn handle(ctx: *zigmodu.http.Context, next: zigmodu.http.HandlerFn, _: ?*anyopaque) anyerror!void {
                if (ctx.method != .GET) return next(ctx);
                const raw = ctx.raw_path;
                if (std.mem.startsWith(u8, raw, "/api") or std.mem.startsWith(u8, raw, "/wx") or
                    std.mem.startsWith(u8, raw, "/health") or std.mem.startsWith(u8, raw, "/metrics"))
                {
                    return next(ctx);
                }
                const io = ctx.io orelse return next(ctx);
                var rel = raw;
                while (rel.len > 0 and rel[0] == '/') rel = rel[1..];
                if (rel.len == 0) rel = "index.html";
                // Path traversal guard.
                if (std.mem.indexOf(u8, rel, "..") != null or std.mem.indexOf(u8, rel, "\\") != null) {
                    try ctx.sendErrorResponse(400, 400, "Bad path");
                    return;
                }
                if (try serveStaticFile(ctx, io, rel)) return;
                // Missing file: assets 404; SPA routes fall back to index.html.
                if (std.mem.startsWith(u8, rel, "static/")) {
                    try ctx.sendErrorResponse(404, 404, "Not Found");
                    return;
                }
                _ = try serveStaticFile(ctx, io, "index.html");
                if (!ctx.responded) return next(ctx);
            }
        }.handle,
    };
}
