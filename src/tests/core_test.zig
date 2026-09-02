//! 平台核心：健康检查、PG 冒烟、AppSecurity、SQLite store 直查、HTTP 全链路注册→登录、限流、admin 门禁、dashboard 计数、缓存与邮件 sink。
// 拆分自原 src/tests.zig（按域分文件，正文逐字保留）。

// 与原 src/tests.zig 相同的顶层命名，测试正文逐字搬运、零改动。
const std = @import("common.zig").std;
const zigmodu = @import("common.zig").zigmodu;
const zent = @import("common.zig").zent;
const zwechat = @import("common.zig").zwechat;
const db_mod = @import("common.zig").db_mod;
const schema = @import("common.zig").schema;
const user = @import("common.zig").user;
const auth = @import("common.zig").auth;
const task = @import("common.zig").task;
const file = @import("common.zig").file;
const notify = @import("common.zig").notify;
const tenant = @import("common.zig").tenant;
const audit = @import("common.zig").audit;
const mail_template = @import("common.zig").mail_template;
const ai = @import("common.zig").ai;
const account = @import("common.zig").account;
const permission = @import("common.zig").permission;
const setting = @import("common.zig").setting;
const rule = @import("common.zig").rule;
const member = @import("common.zig").member;
const message = @import("common.zig").message;
const appmod = @import("common.zig").appmod;
const payment = @import("common.zig").payment;
const cloud = @import("common.zig").cloud;
const material = @import("common.zig").material;
const checkin = @import("common.zig").checkin;
const lucky_draw = @import("common.zig").lucky_draw;
const coupon = @import("common.zig").coupon;
const vote = @import("common.zig").vote;
const seckill = @import("common.zig").seckill;
const member_card = @import("common.zig").member_card;
const distribution = @import("common.zig").distribution;
const shop = @import("common.zig").shop;
const menu = @import("common.zig").menu;
const points = @import("common.zig").points;
const cache_svc = @import("common.zig").cache_svc;
const mail = @import("common.zig").mail;
const mw_rate = @import("common.zig").mw_rate;
const all_infos = @import("common.zig").all_infos;
const openMemory = @import("common.zig").openMemory;
const openPostgres = @import("common.zig").openPostgres;

test "health: zigmodu + zent importable together" {
    _ = zigmodu;
    _ = zent;
    try std.testing.expect(true);
}

test "postgres: real-DB migration + smoke (skip unless ZWEQ_TEST_PG_CONNINFO set)" {
    const allocator = std.testing.allocator;
    // 环境变量读取（Zig 0.17 用 libc getenv；测试链接 libc）。
    const raw = std.c.getenv("ZWEQ_TEST_PG_CONNINFO") orelse return; // 未配置 → 跳过
    const conninfo = std.mem.span(raw);
    if (conninfo.len == 0) return;

    // 首次打开：全量迁移（40+ 表，生产主路径）。
    var env = try openPostgres(allocator, conninfo);
    defer env.deinit();

    // 冒烟 CRUD（module 表 upsert 幂等，可重复跑）。
    var module_store = appmod.persistence.ModuleStore.init(allocator, env.client);
    _ = try module_store.upsertModule(1, "pg_smoke", "PG冒烟", "1.0.0", "active", 100);
    const row = (try module_store.getModuleByName(1, "pg_smoke")).?;
    defer row.free(allocator);
    try std.testing.expectEqualStrings("pg_smoke", row.name);

    // 第二次打开：迁移幂等快速跳过（advisory lock + zent_schema_migrations）。
    var env2 = try openPostgres(allocator, conninfo);
    defer env2.deinit();
}

test "AppSecurity signs and verifies a token" {
    const allocator = std.testing.allocator;
    var sec = zigmodu.security.AppSecurity.init(allocator, std.testing.io, .{ .jwt_secret = "test-secret" });
    const token = try sec.generateToken("7", &.{"admin"});
    defer allocator.free(token);
    const payload = try sec.module.verifyToken(token);
    defer sec.module.freePayload(payload);
    try std.testing.expectEqualStrings("7", payload.sub);
    try std.testing.expect(zigmodu.security.SecurityModule.hasRole(payload, "admin"));
}

