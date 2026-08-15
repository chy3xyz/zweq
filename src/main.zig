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
const zwechat = @import("zwechat");
const config_mod = @import("config.zig");
const db_mod = @import("db.zig");
const schema = @import("schema.zig");
const access_log_mod = @import("middleware/access_log.zig");
const sec_headers = @import("middleware/security_headers.zig");
const metrics_mod = @import("middleware/metrics.zig");
const real_ip_mod = @import("middleware/real_ip.zig");
const request_log_mod = @import("middleware/request_log.zig");
const license_mw = @import("middleware/license.zig");
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
const checkin = @import("modules/checkin/root.zig");
const lucky_draw = @import("modules/lucky_draw/root.zig");
const coupon = @import("modules/coupon/root.zig");
const vote = @import("modules/vote/root.zig");
const seckill = @import("modules/seckill/root.zig");
const member_card = @import("modules/member_card/root.zig");
const distribution = @import("modules/distribution/root.zig");
const shop = @import("modules/shop/root.zig");
const menu = @import("modules/menu/root.zig");
const points = @import("modules/points/root.zig");

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
        checkin.persistence.infos,
        lucky_draw.persistence.infos,
        coupon.persistence.infos,
        vote.persistence.infos,
        seckill.persistence.infos,
        member_card.persistence.infos,
        distribution.persistence.infos,
        shop.persistence.infos,
        menu.persistence.infos,
        points.persistence.infos,
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
    var tag_store = member.persistence.TagStore.init(allocator, store_env.client);
    member_svc.tag_store = &tag_store;
    member_svc.account_svc = &account_svc;
    var message_store = message.persistence.MessageStore.init(allocator, store_env.client);
    var wechat_svc = message.service.WechatService.init(allocator, io, &account_svc, &rule_svc, &member_svc, &setting_store, &message_store);
    var app_module_store = appmod.persistence.ModuleStore.init(allocator, store_env.client);
    var module_svc = appmod.service.ModuleService.init(allocator, io, &app_module_store);
    try module_svc.seedBuiltins(default_tenant_id);
    std.log.info("[module] built-in modules seeded", .{});
    // Wire the module registry into the callback engine so bound modules'
    // receivers can be dispatched.
    wechat_svc.module_svc = &module_svc;
    // Wire the cache into the callback engine for nonce replay detection.
    wechat_svc.cache = &cache;
    var payment_store = payment.persistence.PaymentStore.init(allocator, store_env.client);
    var payment_svc = payment.service.PaymentService.init(allocator, io, &payment_store);
    var cloud_store = cloud.persistence.CloudStore.init(allocator, store_env.client);
    var cloud_svc = cloud.service.CloudService.init(allocator, io, &cloud_store, &module_svc, cfg.cloud_remote_url);
    // 注入原始 SQL 执行器（市场包 manifest 迁移 SQL 用）。
    cloud_svc.setDriver(if (kind == .postgres) store_env.pg.?.asDriver() else store_env.sqlite.?.asDriver());
    // 动态表元数据存储（manifest tables 注册 + 通用查询网关）。
    var dyn_table_store = cloud.persistence.DynamicTableStore.init(allocator, store_env.client);
    cloud_svc.setDynamicTableStore(&dyn_table_store);
    // 站点授权码注入 + 启动即校验（远端模式 fail-closed + 宽限期）。
    if (setting_svc.get(default_tenant_id, "cloud_license_key") catch null) |row| {
        defer row.free(allocator);
        try cloud_svc.setSiteLicenseKey(row.value);
    }
    if (setting_svc.get(default_tenant_id, "cloud_license_grace_days") catch null) |grow| {
        defer grow.free(allocator);
        cloud_svc.setGraceDays(std.fmt.parseInt(i64, grow.value, 10) catch 7);
    }
    cloud_svc.checkSiteLicense();
    std.log.info("[cloud] license check: licensed={} (remote={s})", .{ cloud_svc.isLicensed(), cfg.cloud_remote_url });
    // Shared access_token cache（主动微信能力的地基：菜单 + 素材同步共用）.
    var token_cache = try zwechat.cache.Memory.create(allocator);
    defer allocator.destroy(token_cache);
    defer token_cache.deinit();
    wechat_svc.token_cache = token_cache;
    member_svc.token_cache = token_cache;
    var material_store = material.persistence.MaterialStore.init(allocator, store_env.client);
    var material_svc = material.service.MaterialService.init(allocator, io, &material_store, &account_svc, token_cache);
    var checkin_store = checkin.persistence.CheckinStore.init(allocator, store_env.client);
    var checkin_svc = checkin.service.CheckinService.init(allocator, io, &checkin_store);
    var checkin_ctx = checkin.service.ReceiverCtx{
        .module_svc = &module_svc,
        .checkin_svc = &checkin_svc,
        .io = io,
    };
    try wechat_svc.registerReceiver(.{
        .module_name = "checkin",
        .ctx = &checkin_ctx,
        .handle = checkin.service.receiverHandle,
    });
    var lucky_draw_store = lucky_draw.persistence.DrawStore.init(allocator, store_env.client);
    var lucky_draw_svc = lucky_draw.service.DrawService.init(allocator, io, &lucky_draw_store);
    var lucky_draw_ctx = lucky_draw.service.ReceiverCtx{
        .module_svc = &module_svc,
        .draw_svc = &lucky_draw_svc,
        .io = io,
    };
    try wechat_svc.registerReceiver(.{
        .module_name = "lucky_draw",
        .ctx = &lucky_draw_ctx,
        .handle = lucky_draw.service.receiverHandle,
    });
    var coupon_store = coupon.persistence.CouponStore.init(allocator, store_env.client);
    var coupon_svc = coupon.service.CouponService.init(allocator, io, &coupon_store);
    var coupon_ctx = coupon.service.ReceiverCtx{
        .module_svc = &module_svc,
        .coupon_svc = &coupon_svc,
        .io = io,
    };
    try wechat_svc.registerReceiver(.{
        .module_name = "coupon",
        .ctx = &coupon_ctx,
        .handle = coupon.service.receiverHandle,
    });
    var vote_store = vote.persistence.VoteStore.init(allocator, store_env.client);
    var vote_svc = vote.service.VoteService.init(allocator, io, &vote_store);
    var vote_ctx = vote.service.ReceiverCtx{
        .module_svc = &module_svc,
        .vote_svc = &vote_svc,
        .io = io,
    };
    try wechat_svc.registerReceiver(.{
        .module_name = "vote",
        .ctx = &vote_ctx,
        .handle = vote.service.receiverHandle,
    });
    var seckill_store = seckill.persistence.SeckillStore.init(allocator, store_env.client);
    var seckill_svc = seckill.service.SeckillService.init(allocator, io, &seckill_store);
    var seckill_ctx = seckill.service.ReceiverCtx{
        .io = io,
        .seckill_svc = &seckill_svc,
    };
    try wechat_svc.registerReceiver(.{
        .module_name = "seckill",
        .ctx = &seckill_ctx,
        .handle = seckill.service.receiverHandle,
    });
    var member_card_store = member_card.persistence.MemberCardStore.init(allocator, store_env.client);
    var member_card_svc = member_card.service.MemberCardService.init(allocator, io, &member_card_store);
    var member_card_ctx = member_card.service.ReceiverCtx{
        .io = io,
        .member_svc = &member_card_svc,
    };
    try wechat_svc.registerReceiver(.{
        .module_name = "member_card",
        .ctx = &member_card_ctx,
        .handle = member_card.service.receiverHandle,
    });
    var distribution_store = distribution.persistence.DistributionStore.init(allocator, store_env.client);
    var distribution_svc = distribution.service.DistributionService.init(allocator, io, &distribution_store);
    var distribution_ctx = distribution.service.ReceiverCtx{
        .io = io,
        .dist_svc = &distribution_svc,
    };
    try wechat_svc.registerReceiver(.{
        .module_name = "distribution",
        .ctx = &distribution_ctx,
        .handle = distribution.service.receiverHandle,
    });
    var menu_store = menu.persistence.MenuStore.init(allocator, store_env.client);
    var menu_svc = menu.service.MenuService.init(allocator, io, &menu_store, &account_svc, token_cache);
    var points_store = points.persistence.PointsStore.init(allocator, store_env.client);
    var points_svc = points.service.PointsService.init(allocator, io, &points_store, &fan_store);

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
        checkin.module,
        lucky_draw.module,
        coupon.module,
        vote.module,
        seckill.module,
        member_card.module,
        distribution.module,
        shop.module,
        menu.module,
        points.module,
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
    var auth_registry = zigmodu.RateLimiterRegistry.init(allocator, 20, 1);
    defer auth_registry.deinit();
    // WeChat callback flood guard (global token bucket — WeChat pushes from a
    // shared server pool, so per-IP limiting would misfire on bursts).
    var wx_limiter = try zigmodu.RateLimiter.init(allocator, "wx-callback", 1000, 20);
    defer wx_limiter.deinit();

    var user_api = user.api.UserApi(@TypeOf(user_svc)).init(&user_svc, default_tenant_id, &audit_svc);
    var auth_api = auth.api.AuthApi(@TypeOf(user_svc)).init(&user_svc, cfg.app_host, &auth_registry, &mailer, &task_svc, &notify_svc, &audit_svc, &template_svc, default_tenant_id);
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
    var checkin_api = checkin.api.CheckinApi(@TypeOf(checkin_svc), @TypeOf(user_svc)).init(&checkin_svc, &user_svc, &audit_svc, default_tenant_id);
    var lucky_draw_api = lucky_draw.api.LuckyDrawApi(@TypeOf(lucky_draw_svc), @TypeOf(user_svc)).init(&lucky_draw_svc, &user_svc, &audit_svc, default_tenant_id);
    var coupon_api = coupon.api.CouponApi(@TypeOf(coupon_svc), @TypeOf(user_svc)).init(&coupon_svc, &user_svc, &audit_svc, default_tenant_id);
    var vote_api = vote.api.VoteApi(@TypeOf(vote_svc), @TypeOf(user_svc)).init(&vote_svc, &user_svc, &audit_svc, default_tenant_id);
    var seckill_api = seckill.api.SeckillApi(@TypeOf(seckill_svc), @TypeOf(user_svc)).init(&seckill_svc, &user_svc, &audit_svc, default_tenant_id);
    var member_card_api = member_card.api.MemberCardApi(@TypeOf(member_card_svc), @TypeOf(user_svc)).init(&member_card_svc, &user_svc, &audit_svc, default_tenant_id);
    var distribution_api = distribution.api.DistributionApi(@TypeOf(distribution_svc), @TypeOf(user_svc)).init(&distribution_svc, &user_svc, &audit_svc, default_tenant_id);
    var shop_store = shop.persistence.ShopStore.init(allocator, store_env.client);
    var shop_svc = shop.service.ShopService.init(allocator, io, &shop_store);
    shop_svc.dist_svc = &distribution_svc; // 订单支付 → 分销三级分佣
    shop_svc.coupon_store = &coupon_store; // 下单优惠券校验/核销
    shop_svc.member_svc = &member_card_svc; // 支付 → 会员积分累计
    shop_svc.coupon_svc = &coupon_svc; // 邀请达标发券
    shop_svc.payment_svc = &payment_svc; // 余额支付扣钱包
    shop_svc.fan_store = &fan_store; // openid → fan_id
    // 事件驱动：订单支付 → 分销分佣 + 会员积分（解耦消费，替代同步钩子）。
    {
        const OrderPaidBus = shop.service.OrderPaidBus;
        var order_paid_bus = OrderPaidBus.init(allocator);
        const OrderPaidCtx = struct {
            var shop_ref: *shop.service.ShopService = undefined;
            var webhook_transport: @import("http/webhook_transport.zig").WebhookTransport = undefined;
            fn onPaid(e: shop.service.OrderPaidEvent) void {
                const s = shop_ref;
                const o_opt = s.getOrder(e.order_id) catch return;
                const o = o_opt orelse return;
                defer o.free(s.allocator);
                // 分销三级分佣。
                if (s.dist_svc) |ds| {
                    const dist_mod = @import("modules/distribution/service.zig");
                    const dsvc: *dist_mod.DistributionService = @ptrCast(@alignCast(ds));
                    _ = dsvc.distribute(e.tenant_id, e.account_id, o.openid, o.pay_amount) catch {};
                }
                // 会员积分累计（1 元 = 1 积分）。
                if (s.member_svc) |ms| {
                    const mc_mod = @import("modules/member_card/service.zig");
                    const msvc: *mc_mod.MemberCardService = @ptrCast(@alignCast(ms));
                    _ = msvc.adjust(e.tenant_id, e.account_id, o.openid, @divTrunc(o.pay_amount, 100)) catch {};
                }
                // Webhook 推送（事件开放出口）。
                s.webhook_transport = &webhook_transport;
                s.dispatchWebhooks("order.paid", e.tenant_id, e.account_id, e.order_id);
            }
        };
        OrderPaidCtx.shop_ref = &shop_svc;
        OrderPaidCtx.webhook_transport = @import("http/webhook_transport.zig").WebhookTransport.init(io);
        order_paid_bus.subscribe(OrderPaidCtx.onPaid) catch {};
        shop_svc.order_paid_bus = &order_paid_bus;
        // 生命周期：bus 随主循环存活（栈变量，作用域到 main 结束）——需提升到函数级。
        // 此处用堆分配避免悬挂。
        const heap_bus = allocator.create(OrderPaidBus) catch unreachable;
        heap_bus.* = order_paid_bus;
        shop_svc.order_paid_bus = heap_bus;
    }
    var shop_limiter = zigmodu.RateLimiterRegistry.init(allocator, 30, 1);
    var shop_api = shop.api.ShopApi(@TypeOf(shop_svc), @TypeOf(user_svc)).init(&shop_svc, &user_svc, &audit_svc, default_tenant_id, &shop_limiter, &fan_store, &setting_store);
    var menu_api = menu.api.MenuApi(@TypeOf(menu_svc), @TypeOf(user_svc)).init(&menu_svc, &user_svc, &audit_svc, default_tenant_id);
    var points_api = points.api.PointsApi(@TypeOf(points_svc), @TypeOf(user_svc)).init(&points_svc, &user_svc, &audit_svc, default_tenant_id);
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
    try server.addMiddleware(real_ip_mod.realIp());
    try server.addMiddleware(request_log_mod.requestLog());
    try server.addMiddleware(metrics.middleware());
    try server.addMiddleware(sec_headers.securityHeaders());
    try server.addMiddleware(access_log.middleware());
    try server.addMiddleware(zigmodu.http.http_middleware.cors(.{ .allow_origins = origins }));
    try server.addMiddleware(license_mw.licenseGate(&cloud_svc));

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
    try checkin_api.registerRoutes(&v1);
    try lucky_draw_api.registerRoutes(&v1);
    try coupon_api.registerRoutes(&v1);
    try vote_api.registerRoutes(&v1);
    try seckill_api.registerRoutes(&v1);
    try member_card_api.registerRoutes(&v1);
    try distribution_api.registerRoutes(&v1);
    try shop_api.registerPublicRoutes(&v1);
    try shop_api.registerAdminRoutes(&v1);
    try menu_api.registerRoutes(&v1);
    try points_api.registerRoutes(&v1);
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
    var wx_limited = try wx.use(zigmodu.http.rateLimitMiddleware(&wx_limiter));
    try message_api.registerPublicRoutes(&wx_limited);

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
    var last_license_check = zigmodu.time.wallClockSeconds(io);
    while (!ShutdownFlag.requested.load(.acquire)) {
        _ = std.c.nanosleep(&poll, null);
        // 远端模式下每 24h 重新校验站点授权码（fail-closed）。
        if (cfg.cloud_remote_url.len > 0) {
            const now = zigmodu.time.wallClockSeconds(io);
            if (now - last_license_check >= 24 * 3600) {
                cloud_svc.checkSiteLicense();
                last_license_check = now;
                std.log.info("[cloud] periodic license check: licensed={}", .{cloud_svc.isLicensed()});
            }
        }
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