test "sqlite store query prepares and runs standalone" {
    const allocator = std.testing.allocator;
    var env = try db_mod.StoreEnv(schema.infos, .{
        user.persistence.infos,
        task.persistence.infos,
        file.persistence.infos,
        notify.persistence.infos,
        audit.persistence.infos,
        mail_template.persistence.infos,
    }).open(allocator, .sqlite, ":memory:");
    defer env.deinit();
    var store = user.persistence.UserStore.init(allocator, env.client);
    const existing = try store.getUserByEmail("nobody@example.com");
    try std.testing.expect(existing == null);
}

test "sqlite store keyword search finds user" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = user.persistence.UserStore.init(allocator, env.client);
    _ = try store.createUser("Alice", "alice@example.com", "hash", false, false, 1, 100);
    _ = try store.createUser("Bob", "bob@example.com", "hash", false, false, 1, 200);

    // Substring search: "alice" matches only alice's row via name or email.
    var result = try store.listUsers(1, 20, "alice", null, null, false);
    defer store.freeList(&result);
    try std.testing.expectEqual(@as(i64, 1), result.total);
    try std.testing.expectEqualStrings("alice@example.com", result.items[0].email);
}

test "cache service set/get/remove" {
    const allocator = std.testing.allocator;
    var cache = cache_svc.CacheService.init(allocator, 16, 60);
    defer cache.deinit();
    try cache.set("user:1", "{\"name\":\"Alice\"}");
    try std.testing.expectEqualStrings("{\"name\":\"Alice\"}", cache.get("user:1").?);
    try std.testing.expect(cache.remove("user:1"));
    try std.testing.expect(cache.get("user:1") == null);
}

test "mailer console sink never fails" {
    const allocator = std.testing.allocator;
    var mailer = mail.Mailer.init(allocator, std.testing.io, "", 587, "", "", "test@localhost", true, true);
    mailer.send(.{ .to = "a@example.com", .subject = "hi", .text = "hello" });
    mailer.send(.{ .to = "b@example.com", .subject = "hi", .text = "hello" });
}

test "HTTP dispatch: public auth flow (register -> me) via Testkit" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = user.persistence.UserStore.init(allocator, env.client);
    var sec = zigmodu.security.AppSecurity.init(allocator, std.testing.io, .{ .jwt_secret = "testkit-secret" });
    var svc = user.service.UserService.init(&store, &sec, std.testing.io, 3600, 86400);
    var auth_registry = zigmodu.RateLimiterRegistry.init(allocator, 100, 1);
    defer auth_registry.deinit();
    var auth_limiter = mw_rate.PerIpLimiter{
        .backend = .{ .registry = &auth_registry },
        .max = 100,
        .window_seconds = 60,
        .refill_rate = 1,
    };
    var mailer = mail.Mailer.init(allocator, std.testing.io, "", 587, "", "", "test@localhost", true, false);
    var task_store = task.persistence.TaskStore.init(allocator, env.client);
    var task_svc = task.service.TaskService.init(&task_store, std.testing.io, 3);
    var notify_store = notify.persistence.NotificationStore.init(allocator, env.client);
    var notify_svc = notify.service.NotificationService.init(allocator, std.testing.io, &notify_store);
    var audit_store = audit.persistence.AuditStore.init(allocator, env.client);
    var audit_svc = audit.service.AuditService.init(allocator, std.testing.io, &audit_store);
    var template_store = mail_template.persistence.TemplateStore.init(allocator, env.client);
    var template_svc = mail_template.service.MailTemplateService.init(allocator, std.testing.io, &template_store);
    var auth_api = auth.api.AuthApi(@TypeOf(svc)).init(&svc, "http://localhost:3001", &auth_limiter, &mailer, &task_svc, &notify_svc, &audit_svc, &template_svc, 1);

    var server = zigmodu.http.Server.init(std.testing.io, allocator, 0);
    defer server.deinit();
    var g = server.group("/api/v1");
    try auth_api.registerRoutes(&g);

    var resp = try zigmodu.http.Testkit.dispatch(&server, .POST, "/api/v1/auth/register", "{\"name\":\"Tester\",\"email\":\"t@example.com\",\"password\":\"password123\"}");
    defer resp.deinit(allocator);
    try std.testing.expectEqual(@as(u16, 201), resp.status_code);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"code\":0") != null);
}

test "rate limit: per-IP isolation via realIp + perIpRateLimit" {
    const allocator = std.testing.allocator;
    const real_ip = @import("../middleware/real_ip.zig");
    var registry = zigmodu.RateLimiterRegistry.init(allocator, 2, 1);
    defer registry.deinit();
    var limiter = mw_rate.PerIpLimiter{
        .backend = .{ .registry = &registry },
        .max = 2,
        .window_seconds = 60,
        .refill_rate = 1,
    };

    const Probe = struct {
        fn h(ctx: *zigmodu.http.Context) !void {
            try ctx.json(200, "{\"code\":0}");
        }
    };

    var server = zigmodu.http.Server.init(std.testing.io, allocator, 0);
    defer server.deinit();
    try server.addMiddleware(real_ip.realIp());
    var g = server.group("/api/v1");
    var limited = try g.use(mw_rate.perIpRateLimit(&limiter));
    try limited.get("/probe", Probe.h, null);

    // IP A：前 2 次通过，第 3 次触发 429。
    var r1 = try zigmodu.http.Testkit.dispatchOpts(&server, .GET, "/api/v1/probe", .{ .headers = &.{.{ "X-Real-IP", "1.1.1.1" }} });
    defer r1.deinit(allocator);
    var r2 = try zigmodu.http.Testkit.dispatchOpts(&server, .GET, "/api/v1/probe", .{ .headers = &.{.{ "X-Real-IP", "1.1.1.1" }} });
    defer r2.deinit(allocator);
    var r3 = try zigmodu.http.Testkit.dispatchOpts(&server, .GET, "/api/v1/probe", .{ .headers = &.{.{ "X-Real-IP", "1.1.1.1" }} });
    defer r3.deinit(allocator);
    try std.testing.expectEqual(@as(u16, 200), r1.status_code);
    try std.testing.expectEqual(@as(u16, 200), r2.status_code);
    try std.testing.expectEqual(@as(u16, 429), r3.status_code);

    // IP B：不受 IP A 限流影响。
    var rb = try zigmodu.http.Testkit.dispatchOpts(&server, .GET, "/api/v1/probe", .{ .headers = &.{.{ "X-Real-IP", "2.2.2.2" }} });
    defer rb.deinit(allocator);
    try std.testing.expectEqual(@as(u16, 200), rb.status_code);
}

test "dashboard counts: countAll + registration trend buckets" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = user.persistence.UserStore.init(allocator, env.client);
    var file_store = file.persistence.FileStore.init(allocator, env.client);
    var notify_store = notify.persistence.NotificationStore.init(allocator, env.client);
    var tenant_store = tenant.persistence.TenantStore.init(allocator, env.client);

    _ = try store.createUser("A", "a@x.com", "h", false, false, 1, 100);
    _ = try store.createUser("B", "b@x.com", "h", false, false, 1, 150);
    try std.testing.expectEqual(@as(i64, 2), try store.countAll());
    try std.testing.expectEqual(@as(i64, 2), try store.countRegisteredBetween(0, 200));
    try std.testing.expectEqual(@as(i64, 1), try store.countRegisteredBetween(120, 160)); // 桶边界 [start, end)
    try std.testing.expectEqual(@as(i64, 0), try store.countRegisteredBetween(200, 300));

    _ = try file_store.create("a.txt", "k", "text/plain", 3, 1, 1, 0, 100);
    _ = try notify_store.create(1, "t", "b", "info", 100);
    try std.testing.expectEqual(@as(i64, 1), try file_store.countAll());
    try std.testing.expectEqual(@as(i64, 1), try notify_store.countAll());
    try std.testing.expectEqual(@as(i64, 0), try tenant_store.countAll());
    _ = try tenant_store.create("Acme", "active", 100);
    try std.testing.expectEqual(@as(i64, 1), try tenant_store.countAll());
}

test "admin-only endpoints reject missing/non-admin tokens" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = user.persistence.UserStore.init(allocator, env.client);
    var sec = zigmodu.security.AppSecurity.init(allocator, std.testing.io, .{ .jwt_secret = "testkit-secret" });
    var svc = user.service.UserService.init(&store, &sec, std.testing.io, 3600, 86400);

    var audit_store = audit.persistence.AuditStore.init(allocator, env.client);
    var audit_svc = audit.service.AuditService.init(allocator, std.testing.io, &audit_store);
    var tstore = mail_template.persistence.TemplateStore.init(allocator, env.client);
    var tsvc = mail_template.service.MailTemplateService.init(allocator, std.testing.io, &tstore);

    const plain_uid = try store.createUser("Alice", "alice@example.com", "hash", false, false, 1, 100);
    const admin_uid = try store.createUser("Boss", "boss@example.com", "hash", false, true, 1, 100);

    var uid_buf: [32]u8 = undefined;
    const plain_token = try sec.module.generateTokenWithTenant(try std.fmt.bufPrint(&uid_buf, "{d}", .{plain_uid}), &.{}, "1");
    defer allocator.free(plain_token);
    const admin_token = try sec.module.generateTokenWithTenant(try std.fmt.bufPrint(&uid_buf, "{d}", .{admin_uid}), &.{"admin"}, "1");
    defer allocator.free(admin_token);

    var server = zigmodu.http.Server.init(std.testing.io, allocator, 0);
    defer server.deinit();
    var g = server.group("/api/v1");
    var audit_api = audit.api.AuditApi(@TypeOf(audit_svc), @TypeOf(svc)).init(&audit_svc, &svc);
    try audit_api.registerRoutes(&g);
    var mt_api = mail_template.api.MailTemplateApi(@TypeOf(tsvc), @TypeOf(svc)).init(&tsvc, &svc);
    try mt_api.registerRoutes(&g);

    // 无 token → 401。
    var anon = try zigmodu.http.Testkit.dispatch(&server, .GET, "/api/v1/audit-logs", null);
    defer anon.deinit(allocator);
    try std.testing.expectEqual(@as(u16, 401), anon.status_code);

    // 普通用户 token → 403(后端再次校验 admin,而非仅依赖前端隐藏)。
    var hdr: [512]u8 = undefined;
    var denied = try zigmodu.http.Testkit.dispatchOpts(&server, .GET, "/api/v1/audit-logs", .{
        .headers = &.{.{ "authorization", try std.fmt.bufPrint(&hdr, "Bearer {s}", .{plain_token}) }},
    });
    defer denied.deinit(allocator);
    try std.testing.expectEqual(@as(u16, 403), denied.status_code);

    // admin token → 200。
    var allowed = try zigmodu.http.Testkit.dispatchOpts(&server, .GET, "/api/v1/audit-logs", .{
        .headers = &.{.{ "authorization", try std.fmt.bufPrint(&hdr, "Bearer {s}", .{admin_token}) }},
    });
    defer allowed.deinit(allocator);
    try std.testing.expectEqual(@as(u16, 200), allowed.status_code);

    // 模板 PUT 无 token → 401。
    var anon_put = try zigmodu.http.Testkit.dispatch(&server, .PUT, "/api/v1/email-templates/verify_email", null);
    defer anon_put.deinit(allocator);
    try std.testing.expectEqual(@as(u16, 401), anon_put.status_code);
}
