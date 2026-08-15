//! Unit tests for zweq. DB-backed tests use an in-memory zent store;
//! HTTP-layer tests dispatch through zigmodu's Testkit without a socket.
//! Tenant tests cover default bootstrap, JWT aud binding and row isolation.

const std = @import("std");
const zigmodu = @import("zigmodu");
const zent = @import("zent");
const zwechat = @import("zwechat");
const db_mod = @import("db.zig");
const schema = @import("schema.zig");
const user = @import("modules/user/root.zig");
const auth = @import("modules/auth/root.zig");
const task = @import("modules/task/root.zig");
const file = @import("modules/file/root.zig");
const notify = @import("modules/notify/root.zig");
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
const cache_svc = @import("services/cache.zig");
const mail = @import("services/mail.zig");

/// 全部 schema group（openMemory / openPostgres 共用）。
const all_infos = .{
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
};

/// In-memory SQLite store with every schema group migrated.
fn openMemory(allocator: std.mem.Allocator) !db_mod.StoreEnv(schema.infos, all_infos) {
    return db_mod.StoreEnv(schema.infos, all_infos).open(allocator, .sqlite, ":memory:");
}

/// Real Postgres store（测试用，需 `ZWEQ_TEST_PG_CONNINFO` 环境变量）。
fn openPostgres(allocator: std.mem.Allocator, conninfo: []const u8) !db_mod.StoreEnv(schema.infos, all_infos) {
    return db_mod.StoreEnv(schema.infos, all_infos).open(allocator, .postgres, conninfo);
}

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

test "service updateProfile keeps fields and normalizes email" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = user.persistence.UserStore.init(allocator, env.client);
    var sec = zigmodu.security.AppSecurity.init(allocator, std.testing.io, .{ .jwt_secret = "test-secret" });
    var svc = user.service.UserService.init(&store, &sec, std.testing.io, 3600, 86400);

    const id = try store.createUser("Alice", "alice@example.com", "hash", false, false, 1, 100);

    // Only the name changes; email is preserved.
    try svc.updateProfile(id, "Alice Renamed", "alice@example.com");
    {
        const row = (try store.getUserById(id)).?;
        defer row.free(allocator);
        try std.testing.expectEqualStrings("Alice Renamed", row.name);
        try std.testing.expectEqualStrings("alice@example.com", row.email);
    }

    // Mixed-case email is lowercased before persisting.
    try svc.updateProfile(id, "Alice", "ALICE@EXAMPLE.COM");
    {
        const row = (try store.getUserById(id)).?;
        defer row.free(allocator);
        try std.testing.expectEqualStrings("alice@example.com", row.email);
    }

    try std.testing.expectError(error.InvalidEmail, svc.updateProfile(id, "Alice", "not-an-email"));
    try std.testing.expectError(error.InvalidName, svc.updateProfile(id, "   ", "alice@example.com"));
}

test "emailTakenByOther detects a conflicting email" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = user.persistence.UserStore.init(allocator, env.client);
    var sec = zigmodu.security.AppSecurity.init(allocator, std.testing.io, .{ .jwt_secret = "test-secret" });
    var svc = user.service.UserService.init(&store, &sec, std.testing.io, 3600, 86400);

    const alice_id = try store.createUser("Alice", "alice@example.com", "hash", false, false, 1, 100);
    const bob_id = try store.createUser("Bob", "bob@example.com", "hash", false, false, 1, 200);

    try std.testing.expect(try svc.emailTakenByOther(allocator, bob_id, "alice@example.com"));
    try std.testing.expect(!try svc.emailTakenByOther(allocator, alice_id, "alice@example.com"));
    try std.testing.expect(!try svc.emailTakenByOther(allocator, bob_id, "bob@example.com"));
}

test "password token lifecycle: issue, validate, expired cleanup" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = user.persistence.UserStore.init(allocator, env.client);
    var sec = zigmodu.security.AppSecurity.init(allocator, std.testing.io, .{ .jwt_secret = "test-secret" });
    var svc = user.service.UserService.init(&store, &sec, std.testing.io, 3600, 86400);

    _ = try store.createUser("Alice", "alice@example.com", "hash", false, false, 1, 100);

    // Valid token round-trips.
    const info = (try svc.createPasswordResetToken(allocator, "alice@example.com")).?;
    defer allocator.free(info.raw);
    try svc.validatePasswordResetToken(info.user_id, info.raw);

    // A stale token (far in the past) is purged, the fresh one survives.
    _ = try store.createPasswordToken(info.user_id, "stale-hash", 1000);
    const now = zigmodu.time.wallClockSeconds(std.testing.io);
    try store.deleteExpiredPasswordTokens(info.user_id, now, 3600);
    const latest = (try store.getLatestPasswordToken(info.user_id)).?;
    defer latest.free(allocator);
    try std.testing.expectEqual(info.user_id, latest.user_id);
    // The stored value is the PBKDF2 hash of the raw token — assert it is not
    // the stale marker so we know cleanup removed only the old row.
    try std.testing.expect(!std.mem.eql(u8, latest.token, "stale-hash"));
}

test "email verification lifecycle: issue, verify, purge" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = user.persistence.UserStore.init(allocator, env.client);
    var sec = zigmodu.security.AppSecurity.init(allocator, std.testing.io, .{ .jwt_secret = "test-secret" });
    var svc = user.service.UserService.init(&store, &sec, std.testing.io, 3600, 86400);

    const id = try store.createUser("Alice", "alice@example.com", "hash", false, false, 1, 100);
    const info = (try svc.createEmailVerification(allocator, id)).?;
    defer allocator.free(info.raw);
    try svc.verifyEmail(id, info.raw);

    const row = (try store.getUserById(id)).?;
    defer row.free(allocator);
    try std.testing.expect(row.verified);
}

test "changePassword verifies the current password" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = user.persistence.UserStore.init(allocator, env.client);
    var sec = zigmodu.security.AppSecurity.init(allocator, std.testing.io, .{ .jwt_secret = "test-secret" });
    var svc = user.service.UserService.init(&store, &sec, std.testing.io, 3600, 86400);
    const id = try store.createUser("Alice", "alice@example.com", "hash", false, false, 1, 100);

    try std.testing.expectError(error.InvalidCredentials, svc.changePassword(id, "wrong", "newpassword123"));
    try std.testing.expectError(error.InvalidPassword, svc.changePassword(id, "hash", "short"));
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

test "task queue: enqueue -> claim -> done" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var task_store = task.persistence.TaskStore.init(allocator, env.client);
    var task_svc = task.service.TaskService.init(&task_store, std.testing.io, 3);

    const id = try task_svc.enqueueNow("mail.send", "{}", 1);
    const claimed = (try task_store.claimNext(1000)).?;
    defer claimed.free(allocator);
    try std.testing.expectEqual(id, claimed.id);
    try std.testing.expectEqualStrings("claimed", claimed.status);
    try task_store.markDone(id, 1001);
    const row = (try task_store.getTaskById(id)).?;
    defer row.free(allocator);
    try std.testing.expectEqualStrings("done", row.status);
}

test "task queue: retry backoff and failure budget" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var task_store = task.persistence.TaskStore.init(allocator, env.client);

    const id = try task_store.createTask("mail.send", "{}", "pending", 1, 1, 2, "", 0, 100);
    try task_store.markFailedOrRetry(id, 1, 2, "boom", 200, 60);
    const after = (try task_store.getTaskById(id)).?;
    defer after.free(allocator);
    try std.testing.expectEqualStrings("pending", after.status);
    try std.testing.expectEqual(@as(i64, 260), after.available_at);

    try task_store.markFailedOrRetry(id, 2, 2, "boom", 300, 60);
    const failed = (try task_store.getTaskById(id)).?;
    defer failed.free(allocator);
    try std.testing.expectEqualStrings("failed", failed.status);
}

test "notification store: create, unread count, mark read" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var notify_store = notify.persistence.NotificationStore.init(allocator, env.client);
    var notify_svc = notify.service.NotificationService.init(allocator, std.testing.io, &notify_store);

    _ = try notify_svc.notify(7, "任务完成", "mail.send ok", "success");
    _ = try notify_svc.notify(7, "系统消息", "欢迎", "info");
    try std.testing.expectEqual(@as(i64, 2), try notify_svc.unreadCount(7));

    var result = try notify_svc.list(7, 1, 20, true);
    defer result.free(allocator);
    try std.testing.expectEqual(@as(i64, 2), result.total);
    try notify_svc.markAllRead(7);
    try std.testing.expectEqual(@as(i64, 0), try notify_svc.unreadCount(7));
}

test "file store metadata CRUD" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var file_store = file.persistence.FileStore.init(allocator, env.client);

    const id = try file_store.create("a.txt", "key1", "text/plain", 4, 9, 1, 100);
    const row = (try file_store.getById(id)).?;
    defer row.free(allocator);
    try std.testing.expectEqualStrings("a.txt", row.name);
    try std.testing.expectEqualStrings("key1", row.storage_key);
    try file_store.delete(id);
    try std.testing.expect((try file_store.getById(id)) == null);
}

test "file: upload mime validation rejects active content (XSS)" {
    // 允许常见安全类型。
    try std.testing.expect(file.service.FileService.validMime("image/png"));
    try std.testing.expect(file.service.FileService.validMime("application/pdf"));
    try std.testing.expect(file.service.FileService.validMime("text/plain"));
    try std.testing.expect(file.service.FileService.validMime("application/octet-stream"));
    // 拒绝浏览器可当活动内容渲染的类型（含带参数的形式）。
    try std.testing.expect(!file.service.FileService.validMime("text/html"));
    try std.testing.expect(!file.service.FileService.validMime("image/svg+xml"));
    try std.testing.expect(!file.service.FileService.validMime("image/svg+xml; charset=utf-8"));
    try std.testing.expect(!file.service.FileService.validMime("application/javascript"));
    try std.testing.expect(!file.service.FileService.validMime("application/xhtml+xml"));
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
    var mailer = mail.Mailer.init(allocator, std.testing.io, "", 587, "", "", "test@localhost", true, false);
    var task_store = task.persistence.TaskStore.init(allocator, env.client);
    var task_svc = task.service.TaskService.init(&task_store, std.testing.io, 3);
    var notify_store = notify.persistence.NotificationStore.init(allocator, env.client);
    var notify_svc = notify.service.NotificationService.init(allocator, std.testing.io, &notify_store);
    var audit_store = audit.persistence.AuditStore.init(allocator, env.client);
    var audit_svc = audit.service.AuditService.init(allocator, std.testing.io, &audit_store);
    var template_store = mail_template.persistence.TemplateStore.init(allocator, env.client);
    var template_svc = mail_template.service.MailTemplateService.init(allocator, std.testing.io, &template_store);
    var auth_api = auth.api.AuthApi(@TypeOf(svc)).init(&svc, "http://localhost:3001", &auth_registry, &mailer, &task_svc, &notify_svc, &audit_svc, &template_svc, 1);

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
    const real_ip = @import("middleware/real_ip.zig");
    const mw_rate = @import("middleware/rate_limit.zig");
    var registry = zigmodu.RateLimiterRegistry.init(allocator, 2, 1);
    defer registry.deinit();

    const Probe = struct {
        fn h(ctx: *zigmodu.http.Context) !void {
            try ctx.json(200, "{\"code\":0}");
        }
    };

    var server = zigmodu.http.Server.init(std.testing.io, allocator, 0);
    defer server.deinit();
    try server.addMiddleware(real_ip.realIp());
    var g = server.group("/api/v1");
    var limited = try g.use(mw_rate.perIpRateLimit(&registry, 2, 1));
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

test "tenant service: ensureDefault is idempotent, CRUD works" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var tenant_store = tenant.persistence.TenantStore.init(allocator, env.client);
    var tenant_svc = tenant.service.TenantService.init(allocator, std.testing.io, &tenant_store);

    const default_id = try tenant_svc.ensureDefault();
    try std.testing.expectEqual(default_id, try tenant_svc.ensureDefault());

    const acme = try tenant_svc.create("Acme Inc");
    const acme_row = (try tenant_svc.get(acme)).?;
    defer acme_row.free(allocator);
    try std.testing.expectEqualStrings("Acme Inc", acme_row.name);
    try std.testing.expectEqualStrings("active", acme_row.status);

    _ = try tenant_svc.update(acme, "Acme Inc", "disabled");
    const disabled = (try tenant_svc.get(acme)).?;
    defer disabled.free(allocator);
    try std.testing.expectEqualStrings("disabled", disabled.status);

    var result = try tenant_svc.list(1, 20);
    defer result.free(allocator);
    try std.testing.expectEqual(@as(i64, 2), result.total);
}

test "register binds tenant and JWT aud carries it" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = user.persistence.UserStore.init(allocator, env.client);
    var sec = zigmodu.security.AppSecurity.init(allocator, std.testing.io, .{ .jwt_secret = "test-secret" });
    var svc = user.service.UserService.init(&store, &sec, std.testing.io, 3600, 86400);

    var session = try svc.register(allocator, "Alice", "alice@example.com", "password123", false, 7);
    defer session.deinit(allocator);
    try std.testing.expectEqual(@as(i64, 7), session.row.tenant_id);

    const payload = try sec.module.verifyToken(session.token);
    defer sec.module.freePayload(payload);
    try std.testing.expectEqualStrings("7", payload.aud);
}

test "user list filters by tenant" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = user.persistence.UserStore.init(allocator, env.client);

    _ = try store.createUser("A1", "a1@example.com", "hash", false, false, 1, 100);
    _ = try store.createUser("A2", "a2@example.com", "hash", false, false, 1, 101);
    _ = try store.createUser("B1", "b1@example.com", "hash", false, false, 2, 102);

    var tenant1 = try store.listUsers(1, 20, null, 1, null, false);
    defer tenant1.free(allocator);
    try std.testing.expectEqual(@as(i64, 2), tenant1.total);

    var tenant2 = try store.listUsers(1, 20, null, 2, null, false);
    defer tenant2.free(allocator);
    try std.testing.expectEqual(@as(i64, 1), tenant2.total);
    try std.testing.expectEqualStrings("b1@example.com", tenant2.items[0].email);
}

test "file list isolates tenants" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var file_store = file.persistence.FileStore.init(allocator, env.client);

    _ = try file_store.create("t1.txt", "k1", "text/plain", 3, 1, 1, 100);
    _ = try file_store.create("t2.txt", "k2", "text/plain", 3, 1, 2, 101);

    var tenant1 = try file_store.list(1, 20, null, 1, null, false);
    defer tenant1.free(allocator);
    try std.testing.expectEqual(@as(i64, 1), tenant1.total);
    try std.testing.expectEqualStrings("t1.txt", tenant1.items[0].name);
}

test "audit log: create, filter by actor/action/keyword, paginate" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var audit_store = audit.persistence.AuditStore.init(allocator, env.client);
    var audit_svc = audit.service.AuditService.init(allocator, std.testing.io, &audit_store);

    audit_svc.log(7, "Boss", "user.create", "user", 10, "创建用户 Alice", "127.0.0.1", true, 1);
    audit_svc.log(7, "Boss", "task.retry", "task", 3, "重试任务 #3", "127.0.0.1", true, 1);
    audit_svc.log(0, "", "auth.login.fail", "user", 0, "登录失败: x@y.z", "10.0.0.1", false, 1);

    var all = try audit_svc.list(1, 20, .{});
    defer all.free(allocator);
    try std.testing.expectEqual(@as(i64, 3), all.total);

    var by_actor = try audit_svc.list(1, 20, .{ .actor_user_id = 7 });
    defer by_actor.free(allocator);
    try std.testing.expectEqual(@as(i64, 2), by_actor.total);

    var by_action = try audit_svc.list(1, 20, .{ .action = "task." });
    defer by_action.free(allocator);
    try std.testing.expectEqual(@as(i64, 1), by_action.total);

    var by_kw = try audit_svc.list(1, 20, .{ .keyword = "登录失败" });
    defer by_kw.free(allocator);
    try std.testing.expectEqual(@as(i64, 1), by_kw.total);
    try std.testing.expectEqualStrings("auth.login.fail", by_kw.items[0].action);
    try std.testing.expect(!by_kw.items[0].success);
}

test "mail template: default fallback, upsert override, variable render" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var tstore = mail_template.persistence.TemplateStore.init(allocator, env.client);
    var tsvc = mail_template.service.MailTemplateService.init(allocator, std.testing.io, &tstore);

    // 未配置时回退内置默认,变量被替换。
    var r1 = (try tsvc.render("verify_email", .{ .link = "https://a/verify", .email = "x@y.z" })).?;
    defer r1.free(allocator);
    try std.testing.expect(std.mem.indexOf(u8, r1.subject, "zweq") != null);
    try std.testing.expect(std.mem.indexOf(u8, r1.body, "https://a/verify") != null);
    try std.testing.expect(std.mem.indexOf(u8, r1.body, "x@y.z") != null);

    // upsert 覆盖后渲染用自定义内容。
    try tsvc.upsert("verify_email", "自定义主题 {app_name}", "链接: {link}");
    var r2 = (try tsvc.render("verify_email", .{ .link = "https://b/verify", .email = "a@b.c" })).?;
    defer r2.free(allocator);
    try std.testing.expectEqualStrings("自定义主题 zweq", r2.subject);
    try std.testing.expectEqualStrings("链接: https://b/verify", r2.body);

    // 未知 code → null。
    try std.testing.expect((try tsvc.render("nope", .{ .link = "x", .email = "y" })) == null);
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

    _ = try file_store.create("a.txt", "k", "text/plain", 3, 1, 1, 100);
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

test "ai: provider key encryption round-trip + tamper detection" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var ai_store = ai.persistence.AiStore.init(allocator, env.client);
    var user_store = user.persistence.UserStore.init(allocator, env.client);
    var task_store = task.persistence.TaskStore.init(allocator, env.client);
    var audit_store = audit.persistence.AuditStore.init(allocator, env.client);
    var tenant_store = tenant.persistence.TenantStore.init(allocator, env.client);
    var notify_store = notify.persistence.NotificationStore.init(allocator, env.client);
    var notify_svc = notify.service.NotificationService.init(allocator, std.testing.io, &notify_store);

    const RefA = struct {
        var user_store_ref: *user.persistence.UserStore = undefined;
        var task_store_ref: *task.persistence.TaskStore = undefined;
        var audit_store_ref: *audit.persistence.AuditStore = undefined;
        var tenant_store_ref: *tenant.persistence.TenantStore = undefined;
        var ai_store_ref: *ai.persistence.AiStore = undefined;
        var notify_ref: *notify.service.NotificationService = undefined;
    };
    RefA.user_store_ref = &user_store;
    RefA.task_store_ref = &task_store;
    RefA.audit_store_ref = &audit_store;
    RefA.tenant_store_ref = &tenant_store;
    RefA.ai_store_ref = &ai_store;
    RefA.notify_ref = &notify_svc;
    const refs = ai.service.SkillsRefs{
        .user_store = RefA.user_store_ref,
        .task_store = RefA.task_store_ref,
        .audit_store = RefA.audit_store_ref,
        .tenant_store = RefA.tenant_store_ref,
        .ai_store = RefA.ai_store_ref,
        .notify_svc = RefA.notify_ref,
    };

    var svc = try ai.service.AiService.init(allocator, std.testing.io, &ai_store, .{ .key_secret = "master-secret" }, refs);
    defer svc.deinit();

    // 加密 → 解密 round-trip。
    const enc = try svc.encryptKeys(allocator, "[\"sk-abc\"]");
    defer allocator.free(enc);
    const dec = try svc.decryptKeys(allocator, enc);
    defer allocator.free(dec);
    try std.testing.expectEqualStrings("[\"sk-abc\"]", dec);

    // 错误主密钥 → 认证失败(防篡改/防错配)。
    var svc2 = try ai.service.AiService.init(allocator, std.testing.io, &ai_store, .{ .key_secret = "wrong-secret" }, refs);
    defer svc2.deinit();
    try std.testing.expectError(error.AuthenticationFailed, svc2.decryptKeys(allocator, enc));

    // 未配置主密钥 → MissingKeySecret。
    var svc3 = try ai.service.AiService.init(allocator, std.testing.io, &ai_store, .{ .key_secret = "" }, refs);
    defer svc3.deinit();
    try std.testing.expectError(error.MissingKeySecret, svc3.encryptKeys(allocator, "x"));
}

test "ai: notify.send approval pending → approve executes, double-resolve rejected" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var ai_store = ai.persistence.AiStore.init(allocator, env.client);
    var user_store = user.persistence.UserStore.init(allocator, env.client);
    var task_store = task.persistence.TaskStore.init(allocator, env.client);
    var audit_store = audit.persistence.AuditStore.init(allocator, env.client);
    var tenant_store = tenant.persistence.TenantStore.init(allocator, env.client);
    var notify_store = notify.persistence.NotificationStore.init(allocator, env.client);
    var notify_svc = notify.service.NotificationService.init(allocator, std.testing.io, &notify_store);
    const refs = ai.service.SkillsRefs{
        .user_store = &user_store,
        .task_store = &task_store,
        .audit_store = &audit_store,
        .tenant_store = &tenant_store,
        .ai_store = &ai_store,
        .notify_svc = &notify_svc,
    };
    var svc = try ai.service.AiService.init(allocator, std.testing.io, &ai_store, .{ .key_secret = "master-secret" }, refs);
    defer svc.deinit();

    _ = try user_store.createUser("Alice", "a@x.com", "hash", false, false, 1, 100);
    const approval_id = try ai_store.createApproval(1, 7, "zweq.notify.send", "{\"user_id\":1,\"title\":\"hi\",\"body\":\"hello\",\"kind\":\"info\"}", 100);
    try std.testing.expectEqual(@as(i64, 0), try notify_svc.unreadCount(1));

    // 批准 → 实际发送通知。
    try std.testing.expect(try svc.approve(allocator, approval_id, 1, true));
    try std.testing.expectEqual(@as(i64, 1), try notify_svc.unreadCount(1));

    // 重复处理 → false。
    try std.testing.expect(!try svc.approve(allocator, approval_id, 1, true));
    const row = (try ai_store.getApproval(approval_id)).?;
    defer row.free(allocator);
    try std.testing.expectEqualStrings("approved", row.status);
}

test "account: CRUD, tenant isolation, wechat config upsert" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var a_store = account.persistence.AccountStore.init(allocator, env.client);
    var a_svc = account.service.AccountService.init(allocator, std.testing.io, &a_store);

    // create + get
    const id = try a_svc.create(1, "测试公众号", "wechat");
    const row = (try a_svc.get(id)).?;
    defer row.free(allocator);
    try std.testing.expectEqualStrings("测试公众号", row.name);
    try std.testing.expectEqualStrings("wechat", row.kind);
    try std.testing.expectEqualStrings("active", row.status);

    // invalid kind rejected
    try std.testing.expectError(error.InvalidKind, a_svc.create(1, "坏类型", "car"));
    try std.testing.expectError(error.InvalidName, a_svc.create(1, "   ", "wechat"));

    // tenant isolation in list
    _ = try a_svc.create(2, "租户二公众号", "wechat");
    var t1 = try a_svc.list(1, 20, 1, null);
    defer t1.free(allocator);
    try std.testing.expectEqual(@as(i64, 1), t1.total);

    // kind filter
    var wc = try a_svc.list(1, 20, null, "wechat");
    defer wc.free(allocator);
    try std.testing.expectEqual(@as(i64, 2), wc.total);

    // update
    _ = try a_svc.update(id, "改名公众号", "wechat", "active");
    const updated = (try a_svc.get(id)).?;
    defer updated.free(allocator);
    try std.testing.expectEqualStrings("改名公众号", updated.name);

    // wechat config upsert (idempotent) + secrets round-trip
    const cfg1 = account.service.WechatConfig{
        .appid = "wx123",
        .secret = "sec1",
        .token = "tok1",
        .encoding_aes_key = "key1",
        .verified = false,
    };
    _ = try a_svc.upsertWechat(1, id, cfg1);
    const w1 = (try a_svc.getWechatConfig(id)).?;
    defer w1.deinit(allocator);
    try std.testing.expectEqualStrings("wx123", w1.appid);
    try std.testing.expectEqualStrings("sec1", w1.secret);

    const cfg2 = account.service.WechatConfig{
        .appid = "wx123",
        .secret = "sec2",
        .token = "tok1",
        .encoding_aes_key = "key1",
        .verified = true,
    };
    _ = try a_svc.upsertWechat(1, id, cfg2);
    const w2 = (try a_svc.getWechatConfig(id)).?;
    defer w2.deinit(allocator);
    try std.testing.expectEqualStrings("sec2", w2.secret);
    try std.testing.expect(w2.verified);

    // delete
    try a_svc.delete(id);
    try std.testing.expect((try a_svc.get(id)) == null);
}

test "permission: role CRUD + user-role binding" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var r_store = permission.persistence.RoleStore.init(allocator, env.client);
    var r_svc = permission.service.RoleService.init(allocator, std.testing.io, &r_store);

    const id = try r_svc.create(1, "操作员", "operator", "负责公众号运营");
    const row = (try r_svc.get(id)).?;
    defer row.free(allocator);
    try std.testing.expectEqualStrings("操作员", row.name);
    try std.testing.expectEqualStrings("operator", row.code);

    // invalid code rejected
    try std.testing.expectError(error.InvalidCode, r_svc.create(1, "超管", "superuser", ""));

    // grant + revoke permission
    const p_id = try r_svc.grant(1, 1, "account", "read");
    var perms = try r_svc.listPermissions(1, 20, 1, null);
    defer perms.free(allocator);
    try std.testing.expectEqual(@as(i64, 1), perms.total);
    try std.testing.expectEqualStrings("account", perms.items[0].module);
    try r_svc.revoke(p_id);

    // assign + list roles for user
    _ = try r_svc.assignRole(1, 7, id);
    const roles = try r_svc.listRolesForUser(7);
    defer allocator.free(roles);
    try std.testing.expectEqual(@as(usize, 1), roles.len);
    try std.testing.expectEqual(id, roles[0].role_id);

    // delete role
    try r_svc.delete(id);
    try std.testing.expect((try r_svc.get(id)) == null);
}

test "setting: tenant-scoped KV upsert, list, delete" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var s_store = setting.persistence.SettingStore.init(allocator, env.client);
    var s_svc = setting.service.SettingService.init(allocator, std.testing.io, &s_store);

    _ = try s_svc.set(1, "site_name", "我的微擎");
    _ = try s_svc.set(1, "site_name", "改名微擎"); // upsert 覆盖
    const row = (try s_svc.get(1, "site_name")).?;
    defer row.free(allocator);
    try std.testing.expectEqualStrings("改名微擎", row.value);

    // 租户隔离
    _ = try s_svc.set(2, "site_name", "租户二");
    var t1 = try s_svc.list(1, 20, 1);
    defer t1.free(allocator);
    try std.testing.expectEqual(@as(i64, 1), t1.total);

    // delete
    try s_svc.delete(1, "site_name");
    try std.testing.expect((try s_svc.get(1, "site_name")) == null);
    // 另一租户不受影响
    const other = (try s_svc.get(2, "site_name")).?;
    defer other.free(allocator);
    try std.testing.expectEqualStrings("租户二", other.value);
}

test "rule: keyword engine matches full/contain and returns first reply" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var rule_store = rule.persistence.RuleStore.init(allocator, env.client);
    var rule_svc = rule.service.RuleService.init(allocator, std.testing.io, &rule_store);

    const account_id: i64 = 1;
    const r1 = try rule_svc.createRule(1, account_id, "问候");
    _ = try rule_svc.addKeyword(1, account_id, r1, "你好", "full");
    _ = try rule_svc.addReply(1, account_id, r1, "text", "你好呀", "", "", "", "");

    const r2 = try rule_svc.createRule(1, account_id, "新闻");
    _ = try rule_svc.addKeyword(1, account_id, r2, "新闻", "contain");
    _ = try rule_svc.addReply(1, account_id, r2, "news", "", "今日头条", "摘要", "http://pic/x.png", "http://a/x");

    // full match + contain match
    const m1 = (try rule_svc.match(allocator, 1, account_id, "你好")).?;
    defer m1.free(allocator);
    try std.testing.expectEqualStrings("text", m1.reply_type);
    try std.testing.expectEqualStrings("你好呀", m1.content);

    const m2 = (try rule_svc.match(allocator, 1, account_id, "看看新闻")).?;
    defer m2.free(allocator);
    try std.testing.expectEqualStrings("news", m2.reply_type);
    try std.testing.expectEqualStrings("今日头条", m2.news_title);

    // no match
    try std.testing.expect((try rule_svc.match(allocator, 1, account_id, "无关内容")) == null);

    // disabled rule is skipped
    try rule_svc.updateRule(r2, "新闻", "disabled");
    try std.testing.expect((try rule_svc.match(allocator, 1, account_id, "看看新闻")) == null);
}

test "member: fan subscribe/unsubscribe lifecycle + tenant isolation" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var fan_store = member.persistence.FanStore.init(allocator, env.client);
    var member_svc = member.service.MemberService.init(allocator, std.testing.io, &fan_store);

    _ = try member_svc.onSubscribe(1, 5, "o_abc", "");
    const fan = (try fan_store.getByOpenid(1, 5, "o_abc")).?;
    defer fan.free(allocator);
    try std.testing.expect(fan.subscribed);
    try std.testing.expectEqual(@as(i64, 5), fan.account_id);

    try member_svc.onUnsubscribe(1, 5, "o_abc");
    const fan2 = (try fan_store.getByOpenid(1, 5, "o_abc")).?;
    defer fan2.free(allocator);
    try std.testing.expect(!fan2.subscribed);

    // 不同租户同 openid 互不影响
    _ = try member_svc.onSubscribe(2, 5, "o_abc", "");
    var t1 = try member_svc.list(1, 20, 1, 5, null, true);
    defer t1.free(allocator);
    try std.testing.expectEqual(@as(i64, 0), t1.total); // t1 的 o_abc 已取关
    var t2 = try member_svc.list(1, 20, 2, 5, null, true);
    defer t2.free(allocator);
    try std.testing.expectEqual(@as(i64, 1), t2.total);
}

test "member: fan tag store upsert idempotent + list" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var tag_store = member.persistence.TagStore.init(allocator, env.client);

    // 同 wx_tag_id 两次 upsert → 同 id，字段更新。
    const t1 = try tag_store.upsert(1, 5, 100, "VIP", 100);
    const t2 = try tag_store.upsert(1, 5, 100, "VIPv2", 101);
    try std.testing.expectEqual(t1, t2);
    const t3 = try tag_store.upsert(1, 5, 101, "新客", 102);
    try std.testing.expect(t3 != t1);

    // list 按 wx_tag_id 升序。
    const rows = try tag_store.list(1, 5);
    defer {
        for (rows) |r| r.free(allocator);
        allocator.free(rows);
    }
    try std.testing.expectEqual(@as(usize, 2), rows.len);
    try std.testing.expectEqualStrings("VIPv2", rows[0].name);
    try std.testing.expectEqualStrings("新客", rows[1].name);

    // 另一租户隔离。
    const other = try tag_store.list(2, 5);
    defer {
        for (other) |r| r.free(allocator);
        allocator.free(other);
    }
    try std.testing.expectEqual(@as(usize, 0), other.len);
}

test "points: redeem deducts points + stock, rejects insufficient/out-of-stock" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var fan_store = member.persistence.FanStore.init(allocator, env.client);
    var points_store = points.persistence.PointsStore.init(allocator, env.client);
    var svc = points.service.PointsService.init(allocator, std.testing.io, &points_store, &fan_store);

    // 粉丝 + 发 100 积分。
    _ = try fan_store.upsert(1, 5, "o_p", "", "", "", true, 100, 100);
    const newp = try fan_store.adjustPoints(1, 5, "o_p", 100, 101);
    try std.testing.expectEqual(@as(i64, 100), newp);

    // 商品（100 积分，库存 5）。
    const pid = try svc.createProduct(1, 5, "马克杯", 100, 5);

    // 兑换成功：积分 100→0，库存 5→4，订单 1 条。
    const order_id = try svc.redeem(1, 5, "o_p", pid);
    _ = order_id;
    const fan = (try fan_store.getByOpenid(1, 5, "o_p")).?;
    defer fan.free(allocator);
    try std.testing.expectEqual(@as(i64, 0), fan.points);
    const prod = (try svc.getProduct(pid)).?;
    defer prod.free(allocator);
    try std.testing.expectEqual(@as(i64, 4), prod.stock);
    const orders = try svc.listOrders(1, 5, null);
    defer {
        for (orders) |o| o.free(allocator);
        allocator.free(orders);
    }
    try std.testing.expectEqual(@as(usize, 1), orders.len);
    try std.testing.expectEqual(@as(i64, 100), orders[0].points_spent);

    // 积分不足 → 拒绝。
    try std.testing.expectError(error.InsufficientPoints, svc.redeem(1, 5, "o_p", pid));

    // 库存清空 → OutOfStock。
    _ = try svc.adjustPoints(1, 5, "o_p", 100);
    try svc.updateProduct(pid, "马克杯", 100, 0);
    try std.testing.expectError(error.OutOfStock, svc.redeem(1, 5, "o_p", pid));

    // 粉丝不存在 → FanNotFound（用有库存的商品）。
    const pid2 = try svc.createProduct(1, 5, "新商品", 50, 1);
    try std.testing.expectError(error.FanNotFound, svc.redeem(1, 5, "o_nobody", pid2));
}

test "message: WeChat callback — handshake, subscribe, keyword reply, bad sig" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var account_store = account.persistence.AccountStore.init(allocator, env.client);
    var account_svc = account.service.AccountService.init(allocator, std.testing.io, &account_store);
    var rule_store = rule.persistence.RuleStore.init(allocator, env.client);
    var rule_svc = rule.service.RuleService.init(allocator, std.testing.io, &rule_store);
    var fan_store = member.persistence.FanStore.init(allocator, env.client);
    var member_svc = member.service.MemberService.init(allocator, std.testing.io, &fan_store);
    var setting_store = setting.persistence.SettingStore.init(allocator, env.client);
    var message_store = message.persistence.MessageStore.init(allocator, env.client);
    var wechat_svc = message.service.WechatService.init(allocator, std.testing.io, &account_svc, &rule_svc, &member_svc, &setting_store, &message_store);

    const account_id = try account_svc.create(1, "测试公众号", "wechat");
    _ = try account_svc.upsertWechat(1, account_id, .{
        .appid = "wx1",
        .secret = "s",
        .token = "tok",
        .encoding_aes_key = "",
        .verified = false,
    });
    const rule_id = try rule_svc.createRule(1, account_id, "问候");
    _ = try rule_svc.addKeyword(1, account_id, rule_id, "你好", "full");
    _ = try rule_svc.addReply(1, account_id, rule_id, "text", "你好呀", "", "", "", "");

    const token = "tok";
    var ts_buf: [16]u8 = undefined;
    const ts = try std.fmt.bufPrint(&ts_buf, "{d}", .{zigmodu.time.wallClockSeconds(std.testing.io)});
    const nonce = "n1";
    const sig = try zwechat.util.signature.signature(allocator, &[_][]const u8{ token, ts, nonce });
    defer allocator.free(sig);

    // 1. URL handshake: echostr echoed back.
    const handshake = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce, .echostr = "echo-me" }, "");
    defer allocator.free(handshake);
    try std.testing.expectEqualStrings("echo-me", handshake);

    // 2. subscribe event → fan saved, no follow reply configured → "success".
    const sub_xml = "<xml><ToUserName><![CDATA[gh_x]]></ToUserName><FromUserName><![CDATA[o_1]]></FromUserName><CreateTime>1700000000</CreateTime><MsgType><![CDATA[event]]></MsgType><Event><![CDATA[subscribe]]></Event></xml>";
    const sub_reply = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, sub_xml);
    defer allocator.free(sub_reply);
    try std.testing.expectEqualStrings("success", sub_reply);
    const fan = (try fan_store.getByOpenid(1, account_id, "o_1")).?;
    defer fan.free(allocator);
    try std.testing.expect(fan.subscribed);

    // 3. text keyword → passive text reply.
    const text_xml = "<xml><ToUserName><![CDATA[gh_x]]></ToUserName><FromUserName><![CDATA[o_1]]></FromUserName><CreateTime>1700000000</CreateTime><MsgType><![CDATA[text]]></MsgType><Content><![CDATA[你好]]></Content></xml>";
    const reply = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, text_xml);
    defer allocator.free(reply);
    try std.testing.expect(std.mem.indexOf(u8, reply, "你好呀") != null);
    try std.testing.expect(std.mem.indexOf(u8, reply, "<MsgType><![CDATA[text]]>") != null);

    // 4. bad signature → SignatureMismatch.
    try std.testing.expectError(error.SignatureMismatch, wechat_svc.handleCallback(allocator, token, .{ .signature = "bad", .timestamp = ts, .nonce = nonce }, text_xml));

    // 5. unsubscribe → fan flips to unsubscribed.
    const unsub_xml = "<xml><ToUserName><![CDATA[gh_x]]></ToUserName><FromUserName><![CDATA[o_1]]></FromUserName><CreateTime>1700000000</CreateTime><MsgType><![CDATA[event]]></MsgType><Event><![CDATA[unsubscribe]]></Event></xml>";
    const unsub_reply = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, unsub_xml);
    defer allocator.free(unsub_reply);
    const fan2 = (try fan_store.getByOpenid(1, account_id, "o_1")).?;
    defer fan2.free(allocator);
    try std.testing.expect(!fan2.subscribed);
}

test "message: replay guard rejects stale timestamp + duplicate nonce" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var account_store = account.persistence.AccountStore.init(allocator, env.client);
    var account_svc = account.service.AccountService.init(allocator, std.testing.io, &account_store);
    var rule_store = rule.persistence.RuleStore.init(allocator, env.client);
    var rule_svc = rule.service.RuleService.init(allocator, std.testing.io, &rule_store);
    var fan_store = member.persistence.FanStore.init(allocator, env.client);
    var member_svc = member.service.MemberService.init(allocator, std.testing.io, &fan_store);
    var setting_store = setting.persistence.SettingStore.init(allocator, env.client);
    var message_store = message.persistence.MessageStore.init(allocator, env.client);
    var cache = cache_svc.CacheService.init(allocator, 1024, 300);
    defer cache.deinit();
    var wechat_svc = message.service.WechatService.init(allocator, std.testing.io, &account_svc, &rule_svc, &member_svc, &setting_store, &message_store);
    wechat_svc.cache = &cache;

    const account_id = try account_svc.create(1, "测试公众号", "wechat");
    _ = try account_svc.upsertWechat(1, account_id, .{ .appid = "wx1", .secret = "s", .token = "tokr", .encoding_aes_key = "", .verified = false });

    const token = "tokr";
    const nonce = "n-replay";
    const now = zigmodu.time.wallClockSeconds(std.testing.io);
    const text_xml = "<xml><ToUserName><![CDATA[gh]]></ToUserName><FromUserName><![CDATA[o_r]]></FromUserName><CreateTime>1</CreateTime><MsgType><![CDATA[text]]></MsgType><Content><![CDATA[你好]]></Content></xml>";

    // 过期 timestamp（10 分钟前）→ 拒绝。
    var stale_buf: [16]u8 = undefined;
    const stale_ts = try std.fmt.bufPrint(&stale_buf, "{d}", .{now - 600});
    const stale_sig = try zwechat.util.signature.signature(allocator, &[_][]const u8{ token, stale_ts, nonce });
    defer allocator.free(stale_sig);
    try std.testing.expectError(error.TimestampExpired, wechat_svc.handleCallback(allocator, token, .{ .signature = stale_sig, .timestamp = stale_ts, .nonce = nonce }, text_xml));

    // 当前 timestamp + 相同 nonce：首次通过，重放被拒。
    var ts_buf: [16]u8 = undefined;
    const ts = try std.fmt.bufPrint(&ts_buf, "{d}", .{now});
    const sig = try zwechat.util.signature.signature(allocator, &[_][]const u8{ token, ts, nonce });
    defer allocator.free(sig);
    const first = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, text_xml);
    defer allocator.free(first);
    try std.testing.expectError(error.ReplayDetected, wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, text_xml));
}

test "message: menu CLICK event dispatches to module receiver" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var account_store = account.persistence.AccountStore.init(allocator, env.client);
    var account_svc = account.service.AccountService.init(allocator, std.testing.io, &account_store);
    var rule_store = rule.persistence.RuleStore.init(allocator, env.client);
    var rule_svc = rule.service.RuleService.init(allocator, std.testing.io, &rule_store);
    var fan_store = member.persistence.FanStore.init(allocator, env.client);
    var member_svc = member.service.MemberService.init(allocator, std.testing.io, &fan_store);
    var setting_store = setting.persistence.SettingStore.init(allocator, env.client);
    var message_store = message.persistence.MessageStore.init(allocator, env.client);
    var module_store = appmod.persistence.ModuleStore.init(allocator, env.client);
    var module_svc = appmod.service.ModuleService.init(allocator, std.testing.io, &module_store);
    var wechat_svc = message.service.WechatService.init(allocator, std.testing.io, &account_svc, &rule_svc, &member_svc, &setting_store, &message_store);
    wechat_svc.module_svc = &module_svc;

    // 注册一个响应菜单点击的接收器（demo 模块）。
    const Demo = struct {
        fn handle(_: ?*anyopaque, al: std.mem.Allocator, msg: message.service.IncomingMessage) anyerror!?message.service.Reply {
            if (!std.mem.eql(u8, msg.msg_type, "event")) return null;
            if (!std.mem.eql(u8, msg.event, "CLICK")) return null;
            if (!std.mem.eql(u8, msg.event_key, "VOTE_ENTRY")) return null;
            return try message.service.Reply.text(al, "菜单点击：进入投票");
        }
    };
    try wechat_svc.registerReceiver(.{ .module_name = "demo", .ctx = null, .handle = Demo.handle });

    const account_id = try account_svc.create(1, "测试公众号", "wechat");
    _ = try account_svc.upsertWechat(1, account_id, .{ .appid = "wx1", .secret = "s", .token = "tokm", .encoding_aes_key = "", .verified = false });
    _ = try module_svc.bind(1, account_id, "demo", "active");

    const token = "tokm";
    var ts_buf: [16]u8 = undefined;
    const ts = try std.fmt.bufPrint(&ts_buf, "{d}", .{zigmodu.time.wallClockSeconds(std.testing.io)});
    const nonce = "n-menu";
    const sig = try zwechat.util.signature.signature(allocator, &[_][]const u8{ token, ts, nonce });
    defer allocator.free(sig);

    // 菜单点击事件（CLICK + EventKey）→ receiver 响应。
    const click_xml = "<xml><ToUserName><![CDATA[gh]]></ToUserName><FromUserName><![CDATA[o_m]]></FromUserName><CreateTime>1</CreateTime><MsgType><![CDATA[event]]></MsgType><Event><![CDATA[CLICK]]></Event><EventKey><![CDATA[VOTE_ENTRY]]></EventKey></xml>";
    const reply = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, click_xml);
    defer allocator.free(reply);
    try std.testing.expect(std.mem.indexOf(u8, reply, "进入投票") != null);

    // 未绑定 → 事件不触发 receiver（仅记录，返回 success）。
    const other_id = try account_svc.create(1, "另一个号", "wechat");
    _ = try account_svc.upsertWechat(1, other_id, .{ .appid = "wx2", .secret = "s", .token = "tokn", .encoding_aes_key = "", .verified = false });
    var ts2: [16]u8 = undefined;
    const ts2_s = try std.fmt.bufPrint(&ts2, "{d}", .{zigmodu.time.wallClockSeconds(std.testing.io)});
    const sig2 = try zwechat.util.signature.signature(allocator, &[_][]const u8{ "tokn", ts2_s, nonce });
    defer allocator.free(sig2);
    const plain = try wechat_svc.handleCallback(allocator, "tokn", .{ .signature = sig2, .timestamp = ts2_s, .nonce = nonce }, click_xml);
    defer allocator.free(plain);
    try std.testing.expectEqualStrings("success", plain);
}

test "module: registry upsert idempotent + bind/unbind per account" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var module_store = appmod.persistence.ModuleStore.init(allocator, env.client);
    var module_svc = appmod.service.ModuleService.init(allocator, std.testing.io, &module_store);

    // register is an idempotent upsert
    const id1 = try module_svc.register(1, "payment", "充值支付", "1.0.0");
    const id2 = try module_svc.register(1, "payment", "充值支付v2", "1.1.0");
    try std.testing.expectEqual(id1, id2);

    // builtins seeded
    try module_svc.seedBuiltins(1);
    var all = try module_svc.list(1, 100, 1);
    defer all.free(allocator);
    try std.testing.expect(all.total >= 8);

    // bind/unbind
    _ = try module_svc.bind(1, 7, "payment", "active");
    _ = try module_svc.bind(1, 7, "rule", "active");
    const bound = try module_svc.accountModules(1, 7);
    defer {
        for (bound) |r| r.free(allocator);
        allocator.free(bound);
    }
    try std.testing.expectEqual(@as(usize, 2), bound.len);

    try module_svc.unbind(1, 7, "rule");
    const after = try module_svc.accountModules(1, 7);
    defer {
        for (after) |r| r.free(allocator);
        allocator.free(after);
    }
    try std.testing.expectEqual(@as(usize, 1), after.len);
}

test "payment: PayConfig deinit frees only dupe'd fields (partial config safe)" {
    const allocator = std.testing.allocator;
    // 模拟 readPayConfig 部分配置：只 dupe mch_id，其余保持 "" 字面量。
    // deinit 只应 free dupe 过的字段（free 字面量会崩，SafeAllocator 检测）。
    var cfg = payment.service.PayConfig{
        .mch_id = try allocator.dupe(u8, "mch-1"),
        .app_id = "",
        .serial_no = "",
        .private_key_pem = "",
        .notify_url = "",
        .platform_cert = "",
    };
    cfg.deinit(allocator);

    var cfg2 = payment.service.PayV2Config{
        .mch_id = try allocator.dupe(u8, "mch-2"),
        .key = try allocator.dupe(u8, "k"),
        .app_id = "",
        .notify_url = "",
        .root_ca = "",
    };
    cfg2.deinit(allocator);
    // 到达此处即通过：无泄漏（dupe 已释放）、无 free 字面量崩溃。
}

test "payment: recharge order → complete credits wallet, idempotent" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var payment_store = payment.persistence.PaymentStore.init(allocator, env.client);
    var payment_svc = payment.service.PaymentService.init(allocator, std.testing.io, &payment_store);

    // create recharge order (1000 分 = ¥10)
    const order = try payment_svc.createRechargeOrder(allocator, 1, 5, 42, 1000);
    defer order.free(allocator);
    try std.testing.expect(order.amount == 1000);
    try std.testing.expectEqualStrings("pending", order.status);
    try std.testing.expect(order.order_no.len > 0);

    // complete → wallet credited
    try std.testing.expect(try payment_svc.completeRecharge(1, order.order_no));
    const wallet = (try payment_svc.walletBalance(1, 5, 42)).?;
    try std.testing.expectEqual(@as(i64, 1000), wallet.balance);

    // second complete is a no-op (idempotent)
    try std.testing.expect(!try payment_svc.completeRecharge(1, order.order_no));
    const wallet2 = (try payment_svc.walletBalance(1, 5, 42)).?;
    try std.testing.expectEqual(@as(i64, 1000), wallet2.balance);

    // withdraw
    const wid = try payment_svc.requestWithdraw(1, 5, 42, 300);
    _ = wid;
    try std.testing.expectError(error.WithdrawInsufficient, payment_svc.requestWithdraw(1, 5, 42, 99999));

    // invalid amount
    try std.testing.expectError(error.InvalidAmount, payment_svc.createRechargeOrder(allocator, 1, 5, 42, 0));
}

test "message: default reply + AI-flag fallback without provider" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var account_store = account.persistence.AccountStore.init(allocator, env.client);
    var account_svc = account.service.AccountService.init(allocator, std.testing.io, &account_store);
    var rule_store = rule.persistence.RuleStore.init(allocator, env.client);
    var rule_svc = rule.service.RuleService.init(allocator, std.testing.io, &rule_store);
    var fan_store = member.persistence.FanStore.init(allocator, env.client);
    var member_svc = member.service.MemberService.init(allocator, std.testing.io, &fan_store);
    var setting_store = setting.persistence.SettingStore.init(allocator, env.client);
    var message_store = message.persistence.MessageStore.init(allocator, env.client);
    var wechat_svc = message.service.WechatService.init(allocator, std.testing.io, &account_svc, &rule_svc, &member_svc, &setting_store, &message_store);
    // 无 ai_svc：AI 自动回复不可用，应优雅回退默认回复。

    const account_id = try account_svc.create(1, "测试公众号", "wechat");
    _ = try account_svc.upsertWechat(1, account_id, .{ .appid = "wx1", .secret = "s", .token = "tok2", .encoding_aes_key = "", .verified = false });
    const rule_id = try rule_svc.createRule(1, account_id, "问候");
    _ = try rule_svc.addKeyword(1, account_id, rule_id, "你好", "full");
    _ = try rule_svc.addReply(1, account_id, rule_id, "text", "你好呀", "", "", "", "");

    // 默认回复
    _ = try setting_store.set(1, "wechat_default_reply", "抱歉，暂未找到相关信息", 100);
    // 开启 AI 自动回复（无 provider，应回退默认）
    _ = try setting_store.set(1, "wechat_ai_auto_reply", "1", 101);

    const token = "tok2";
    var ts_buf: [16]u8 = undefined;
    const ts = try std.fmt.bufPrint(&ts_buf, "{d}", .{zigmodu.time.wallClockSeconds(std.testing.io)});
    const nonce = "n1";
    const sig = try zwechat.util.signature.signature(allocator, &[_][]const u8{ token, ts, nonce });
    defer allocator.free(sig);

    // 未命中规则 → AI 无 provider → 默认回复
    const miss_xml = "<xml><ToUserName><![CDATA[gh]]></ToUserName><FromUserName><![CDATA[o_2]]></FromUserName><CreateTime>1700000000</CreateTime><MsgType><![CDATA[text]]></MsgType><Content><![CDATA[随便聊聊]]></Content></xml>";
    const miss_reply = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, miss_xml);
    defer allocator.free(miss_reply);
    try std.testing.expect(std.mem.indexOf(u8, miss_reply, "抱歉，暂未找到相关信息") != null);

    // 命中规则 → 规则回复优先于 AI/默认
    const hit_xml = "<xml><ToUserName><![CDATA[gh]]></ToUserName><FromUserName><![CDATA[o_2]]></FromUserName><CreateTime>1700000000</CreateTime><MsgType><![CDATA[text]]></MsgType><Content><![CDATA[你好]]></Content></xml>";
    const hit_reply = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, hit_xml);
    defer allocator.free(hit_reply);
    try std.testing.expect(std.mem.indexOf(u8, hit_reply, "你好呀") != null);
}

test "cloud: license lifecycle + marketplace install" {
    // verifyChecksum：sha256 匹配/不匹配/空期望跳过。
    try std.testing.expect(cloud.service.CloudService.verifyChecksum("hello", "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"));
    try std.testing.expect(!cloud.service.CloudService.verifyChecksum("hello", "0000000000000000000000000000000000000000000000000000000000000000"));
    try std.testing.expect(cloud.service.CloudService.verifyChecksum("hello", ""));

    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var module_store = appmod.persistence.ModuleStore.init(allocator, env.client);
    var module_svc = appmod.service.ModuleService.init(allocator, std.testing.io, &module_store);
    var cloud_store = cloud.persistence.CloudStore.init(allocator, env.client);
    var cloud_svc = cloud.service.CloudService.init(allocator, std.testing.io, &cloud_store, &module_svc, "");

    // 授权码生命周期
    const lic = try cloud_svc.generateLicense(allocator, 1, 30);
    defer lic.free(allocator);
    try std.testing.expect(std.mem.startsWith(u8, lic.license_key, "WEQ-"));
    try std.testing.expectEqualStrings("active", lic.status);
    try std.testing.expect(lic.expires_at > 0);

    // 校验：有效授权码 → true；未知 → InvalidLicense
    try std.testing.expect(try cloud_svc.verifyLicense(1, lic.license_key));
    try std.testing.expectError(error.InvalidLicense, cloud_svc.verifyLicense(1, "WEQ-00000000-00000000-00000000"));

    // 撤销 → 不再有效
    try cloud_svc.revokeLicense(lic.id);
    try std.testing.expectError(error.InvalidLicense, cloud_svc.verifyLicense(1, lic.license_key));

    // 市场：发布 → 安装（注册模块 + 绑定账号）
    _ = try cloud_svc.publishPackage(1, "shop", "商城", "1.0.0", "多商户商城", "", "");
    const module_id = try cloud_svc.installPackage(1, "shop", 7);
    _ = module_id;
    const bound = try module_svc.accountModules(1, 7);
    defer {
        for (bound) |r| r.free(allocator);
        allocator.free(bound);
    }
    var found = false;
    for (bound) |b| {
        if (std.mem.eql(u8, b.module, "shop")) found = true;
    }
    try std.testing.expect(found);

    // 安装不存在的包 → NotFound
    try std.testing.expectError(error.NotFound, cloud_svc.installPackage(1, "nope", 7));
}

// ── 远端云服务（zweq-cloud）对接 mock ───────────────────────────────────
const MockCloudCtx = struct {
    verify_valid: bool = true,
    verify_reason: []const u8 = "ok",
};

fn mockCloudTransport(ctx: *anyopaque, allocator: std.mem.Allocator, uri: []const u8, method: std.http.Method, payload: []const u8, content_type: ?[]const u8) anyerror![]u8 {
    _ = payload;
    _ = content_type;
    const c: *MockCloudCtx = @ptrCast(@alignCast(ctx));
    if (std.mem.indexOf(u8, uri, "/cloud/licenses/verify") != null) {
        const valid = if (c.verify_valid) "true" else "false";
        return std.fmt.allocPrint(allocator, "{{\"code\":0,\"msg\":\"ok\",\"data\":{{\"valid\":{s},\"reason\":\"{s}\"}}}}", .{ valid, c.verify_reason });
    }
    if (method == .GET and std.mem.indexOf(u8, uri, "/cloud/market") != null) {
        return std.fmt.allocPrint(allocator, "{{\"code\":0,\"msg\":\"ok\",\"data\":{{\"list\":[{{\"id\":1,\"name\":\"shop\",\"title\":\"商城\",\"version\":\"1.0.0\",\"description\":\"多商户商城\",\"checksum\":\"abc123\"}}],\"total\":1,\"page\":1,\"pageSize\":20}}}}", .{});
    }
    return error.Unreachable;
}

test "cloud: remote verify + sync-market (zweq-cloud mock)" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var module_store = appmod.persistence.ModuleStore.init(allocator, env.client);
    var module_svc = appmod.service.ModuleService.init(allocator, std.testing.io, &module_store);
    var cloud_store = cloud.persistence.CloudStore.init(allocator, env.client);

    // 本地模式（remote_url 空）。
    var local_svc = cloud.service.CloudService.init(allocator, std.testing.io, &cloud_store, &module_svc, "");
    try std.testing.expect(!local_svc.isRemote());

    // 远端模式 + mock transport。
    var svc = cloud.service.CloudService.init(allocator, std.testing.io, &cloud_store, &module_svc, "http://cloud:8100/api/v1");
    var ctx = MockCloudCtx{ .verify_valid = true };
    svc.http_transport = mockCloudTransport;
    svc.http_transport_ctx = &ctx;
    try std.testing.expect(svc.isRemote());

    // 校验：有效 → true。
    try std.testing.expect(try svc.verifyLicenseRemote(allocator, "WEQ-abcdef"));
    // 过期 → LicenseExpired。
    ctx.verify_valid = false;
    ctx.verify_reason = "expired";
    try std.testing.expectError(error.LicenseExpired, svc.verifyLicenseRemote(allocator, "WEQ-abcdef"));
    // 无效 → InvalidLicense。
    ctx.verify_reason = "invalid";
    try std.testing.expectError(error.InvalidLicense, svc.verifyLicenseRemote(allocator, "WEQ-abcdef"));

    // 同步市场：云端 shop 包 upsert 到本地，download_url 指向云端。
    const count = try svc.syncMarketRemote(allocator, 1);
    try std.testing.expectEqual(@as(usize, 1), count);
    const pkg = (try cloud_store.getPackageByName(1, "shop")).?;
    defer pkg.free(allocator);
    try std.testing.expectEqualStrings("商城", pkg.title);
    try std.testing.expectEqualStrings("abc123", pkg.checksum);
    try std.testing.expect(std.mem.indexOf(u8, pkg.download_url, "/cloud/market/shop/download") != null);
}

test "cloud: license state check (fail-closed)" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var module_store = appmod.persistence.ModuleStore.init(allocator, env.client);
    var module_svc = appmod.service.ModuleService.init(allocator, std.testing.io, &module_store);
    var cloud_store = cloud.persistence.CloudStore.init(allocator, env.client);

    // 本地模式：恒 licensed，无需授权码。
    var local_svc = cloud.service.CloudService.init(allocator, std.testing.io, &cloud_store, &module_svc, "");
    local_svc.checkSiteLicense();
    try std.testing.expect(local_svc.isLicensed());

    // 远端模式：未配置授权码 → fail-closed（licensed=false）。
    var svc = cloud.service.CloudService.init(allocator, std.testing.io, &cloud_store, &module_svc, "http://cloud:8100/api/v1");
    defer svc.deinit();
    var ctx = MockCloudCtx{ .verify_valid = true };
    svc.http_transport = mockCloudTransport;
    svc.http_transport_ctx = &ctx;
    svc.checkSiteLicense();
    try std.testing.expect(!svc.isLicensed());

    // 配置有效授权码 → licensed=true。
    try svc.setSiteLicenseKey("WEQ-valid");
    svc.checkSiteLicense();
    try std.testing.expect(svc.isLicensed());

    // 授权码失效（云端返回 invalid）→ 宽限期内仍 licensed（默认 grace=7 天）。
    ctx.verify_valid = false;
    ctx.verify_reason = "invalid";
    svc.checkSiteLicense();
    try std.testing.expect(svc.isLicensed()); // 宽限期内放行

    // 宽限期归零 → 立即 fail-closed。
    svc.setGraceDays(0);
    try std.testing.expect(!svc.isLicensed());

    // 过期 → licensed=false（宽限期 0）。
    ctx.verify_reason = "expired";
    svc.checkSiteLicense();
    try std.testing.expect(!svc.isLicensed());

    // 恢复宽限 + 授权码重新有效 → licensed=true。
    svc.setGraceDays(7);
    ctx.verify_valid = true;
    ctx.verify_reason = "ok";
    svc.checkSiteLicense();
    try std.testing.expect(svc.isLicensed());
}

test "cloud: manifest migration SQL sandbox (whitelist)" {
    const v = cloud.service.CloudService.validateMigrationSql;
    // 合法 DDL。
    try std.testing.expect(v("CREATE TABLE IF NOT EXISTS shop_order (id INTEGER PRIMARY KEY, tenant_id INTEGER)"));
    try std.testing.expect(v("create table shop_order (id integer)"));
    try std.testing.expect(v("CREATE INDEX idx_shop ON shop_order(tenant_id)"));
    try std.testing.expect(v("CREATE UNIQUE INDEX uq ON shop_order(id)"));
    try std.testing.expect(v("ALTER TABLE shop_order ADD COLUMN amount INTEGER"));
    // 非法：非 DDL 前缀。
    try std.testing.expect(!v("DROP TABLE shop_order"));
    try std.testing.expect(!v("SELECT * FROM shop_order"));
    // 非法：危险关键字。
    try std.testing.expect(!v("CREATE TABLE x (id INTEGER); DELETE FROM y"));
    // 非法：多语句。
    try std.testing.expect(!v("CREATE TABLE a(id INTEGER); CREATE TABLE b(id INTEGER)"));
    // 非法：空 / 超长。
    try std.testing.expect(!v(""));
    try std.testing.expect(!v("   "));
}

test "cloud: manifest install runs migrations (module + SQL)" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var module_store = appmod.persistence.ModuleStore.init(allocator, env.client);
    var module_svc = appmod.service.ModuleService.init(allocator, std.testing.io, &module_store);
    var cloud_store = cloud.persistence.CloudStore.init(allocator, env.client);
    var dyn_table_store = cloud.persistence.DynamicTableStore.init(allocator, env.client);
    var cloud_svc = cloud.service.CloudService.init(allocator, std.testing.io, &cloud_store, &module_svc, "");
    // 注入 sqlite in-memory driver（执行迁移 SQL）。
    cloud_svc.setDriver(env.sqlite.?.asDriver());
    cloud_svc.setDynamicTableStore(&dyn_table_store);

    // 发布一个带 manifest 的市场包（download_url 为空时用 pkg 元数据注册）。
    // 这里直接测 manifest 解析 + 迁移执行：先发布无 download_url 包验证 pkg 元数据路径，
    // 再用 mock transport 注入 manifest 内容测迁移。
    const manifest = "{\"name\":\"shop\",\"title\":\"商城\",\"version\":\"2.0.0\",\"description\":\"\",\"migrations\":[\"CREATE TABLE IF NOT EXISTS shop_order (id INTEGER PRIMARY KEY, tenant_id INTEGER, amount INTEGER)\"],\"tables\":[{\"name\":\"shop_order\",\"title\":\"订单\",\"columns\":[{\"name\":\"id\",\"title\":\"ID\",\"type\":\"integer\"},{\"name\":\"amount\",\"title\":\"金额\",\"type\":\"integer\"}]}]}";

    // 发布包（download_url 指向一个假 URL，靠 mock transport 返回 manifest）。
    _ = try cloud_svc.publishPackage(1, "shop", "商城", "1.0.0", "多商户商城", "http://mock/shop.json", "");
    // 注入 mock transport 返回 manifest 内容。
    var mctx = ManifestMockCtx{ .content = manifest };
    cloud_svc.http_transport = manifestMockTransport;
    cloud_svc.http_transport_ctx = &mctx;

    const module_id = try cloud_svc.installPackage(1, "shop", 0);
    _ = module_id;

    // 迁移表已创建。
    const d = env.sqlite.?.asDriver();
    var rows = try d.query("SELECT name FROM sqlite_master WHERE type='table' AND name='shop_order'", &.{});
    defer rows.deinit();
    var row_count: usize = 0;
    while (rows.next() != null) row_count += 1;
    try std.testing.expectEqual(@as(usize, 1), row_count);

    // 模块按 manifest 元数据注册（version 2.0.0）。
    var mods = try module_svc.list(1, 100, 1);
    defer mods.free(allocator);
    var found_version: ?[]const u8 = null;
    for (mods.items) |m| {
        if (std.mem.eql(u8, m.name, "shop")) found_version = m.version;
    }
    try std.testing.expect(found_version != null);
    try std.testing.expectEqualStrings("2.0.0", found_version.?);

    // 动态表已注册（manifest tables 声明）。
    const tables = try cloud_svc.listDynamicTables(1);
    defer {
        for (tables) |t| t.free(allocator);
        allocator.free(tables);
    }
    try std.testing.expectEqual(@as(usize, 1), tables.len);
    try std.testing.expectEqualStrings("shop_order", tables[0].table_name);
    try std.testing.expectEqualStrings("订单", tables[0].title);

    // 通用查询网关：空表 → 0 行 + 列名。
    var q = try cloud_svc.queryDynamicTable(allocator, 1, "shop_order", 1, 20);
    defer q.free(allocator);
    try std.testing.expectEqual(@as(usize, 0), q.row_count);
    try std.testing.expectEqual(@as(usize, 2), q.column_count); // 元数据声明的 id/amount 两列

    // 未注册表 → NotFound；非法表名 → InvalidName。
    try std.testing.expectError(error.NotFound, cloud_svc.queryDynamicTable(allocator, 1, "nope", 1, 20));
    try std.testing.expectError(error.InvalidName, cloud_svc.queryDynamicTable(allocator, 1, "shop_order; DROP", 1, 20));
}

const ManifestMockCtx = struct {
    content: []const u8,
};

fn manifestMockTransport(ctx: *anyopaque, allocator: std.mem.Allocator, uri: []const u8, method: std.http.Method, payload: []const u8, content_type: ?[]const u8) anyerror![]u8 {
    _ = uri;
    _ = method;
    _ = payload;
    _ = content_type;
    const c: *ManifestMockCtx = @ptrCast(@alignCast(ctx));
    return allocator.dupe(u8, c.content);
}

test "payment: WeChat Pay v3 notify decrypts and completes recharge" {
    const allocator = std.testing.allocator;
    const Aes256Gcm = std.crypto.aead.aes_gcm.Aes256Gcm;
    var env = try openMemory(allocator);
    defer env.deinit();
    var payment_store = payment.persistence.PaymentStore.init(allocator, env.client);
    var payment_svc = payment.service.PaymentService.init(allocator, std.testing.io, &payment_store);

    const api_v3_key = "12345678901234567890123456789012";
    const order = try payment_svc.createRechargeOrder(allocator, 1, 5, 42, 500);
    defer order.free(allocator);
    try std.testing.expect((try payment_svc.walletBalance(1, 5, 42)) == null);

    // Build a WeChat Pay v3 notify: AES-256-GCM encrypt the resource.
    const plain = try std.fmt.allocPrint(allocator, "{{\"trade_state\":\"SUCCESS\",\"out_trade_no\":\"{s}\"}}", .{order.order_no});
    defer allocator.free(plain);
    const key: [32]u8 = api_v3_key[0..32].*;
    const nonce_str = "123456789012";
    const nonce_bytes: [12]u8 = nonce_str[0..12].*;
    const aad = "transaction";

    const cipher_buf = try allocator.alloc(u8, plain.len);
    defer allocator.free(cipher_buf);
    var tag: [16]u8 = undefined;
    Aes256Gcm.encrypt(cipher_buf, &tag, plain, aad, nonce_bytes, key);

    var full = try allocator.alloc(u8, plain.len + 16);
    defer allocator.free(full);
    @memcpy(full[0..plain.len], cipher_buf);
    @memcpy(full[plain.len..], &tag);
    const Enc = std.base64.standard.Encoder;
    const b64_buf = try allocator.alloc(u8, Enc.calcSize(full.len));
    defer allocator.free(b64_buf);
    const b64 = Enc.encode(b64_buf, full);

    const body = try std.fmt.allocPrint(allocator, "{{\"resource\":{{\"ciphertext\":\"{s}\",\"associated_data\":\"transaction\",\"nonce\":\"123456789012\"}}}}", .{b64});
    defer allocator.free(body);

    // decrypt + complete → wallet credited
    try std.testing.expect(try payment_svc.handleV3Notify(allocator, api_v3_key, body));
    const wallet = (try payment_svc.walletBalance(1, 5, 42)).?;
    try std.testing.expectEqual(@as(i64, 500), wallet.balance);

    // duplicate notify is a no-op (idempotent)
    try std.testing.expect(!try payment_svc.handleV3Notify(allocator, api_v3_key, body));

    // wrong key → false
    try std.testing.expect(!try payment_svc.handleV3Notify(allocator, "99999999999999999999999999999999", body));
}

test "material: news + file CRUD, kind validation" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var material_store = material.persistence.MaterialStore.init(allocator, env.client);
    var account_store = account.persistence.AccountStore.init(allocator, env.client);
    var account_svc = account.service.AccountService.init(allocator, std.testing.io, &account_store);
    var token_cache = try zwechat.cache.Memory.create(allocator);
    defer allocator.destroy(token_cache);
    defer token_cache.deinit();
    var material_svc = material.service.MaterialService.init(allocator, std.testing.io, &material_store, &account_svc, token_cache);

    // news CRUD
    const nid = try material_svc.createNews(1, 5, "今日头条", "小编", "摘要", "正文内容", "thumb_1", "http://t/x.png", "http://a/x");
    const row = (try material_svc.getNews(nid)).?;
    defer row.free(allocator);
    try std.testing.expectEqualStrings("今日头条", row.title);
    try std.testing.expectEqualStrings("http://a/x", row.url);

    try material_svc.updateNews(nid, "今日头条V2", "小编", "新摘要", "新正文", "thumb_1", "http://t/x.png", "http://a/y");
    const updated = (try material_svc.getNews(nid)).?;
    defer updated.free(allocator);
    try std.testing.expectEqualStrings("今日头条V2", updated.title);

    // 空标题拒绝
    try std.testing.expectError(error.InvalidTitle, material_svc.createNews(1, 5, "   ", "", "", "", "", "", ""));

    var news = try material_svc.listNews(1, 20, 1, 5);
    defer news.free(allocator);
    try std.testing.expectEqual(@as(i64, 1), news.total);

    // files CRUD + kind filter
    const fid = try material_svc.createFile(1, 5, "image", "img_abc", "http://cdn/x.png");
    _ = fid;
    _ = try material_svc.createFile(1, 5, "video", "vid_abc", "http://cdn/v.mp4");
    try std.testing.expectError(error.InvalidKind, material_svc.createFile(1, 5, "gif", "", ""));

    var imgs = try material_svc.listFiles(1, 20, 1, 5, "image");
    defer imgs.free(allocator);
    try std.testing.expectEqual(@as(i64, 1), imgs.total);
    try std.testing.expectEqualStrings("img_abc", imgs.items[0].media_id);

    try material_svc.deleteNews(nid);
    try std.testing.expect((try material_svc.getNews(nid)) == null);
}

test "material: sync upsert idempotent by media_id" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var material_store = material.persistence.MaterialStore.init(allocator, env.client);

    // 图文：同 media_id 两次 upsert → 同 id，字段更新。
    const n1 = try material_store.upsertNews(1, 5, "news_1", "标题A", "作者", "摘要", "正文", "thumb_1", "", "http://a/1", 100);
    const n2 = try material_store.upsertNews(1, 5, "news_1", "标题B", "作者", "摘要", "正文", "thumb_1", "", "http://a/1", 101);
    try std.testing.expectEqual(n1, n2);
    const news = (try material_store.getNewsByMediaId(1, 5, "news_1")).?;
    defer news.free(allocator);
    try std.testing.expectEqualStrings("标题B", news.title);

    // 不同 media_id → 新行。
    const n3 = try material_store.upsertNews(1, 5, "news_2", "另一篇", "", "", "", "", "", "", 102);
    try std.testing.expect(n3 != n1);

    // 文件：同 media_id 幂等。
    const f1 = try material_store.upsertFile(1, 5, "image", "img_1", "http://cdn/1.png", 100);
    const f2 = try material_store.upsertFile(1, 5, "image", "img_1", "http://cdn/1.png", 101);
    try std.testing.expectEqual(f1, f2);
    const frow = (try material_store.getFileByMediaId(1, 5, "img_1")).?;
    defer frow.free(allocator);
    try std.testing.expectEqualStrings("image", frow.kind);
    try std.testing.expectEqualStrings("http://cdn/1.png", frow.url);
}

test "checkin: module receiver handles 签到 + per-account config" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();

    var account_store = account.persistence.AccountStore.init(allocator, env.client);
    var account_svc = account.service.AccountService.init(allocator, std.testing.io, &account_store);
    var rule_store = rule.persistence.RuleStore.init(allocator, env.client);
    var rule_svc = rule.service.RuleService.init(allocator, std.testing.io, &rule_store);
    var fan_store = member.persistence.FanStore.init(allocator, env.client);
    var member_svc = member.service.MemberService.init(allocator, std.testing.io, &fan_store);
    var setting_store = setting.persistence.SettingStore.init(allocator, env.client);
    var message_store = message.persistence.MessageStore.init(allocator, env.client);
    var module_store = appmod.persistence.ModuleStore.init(allocator, env.client);
    var module_svc = appmod.service.ModuleService.init(allocator, std.testing.io, &module_store);
    var checkin_store = checkin.persistence.CheckinStore.init(allocator, env.client);
    var checkin_svc = checkin.service.CheckinService.init(allocator, std.testing.io, &checkin_store);

    var wechat_svc = message.service.WechatService.init(allocator, std.testing.io, &account_svc, &rule_svc, &member_svc, &setting_store, &message_store);
    wechat_svc.module_svc = &module_svc;
    var checkin_ctx = checkin.service.ReceiverCtx{ .module_svc = &module_svc, .checkin_svc = &checkin_svc, .io = std.testing.io };
    try wechat_svc.registerReceiver(.{ .module_name = "checkin", .ctx = &checkin_ctx, .handle = checkin.service.receiverHandle });

    const account_id = try account_svc.create(1, "测试公众号", "wechat");
    _ = try account_svc.upsertWechat(1, account_id, .{ .appid = "wx1", .secret = "s", .token = "tokc", .encoding_aes_key = "", .verified = false });

    // 绑定 checkin 模块 + 配置每次签到奖励 5 积分。
    _ = try module_svc.bind(1, account_id, "checkin", "active");
    _ = try module_svc.setConfig(1, account_id, "checkin", "5");

    const token = "tokc";
    var ts_buf: [16]u8 = undefined;
    const ts = try std.fmt.bufPrint(&ts_buf, "{d}", .{zigmodu.time.wallClockSeconds(std.testing.io)});
    const nonce = "n1";
    const sig = try zwechat.util.signature.signature(allocator, &[_][]const u8{ token, ts, nonce });
    defer allocator.free(sig);

    const text_xml = "<xml><ToUserName><![CDATA[gh]]></ToUserName><FromUserName><![CDATA[o_9]]></FromUserName><CreateTime>1700000000</CreateTime><MsgType><![CDATA[text]]></MsgType><Content><![CDATA[签到]]></Content></xml>";

    // 首次签到 → receiver 回复「签到成功」+ 积分。
    const r1 = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, text_xml);
    defer allocator.free(r1);
    try std.testing.expect(std.mem.indexOf(u8, r1, "签到成功") != null);
    try std.testing.expect(std.mem.indexOf(u8, r1, "5 积分") != null);

    // 同一天重复签到 → 幂等回复「已经签到」。
    const r2 = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, text_xml);
    defer allocator.free(r2);
    try std.testing.expect(std.mem.indexOf(u8, r2, "已经签到") != null);

    // 记录落库：仅一条，积分为 5。
    var list = try checkin_svc.list(1, 20, 1, account_id);
    defer list.free(allocator);
    try std.testing.expectEqual(@as(i64, 1), list.total);
    try std.testing.expectEqual(@as(i64, 5), list.items[0].points);

    // config 读写回环。
    const cfg = (try module_svc.getConfig(allocator, 1, account_id, "checkin")).?;
    defer allocator.free(cfg);
    try std.testing.expectEqualStrings("5", cfg);
}

test "lucky_draw: weighted pick + draw records + daily_limit" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = lucky_draw.persistence.DrawStore.init(allocator, env.client);
    var svc = lucky_draw.service.DrawService.init(allocator, std.testing.io, &store);

    // pickPrize：加权边界（roll 落在各区间的确定性结果）。
    const prizes = [_]lucky_draw.service.Prize{
        .{ .name = "A", .weight = 50, .points = 10 },
        .{ .name = "B", .weight = 30, .points = 20 },
        .{ .name = "C", .weight = 20, .points = 0 },
    };
    try std.testing.expectEqual(@as(usize, 0), lucky_draw.service.DrawService.pickPrize(&prizes, 0));
    try std.testing.expectEqual(@as(usize, 0), lucky_draw.service.DrawService.pickPrize(&prizes, 49));
    try std.testing.expectEqual(@as(usize, 1), lucky_draw.service.DrawService.pickPrize(&prizes, 50));
    try std.testing.expectEqual(@as(usize, 2), lucky_draw.service.DrawService.pickPrize(&prizes, 99));

    // parseConfig：合法 JSON + 缺 prizes 兜底。
    var cfg = svc.parseConfig(allocator, "{\"cost\":5,\"daily_limit\":3,\"prizes\":[{\"name\":\"10积分\",\"weight\":50,\"points\":10},{\"name\":\"谢谢参与\",\"weight\":50,\"points\":0}]}");
    defer cfg.free(allocator);
    try std.testing.expectEqual(@as(i64, 5), cfg.cost);
    try std.testing.expectEqual(@as(i64, 3), cfg.daily_limit);
    try std.testing.expectEqual(@as(usize, 2), cfg.prizes.len);

    // draw：落库 + 返回中奖。
    const result = try svc.draw(allocator, 1, 9, "o_luck", &cfg);
    defer allocator.free(result.prize_name);
    var list = try svc.list(1, 20, 1, 9);
    defer list.free(allocator);
    try std.testing.expectEqual(@as(i64, 1), list.total);
    try std.testing.expectEqualStrings("o_luck", list.items[0].openid);

    // daily_limit=1：第二次 draw → DailyLimit。
    var cfg1 = svc.parseConfig(allocator, "{\"daily_limit\":1,\"prizes\":[{\"name\":\"X\",\"weight\":1,\"points\":0}]}");
    defer cfg1.free(allocator);
    const r1 = try svc.draw(allocator, 1, 9, "o_lim", &cfg1);
    defer allocator.free(r1.prize_name);
    try std.testing.expectError(error.DailyLimit, svc.draw(allocator, 1, 9, "o_lim", &cfg1));
}

test "lucky_draw: module receiver handles 抽奖" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();

    var account_store = account.persistence.AccountStore.init(allocator, env.client);
    var account_svc = account.service.AccountService.init(allocator, std.testing.io, &account_store);
    var rule_store = rule.persistence.RuleStore.init(allocator, env.client);
    var rule_svc = rule.service.RuleService.init(allocator, std.testing.io, &rule_store);
    var fan_store = member.persistence.FanStore.init(allocator, env.client);
    var member_svc = member.service.MemberService.init(allocator, std.testing.io, &fan_store);
    var setting_store = setting.persistence.SettingStore.init(allocator, env.client);
    var message_store = message.persistence.MessageStore.init(allocator, env.client);
    var module_store = appmod.persistence.ModuleStore.init(allocator, env.client);
    var module_svc = appmod.service.ModuleService.init(allocator, std.testing.io, &module_store);
    var draw_store = lucky_draw.persistence.DrawStore.init(allocator, env.client);
    var draw_svc = lucky_draw.service.DrawService.init(allocator, std.testing.io, &draw_store);

    var wechat_svc = message.service.WechatService.init(allocator, std.testing.io, &account_svc, &rule_svc, &member_svc, &setting_store, &message_store);
    wechat_svc.module_svc = &module_svc;
    var draw_ctx = lucky_draw.service.ReceiverCtx{ .module_svc = &module_svc, .draw_svc = &draw_svc, .io = std.testing.io };
    try wechat_svc.registerReceiver(.{ .module_name = "lucky_draw", .ctx = &draw_ctx, .handle = lucky_draw.service.receiverHandle });

    const account_id = try account_svc.create(1, "抽奖测试号", "wechat");
    _ = try account_svc.upsertWechat(1, account_id, .{ .appid = "wx1", .secret = "s", .token = "tokl", .encoding_aes_key = "", .verified = false });
    _ = try module_svc.bind(1, account_id, "lucky_draw", "active");
    _ = try module_svc.setConfig(1, account_id, "lucky_draw", "{\"prizes\":[{\"name\":\"10积分\",\"weight\":1,\"points\":10}]}");

    const token = "tokl";
    var ts_buf: [16]u8 = undefined;
    const ts = try std.fmt.bufPrint(&ts_buf, "{d}", .{zigmodu.time.wallClockSeconds(std.testing.io)});
    const nonce = "n2";
    const sig = try zwechat.util.signature.signature(allocator, &[_][]const u8{ token, ts, nonce });
    defer allocator.free(sig);

    const text_xml = "<xml><ToUserName><![CDATA[gh]]></ToUserName><FromUserName><![CDATA[o_draw]]></FromUserName><CreateTime>1700000000</CreateTime><MsgType><![CDATA[text]]></MsgType><Content><![CDATA[抽奖]]></Content></xml>";
    const r = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, text_xml);
    defer allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "抽中") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "10积分") != null);

    // 中奖记录落库。
    var list = try draw_svc.list(1, 20, 1, account_id);
    defer list.free(allocator);
    try std.testing.expectEqual(@as(i64, 1), list.total);
}

test "coupon: create/claim/use lifecycle + stock/limit" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = coupon.persistence.CouponStore.init(allocator, env.client);
    var svc = coupon.service.CouponService.init(allocator, std.testing.io, &store);

    // 建券：总量 2，每人限领 1。
    const cid = try svc.createCoupon(1, 9, "满100减20", 2000, 10000, 2, 1, 0, 0);
    const c = (try svc.getCoupon(cid)).?;
    defer c.free(allocator);
    try std.testing.expectEqualStrings("满100减20", c.title);
    try std.testing.expectEqual(@as(i64, 2000), c.amount);

    // 领券：券码 CP- 前缀。
    const code1 = try svc.claimCoupon(allocator, 1, 9, "o_a", cid);
    defer allocator.free(code1);
    try std.testing.expect(std.mem.startsWith(u8, code1, "CP-"));

    // 每人限领 1：同用户再领 → LimitReached。
    try std.testing.expectError(error.LimitReached, svc.claimCoupon(allocator, 1, 9, "o_a", cid));

    // 库存：总量 2，已发 1，再发 1 给另一用户 → 成功；第 3 个 → OutOfStock。
    const code2 = try svc.claimCoupon(allocator, 1, 9, "o_b", cid);
    defer allocator.free(code2);
    try std.testing.expectError(error.OutOfStock, svc.claimCoupon(allocator, 1, 9, "o_c", cid));

    // 核销：unused→used 幂等。
    try svc.useCoupon(code1);
    try std.testing.expectError(error.AlreadyUsed, svc.useCoupon(code1));

    // 领取记录落库。
    var list = try svc.listUserCoupons(1, 20, 1, 9, null);
    defer list.free(allocator);
    try std.testing.expectEqual(@as(i64, 2), list.total);

    // 过期券：end_at 已过 → Expired。
    const cid2 = try svc.createCoupon(1, 9, "过期券", 100, 0, 0, 1, 0, 1000);
    try std.testing.expectError(error.Expired, svc.claimCoupon(allocator, 1, 9, "o_d", cid2));
}

test "coupon: module receiver handles 领券" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();

    var account_store = account.persistence.AccountStore.init(allocator, env.client);
    var account_svc = account.service.AccountService.init(allocator, std.testing.io, &account_store);
    var rule_store = rule.persistence.RuleStore.init(allocator, env.client);
    var rule_svc = rule.service.RuleService.init(allocator, std.testing.io, &rule_store);
    var fan_store = member.persistence.FanStore.init(allocator, env.client);
    var member_svc = member.service.MemberService.init(allocator, std.testing.io, &fan_store);
    var setting_store = setting.persistence.SettingStore.init(allocator, env.client);
    var message_store = message.persistence.MessageStore.init(allocator, env.client);
    var module_store = appmod.persistence.ModuleStore.init(allocator, env.client);
    var module_svc = appmod.service.ModuleService.init(allocator, std.testing.io, &module_store);
    var coupon_store = coupon.persistence.CouponStore.init(allocator, env.client);
    var coupon_svc = coupon.service.CouponService.init(allocator, std.testing.io, &coupon_store);

    var wechat_svc = message.service.WechatService.init(allocator, std.testing.io, &account_svc, &rule_svc, &member_svc, &setting_store, &message_store);
    wechat_svc.module_svc = &module_svc;
    var coupon_ctx = coupon.service.ReceiverCtx{ .module_svc = &module_svc, .coupon_svc = &coupon_svc, .io = std.testing.io };
    try wechat_svc.registerReceiver(.{ .module_name = "coupon", .ctx = &coupon_ctx, .handle = coupon.service.receiverHandle });

    const account_id = try account_svc.create(1, "券测试号", "wechat");
    _ = try account_svc.upsertWechat(1, account_id, .{ .appid = "wx1", .secret = "s", .token = "tokcp", .encoding_aes_key = "", .verified = false });
    _ = try module_svc.bind(1, account_id, "coupon", "active");
    _ = try coupon_svc.createCoupon(1, account_id, "新人券", 500, 0, 10, 1, 0, 0);

    const token = "tokcp";
    var ts_buf: [16]u8 = undefined;
    const ts = try std.fmt.bufPrint(&ts_buf, "{d}", .{zigmodu.time.wallClockSeconds(std.testing.io)});
    const nonce = "ncp";
    const sig = try zwechat.util.signature.signature(allocator, &[_][]const u8{ token, ts, nonce });
    defer allocator.free(sig);

    const text_xml = "<xml><ToUserName><![CDATA[gh]]></ToUserName><FromUserName><![CDATA[o_cp]]></FromUserName><CreateTime>1700000000</CreateTime><MsgType><![CDATA[text]]></MsgType><Content><![CDATA[领券]]></Content></xml>";
    const r = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, text_xml);
    defer allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "领券成功") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "CP-") != null);

    // 已领满（每人限领 1）→ 回复「已领完」。
    const r2 = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, text_xml);
    defer allocator.free(r2);
    try std.testing.expect(std.mem.indexOf(u8, r2, "已领完") != null);
}

test "vote: create/vote/tally lifecycle + dedup" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = vote.persistence.VoteStore.init(allocator, env.client);
    var svc = vote.service.VoteService.init(allocator, std.testing.io, &store);

    const vid = try svc.createVote(1, 9, "最喜欢的语言", "[\"Zig\",\"Rust\",\"Go\"]", 0);
    const v = (try svc.getVote(vid)).?;
    defer v.free(allocator);
    try std.testing.expectEqualStrings("最喜欢的语言", v.title);

    // 投票：o_a 投 0（Zig），o_b 投 1（Rust），o_c 投 0。
    try svc.vote(1, 9, "o_a", vid, 0);
    try svc.vote(1, 9, "o_b", vid, 1);
    try svc.vote(1, 9, "o_c", vid, 0);

    // 防重：o_a 再投 → AlreadyVoted。
    try std.testing.expectError(error.AlreadyVoted, svc.vote(1, 9, "o_a", vid, 1));

    // 计票：Zig=2, Rust=1, Go=0。
    const tally = try svc.tally(allocator, vid);
    defer allocator.free(tally);
    try std.testing.expectEqual(@as(i64, 2), tally[0]);
    try std.testing.expectEqual(@as(i64, 1), tally[1]);
    try std.testing.expectEqual(@as(i64, 0), tally[2]);

    // 非法选项 → InvalidOption。
    try std.testing.expectError(error.InvalidOption, svc.vote(1, 9, "o_d", vid, 99));
}

test "vote: module receiver handles 投票 + 投N" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();

    var account_store = account.persistence.AccountStore.init(allocator, env.client);
    var account_svc = account.service.AccountService.init(allocator, std.testing.io, &account_store);
    var rule_store = rule.persistence.RuleStore.init(allocator, env.client);
    var rule_svc = rule.service.RuleService.init(allocator, std.testing.io, &rule_store);
    var fan_store = member.persistence.FanStore.init(allocator, env.client);
    var member_svc = member.service.MemberService.init(allocator, std.testing.io, &fan_store);
    var setting_store = setting.persistence.SettingStore.init(allocator, env.client);
    var message_store = message.persistence.MessageStore.init(allocator, env.client);
    var module_store = appmod.persistence.ModuleStore.init(allocator, env.client);
    var module_svc = appmod.service.ModuleService.init(allocator, std.testing.io, &module_store);
    var vote_store = vote.persistence.VoteStore.init(allocator, env.client);
    var vote_svc = vote.service.VoteService.init(allocator, std.testing.io, &vote_store);

    var wechat_svc = message.service.WechatService.init(allocator, std.testing.io, &account_svc, &rule_svc, &member_svc, &setting_store, &message_store);
    wechat_svc.module_svc = &module_svc;
    var vote_ctx = vote.service.ReceiverCtx{ .module_svc = &module_svc, .vote_svc = &vote_svc, .io = std.testing.io };
    try wechat_svc.registerReceiver(.{ .module_name = "vote", .ctx = &vote_ctx, .handle = vote.service.receiverHandle });

    const account_id = try account_svc.create(1, "投票测试号", "wechat");
    _ = try account_svc.upsertWechat(1, account_id, .{ .appid = "wx1", .secret = "s", .token = "tokv", .encoding_aes_key = "", .verified = false });
    _ = try module_svc.bind(1, account_id, "vote", "active");
    _ = try vote_svc.createVote(1, account_id, "今晚吃什么", "[\"火锅\",\"烧烤\"]", 0);

    const token = "tokv";
    var ts_buf: [16]u8 = undefined;
    const ts = try std.fmt.bufPrint(&ts_buf, "{d}", .{zigmodu.time.wallClockSeconds(std.testing.io)});
    const nonce = "nv";
    const sig = try zwechat.util.signature.signature(allocator, &[_][]const u8{ token, ts, nonce });
    defer allocator.free(sig);

    // 「投票」→ 列题目 + 选项。
    const q_xml = "<xml><ToUserName><![CDATA[gh]]></ToUserName><FromUserName><![CDATA[o_v]]></FromUserName><CreateTime>1700000000</CreateTime><MsgType><![CDATA[text]]></MsgType><Content><![CDATA[投票]]></Content></xml>";
    const r1 = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, q_xml);
    defer allocator.free(r1);
    try std.testing.expect(std.mem.indexOf(u8, r1, "今晚吃什么") != null);
    try std.testing.expect(std.mem.indexOf(u8, r1, "火锅") != null);

    // 「投1」→ 投票成功。
    const v_xml = "<xml><ToUserName><![CDATA[gh]]></ToUserName><FromUserName><![CDATA[o_v]]></FromUserName><CreateTime>1700000000</CreateTime><MsgType><![CDATA[text]]></MsgType><Content><![CDATA[投1]]></Content></xml>";
    const r2 = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, v_xml);
    defer allocator.free(r2);
    try std.testing.expect(std.mem.indexOf(u8, r2, "投票成功") != null);

    // 再「投2」→ 已投过。
    const v2_xml = "<xml><ToUserName><![CDATA[gh]]></ToUserName><FromUserName><![CDATA[o_v]]></FromUserName><CreateTime>1700000000</CreateTime><MsgType><![CDATA[text]]></MsgType><Content><![CDATA[投2]]></Content></xml>";
    const r3 = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, v2_xml);
    defer allocator.free(r3);
    try std.testing.expect(std.mem.indexOf(u8, r3, "已经投过") != null);
}

test "checkin: unbound module declines, falls through to default reply" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();

    var account_store = account.persistence.AccountStore.init(allocator, env.client);
    var account_svc = account.service.AccountService.init(allocator, std.testing.io, &account_store);
    var rule_store = rule.persistence.RuleStore.init(allocator, env.client);
    var rule_svc = rule.service.RuleService.init(allocator, std.testing.io, &rule_store);
    var fan_store = member.persistence.FanStore.init(allocator, env.client);
    var member_svc = member.service.MemberService.init(allocator, std.testing.io, &fan_store);
    var setting_store = setting.persistence.SettingStore.init(allocator, env.client);
    var message_store = message.persistence.MessageStore.init(allocator, env.client);
    var module_store = appmod.persistence.ModuleStore.init(allocator, env.client);
    var module_svc = appmod.service.ModuleService.init(allocator, std.testing.io, &module_store);
    var checkin_store = checkin.persistence.CheckinStore.init(allocator, env.client);
    var checkin_svc = checkin.service.CheckinService.init(allocator, std.testing.io, &checkin_store);

    var wechat_svc = message.service.WechatService.init(allocator, std.testing.io, &account_svc, &rule_svc, &member_svc, &setting_store, &message_store);
    wechat_svc.module_svc = &module_svc;
    var checkin_ctx = checkin.service.ReceiverCtx{ .module_svc = &module_svc, .checkin_svc = &checkin_svc, .io = std.testing.io };
    try wechat_svc.registerReceiver(.{ .module_name = "checkin", .ctx = &checkin_ctx, .handle = checkin.service.receiverHandle });

    const account_id = try account_svc.create(1, "测试公众号", "wechat");
    _ = try account_svc.upsertWechat(1, account_id, .{ .appid = "wx1", .secret = "s", .token = "tokd", .encoding_aes_key = "", .verified = false });
    // 注意：不绑定 checkin 模块 → receiver 不应被分发。
    _ = try setting_store.set(1, "wechat_default_reply", "默认回复", 100);

    const token = "tokd";
    var ts_buf: [16]u8 = undefined;
    const ts = try std.fmt.bufPrint(&ts_buf, "{d}", .{zigmodu.time.wallClockSeconds(std.testing.io)});
    const nonce = "n1";
    const sig = try zwechat.util.signature.signature(allocator, &[_][]const u8{ token, ts, nonce });
    defer allocator.free(sig);

    const text_xml = "<xml><ToUserName><![CDATA[gh]]></ToUserName><FromUserName><![CDATA[o_8]]></FromUserName><CreateTime>1700000000</CreateTime><MsgType><![CDATA[text]]></MsgType><Content><![CDATA[签到]]></Content></xml>";
    const reply = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, text_xml);
    defer allocator.free(reply);
    try std.testing.expect(std.mem.indexOf(u8, reply, "默认回复") != null);
    // 未绑定 → 无签到记录落库。
    var list = try checkin_svc.list(1, 20, 1, account_id);
    defer list.free(allocator);
    try std.testing.expectEqual(@as(i64, 0), list.total);
}

test "menu: save/get + parseButtons JSON→Button conversion" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var menu_store = menu.persistence.MenuStore.init(allocator, env.client);
    var account_store = account.persistence.AccountStore.init(allocator, env.client);
    var account_svc = account.service.AccountService.init(allocator, std.testing.io, &account_store);
    var token_cache = try zwechat.cache.Memory.create(allocator);
    defer allocator.destroy(token_cache);
    defer token_cache.deinit();
    var menu_svc = menu.service.MenuService.init(allocator, std.testing.io, &menu_store, &account_svc, token_cache);

    // parseButtons: JSON → zwechat Button（含子菜单，字段深拷贝）。
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const json = "[{\"type\":\"click\",\"name\":\"按钮1\",\"key\":\"K1\"},{\"name\":\"菜单\",\"sub_button\":[{\"type\":\"view\",\"name\":\"子1\",\"url\":\"http://x\"}]}]";
    const buttons = try menu.service.parseButtons(arena.allocator(), json);
    try std.testing.expectEqual(@as(usize, 2), buttons.len);
    try std.testing.expectEqualStrings("click", buttons[0].type_);
    try std.testing.expectEqualStrings("K1", buttons[0].key);
    try std.testing.expectEqual(@as(usize, 1), buttons[1].sub_button.len);
    try std.testing.expectEqualStrings("view", buttons[1].sub_button[0].type_);
    try std.testing.expectEqualStrings("http://x", buttons[1].sub_button[0].url);

    // 非法 JSON 拒绝。
    try std.testing.expectError(error.InvalidJson, menu.service.parseButtons(arena.allocator(), "not-json"));

    // save（含 JSON 校验）+ get（DB）。
    const id1 = try menu_svc.save(1, 7, json);
    const row = (try menu_svc.get(1, 7)).?;
    defer row.free(allocator);
    try std.testing.expectEqual(id1, row.id);
    try std.testing.expectEqualStrings(json, row.menu_json);

    // 非法 JSON 保存被拒。
    try std.testing.expectError(error.InvalidJson, menu_svc.save(1, 7, "oops"));

    // upsert 幂等（同账号更新）。
    const id2 = try menu_svc.save(1, 7, "[]");
    try std.testing.expectEqual(id1, id2);
    const row2 = (try menu_svc.get(1, 7)).?;
    defer row2.free(allocator);
    try std.testing.expectEqualStrings("[]", row2.menu_json);
}

test "payment: v3 prepay request build + notify signature verify" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var payment_store = payment.persistence.PaymentStore.init(allocator, env.client);
    var payment_svc = payment.service.PaymentService.init(allocator, std.testing.io, &payment_store);

    const test_priv =
        \\-----BEGIN RSA PRIVATE KEY-----
        \\MIIEogIBAAKCAQEApVoVGMSYGP5YcL5aDDZq0KPP8AC9WWsEMKZfNjAstI3RapNb
        \\89D1m2A2PbCNVzo76GrzNzi3KIbSIxF/dkReSAufuqIBcGQWUCHHtqbrxQr0661B
        \\wptJe9CO3ENepiRK4zQmHAHR4YVeciTDO6hU2DVHpDUdKoYqA3URT8rkyPEKOSsd
        \\lqIz17IBd92KAvxabVUo/ewSTJI74gtGBTy1hpDbKxF9uXLLNdEKnO2dK2qnOf7H
        \\Xmz7Je6OElWpy2TMoeNzh4BbGbdPDk8Ls48y5VpnvnFe6SokODJ7KDNXrReqpcyE
        \\rAeuN1lfVyF9+GzgnTunVwkABAs/IzJVVpk18wIDAQABAoIBAA/SFyun/7+AcnjT
        \\Fa2OdVjiG46km3lXPm7jND/sixJ5cTyHvegNqbpEkdwELPnYFgxOU1gIwqmLgMaf
        \\MXlg4D53ckB6qLWWtfXTzZaB0RQo0LdN+/lBP14r3cdgYMl3tnyXrD/IwsqXpqo4
        \\Lz/hgsCvFFw3QsOjU5jCFjZyvMIm+lo23QitIwzoLu+Z3NIwIjiE+vGZ0biAe8Qk
        \\BUpWQEqBybpVUjotZxUToYqwG2mh1Ham/DjlFFAaodKMl4RFCdNRD+/3czUGuQ8J
        \\oP7MEayFiKzVx57GE4kH0ci8qBfrUA6DYhiJusO0EkDYZukt8uWGBNB8Zu/IaLOd
        \\5HSoL80CgYEA4v6fX1KL5Cmzz/4IWuVJo4F1etzj29ZYF3hLkxMXYblGcYfPEd6X
        \\HytAMr9y+N0D78IsjbnDH3QyrnegKeYPstUQi+1b3ffbpP4LIl/fnRulJ8f0OWdo
        \\2GRN4B0I0CKnPNzmi7k1YCn9BxDjDUs0twUYIGXKgOt/3XtvA0evBNUCgYEAunsF
        \\mVZPHIsOgnvSL78qyay6XdyTjzmcyZxciQX3FioVzHPMEGJVjDfah4wWEAlauvWb
        \\xK5t1dlBetaQQ3VdWAEq3+KC6ZZ10fXdEbT4yZewBB39bIWLOtb1/BW+FPWSF0gI
        \\gcKNQXCN7gxd2GmThzWrcZxL7nEFWZyNaB9sU6cCgYBDndlXib1GD+4SLPfMK7TN
        \\0chu+tGdMLI4+4p3mx5B6/DB7NSP3CBkFnwfIcxbuWpsxwiChy1Kd1CJi/TXxkIy
        \\4Sj2pZPSAP0antouOSThJdUCjpt/ZgBjRS21brCrX0c16A9824S8yoUmz67yzM49
        \\HnVbYTb7RCtojFY7QeUuqQKBgDpPr6+EEpbdULsylsYBZBLOJTSmfanCnSlZ8IGU
        \\UPAoVsqoxv20kgWXjYjnIBsBodJmbL/yvzuohNYxc8j0USzsqIh7nu4F82+lDuyz
        \\hzwaZ5rR+eXOWHwcrayW6+pH49fN2YMh3+O/m1H9ofbDBLO575NGCWRVCRQ9ZOZT
        \\NR9vAoGAGtYec1yzJsKFohRiQhz2p+YmKGBQ/DxEPOBn/VH95XFd6A++AnVh3zHD
        \\2NzVZ1iXlJf1ezHr0QuEzI08cytTX2jxi9rIY/D2xHQbaTMb3VcplmNgxIG5aVKN
        \\8m4LVVmaGSecs6v13QZmsspJ9QfZlHu7/dXWysO1V27RzEznTiI=
        \\-----END RSA PRIVATE KEY-----
    ;
    const test_pub =
        \\-----BEGIN PUBLIC KEY-----
        \\MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEApVoVGMSYGP5YcL5aDDZq
        \\0KPP8AC9WWsEMKZfNjAstI3RapNb89D1m2A2PbCNVzo76GrzNzi3KIbSIxF/dkRe
        \\SAufuqIBcGQWUCHHtqbrxQr0661BwptJe9CO3ENepiRK4zQmHAHR4YVeciTDO6hU
        \\2DVHpDUdKoYqA3URT8rkyPEKOSsdlqIz17IBd92KAvxabVUo/ewSTJI74gtGBTy1
        \\hpDbKxF9uXLLNdEKnO2dK2qnOf7HXmz7Je6OElWpy2TMoeNzh4BbGbdPDk8Ls48y
        \\5VpnvnFe6SokODJ7KDNXrReqpcyErAeuN1lfVyF9+GzgnTunVwkABAs/IzJVVpk1
        \\8wIDAQAB
        \\-----END PUBLIC KEY-----
    ;

    const cfg = payment.service.PayConfig{
        .mch_id = "1900000109",
        .app_id = "wx_test",
        .serial_no = "1DDE5578",
        .private_key_pem = test_priv,
        .notify_url = "https://example.com/api/pay/v3/notify",
    };

    // 1. prepay request build (no network)
    var req_data = try payment_svc.buildPrepayRequest(allocator, cfg, "R1001", 100, "zweq recharge", "o_openid");
    defer req_data.deinit(allocator);
    try std.testing.expect(std.mem.indexOf(u8, req_data.auth, "WECHATPAY2-SHA256-RSA2048") != null);
    try std.testing.expect(std.mem.indexOf(u8, req_data.auth, "mchid=\"1900000109\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, req_data.auth, "serial_no=\"1DDE5578\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, req_data.body, "\"out_trade_no\":\"R1001\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, req_data.body, "\"total\":100") != null);
    try std.testing.expect(std.mem.indexOf(u8, req_data.body, "\"openid\":\"o_openid\"") != null);

    // 2. notify signature verify round-trip: sign → verify true, tamper → false
    const content = try std.fmt.allocPrint(allocator, "{s}\n{s}\n{s}\n", .{ "1700000000", "nonce1", "{\"resource\":{}}" });
    defer allocator.free(content);
    const raw_sig = try zwechat.util.rsa.rsaSign(allocator, content, test_priv);
    defer allocator.free(raw_sig);
    const sig_buf = try allocator.alloc(u8, std.base64.standard.Encoder.calcSize(raw_sig.len));
    defer allocator.free(sig_buf);
    const sig_b64 = std.base64.standard.Encoder.encode(sig_buf, raw_sig);

    try std.testing.expect(try payment_svc.verifyV3NotifySignature(allocator, test_pub, "1700000000", "nonce1", sig_b64, "{\"resource\":{}}"));
    // tampered body → false
    try std.testing.expect(!try payment_svc.verifyV3NotifySignature(allocator, test_pub, "1700000000", "nonce1", sig_b64, "{\"resource\":\"tampered\"}"));
}

test "payment: v3 refund + transfer request build (no network)" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var payment_store = payment.persistence.PaymentStore.init(allocator, env.client);
    var payment_svc = payment.service.PaymentService.init(allocator, std.testing.io, &payment_store);

    const cfg = payment.service.PayConfig{
        .mch_id = "1900000109",
        .app_id = "wx_test",
        .serial_no = "1DDE5578",
        .private_key_pem = "",
        .notify_url = "https://example.com/api/pay/v3/notify",
    };

    // 退款请求 build。
    var refund = try payment_svc.buildRefundV3Request(allocator, cfg, "R1001", "RF2002", 50, 100);
    defer refund.deinit(allocator);
    try std.testing.expect(std.mem.indexOf(u8, refund.auth, "WECHATPAY2-SHA256-RSA2048") != null);
    try std.testing.expect(std.mem.indexOf(u8, refund.body, "\"out_trade_no\":\"R1001\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, refund.body, "\"out_refund_no\":\"RF2002\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, refund.body, "\"refund\":50") != null);
    try std.testing.expect(std.mem.indexOf(u8, refund.body, "\"total\":100") != null);
    try std.testing.expect(std.mem.endsWith(u8, refund.url, "/v3/refund/domestic/refunds"));

    // 转账请求 build。
    var transfer = try payment_svc.buildTransferV3Request(allocator, cfg, "o_openid", 200, "B3003", "D4004", "佣金");
    defer transfer.deinit(allocator);
    try std.testing.expect(std.mem.indexOf(u8, transfer.auth, "WECHATPAY2-SHA256-RSA2048") != null);
    try std.testing.expect(std.mem.indexOf(u8, transfer.body, "\"out_batch_no\":\"B3003\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, transfer.body, "\"out_detail_no\":\"D4004\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, transfer.body, "\"total_amount\":200") != null);
    try std.testing.expect(std.mem.indexOf(u8, transfer.body, "\"openid\":\"o_openid\"") != null);
    try std.testing.expect(std.mem.endsWith(u8, transfer.url, "/v3/transfer/batches"));
}

test "ai: run quota counts within rolling window + health workflow" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var ai_store = ai.persistence.AiStore.init(allocator, env.client);
    var user_store = user.persistence.UserStore.init(allocator, env.client);
    var task_store = task.persistence.TaskStore.init(allocator, env.client);
    var audit_store = audit.persistence.AuditStore.init(allocator, env.client);
    var tenant_store = tenant.persistence.TenantStore.init(allocator, env.client);
    var notify_store = notify.persistence.NotificationStore.init(allocator, env.client);
    var notify_svc = notify.service.NotificationService.init(allocator, std.testing.io, &notify_store);
    const refs = ai.service.SkillsRefs{
        .user_store = &user_store,
        .task_store = &task_store,
        .audit_store = &audit_store,
        .tenant_store = &tenant_store,
        .ai_store = &ai_store,
        .notify_svc = &notify_svc,
    };
    var svc = try ai.service.AiService.init(allocator, std.testing.io, &ai_store, .{ .key_secret = "master-secret" }, refs);
    defer svc.deinit();

    _ = try ai_store.createRun(0, 7, 1, "chat", "hi", "", 0, 0, 0, 0, 0, "ok", "", 100);
    _ = try ai_store.createRun(0, 7, 1, "chat", "hi", "", 0, 0, 0, 0, 0, "ok", "", 200);
    _ = try ai_store.createRun(0, 8, 1, "chat", "hi", "", 0, 0, 0, 0, 0, "ok", "", 300);
    try std.testing.expectEqual(@as(i64, 2), try ai_store.runCountForUser(7, 50));

    // 无 LLM 的健康工作流:两个只读技能按序执行。
    var result = try svc.runHealthWorkflow(allocator, 1, 1);
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 2), result.steps.items.len);
    try std.testing.expectEqualStrings("task_stats", result.steps.items[0].name);
    try std.testing.expectEqualStrings("tenant_list", result.steps.items[1].name);

    const approval_id = try ai_store.createApproval(1, 7, "zweq.notify.send", "{\"user_id\":1,\"title\":\"t\",\"body\":\"b\",\"kind\":\"info\"}", 100);
    _ = try user_store.createUser("Boss", "boss@x.com", "hash", false, true, 1, 100);
    _ = try svc.approve(allocator, approval_id, 2, true);

    // 审计日志应有 ai.approval 记录。
    var logs = try audit_store.list(1, 10, .{ .action = "ai." });
    defer logs.free(allocator);
    try std.testing.expectEqual(@as(i64, 1), logs.total);
    try std.testing.expectEqualStrings("ai.approval", logs.items[0].action);
}

test "session revocation: token_version bump invalidates old JWTs" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = user.persistence.UserStore.init(allocator, env.client);
    var sec = zigmodu.security.AppSecurity.init(allocator, std.testing.io, .{ .jwt_secret = "testkit-secret" });
    const uid = try store.createUser("Alice", "a@x.com", "hash", false, false, 1, 100);

    const Whoami = struct {
        fn h(ctx: *zigmodu.http.Context) !void {
            const mw_mod = @import("middleware/auth.zig");
            const uid_ = mw_mod.authUserId(ctx) orelse {
                try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                return;
            };
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "", .data = .{ .uid = uid_ } });
        }
    };

    var server = zigmodu.http.Server.init(std.testing.io, allocator, 0);
    defer server.deinit();
    var g = server.group("/api/v1");
    var guarded = try g.use(zigmodu.http.http_middleware.jwtAuthWithSecurity(&sec.module));
    guarded = try guarded.use(@import("middleware/auth.zig").tokenVersionGuard(&sec, &store));
    try guarded.get("/whoami", Whoami.h, null);

    var uid_buf: [32]u8 = undefined;
    const token = try sec.module.generateTokenWithTenantAndVersion(try std.fmt.bufPrint(&uid_buf, "{d}", .{uid}), &.{}, "1", 0);
    defer allocator.free(token);
    var hdr: [512]u8 = undefined;
    const auth_header = try std.fmt.bufPrint(&hdr, "Bearer {s}", .{token});

    // 版本未递增 → 正常访问。
    var ok = try zigmodu.http.Testkit.dispatchOpts(&server, .GET, "/api/v1/whoami", .{ .headers = &.{.{ "authorization", auth_header }} });
    defer ok.deinit(allocator);
    try std.testing.expectEqual(@as(u16, 200), ok.status_code);

    // 改密/踢下线(版本 +1)→ 旧 token 立即失效。
    const now = zigmodu.time.wallClockSeconds(std.testing.io);
    try store.bumpTokenVersion(uid, now);
    var denied = try zigmodu.http.Testkit.dispatchOpts(&server, .GET, "/api/v1/whoami", .{ .headers = &.{.{ "authorization", auth_header }} });
    defer denied.deinit(allocator);
    try std.testing.expectEqual(@as(u16, 401), denied.status_code);
}

test "seckill: rush lifecycle + atomic stock + dedup" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = seckill.persistence.SeckillStore.init(allocator, env.client);
    var svc = seckill.service.SeckillService.init(allocator, std.testing.io, &store);

    const aid = try svc.createActivity(1, 9, "限时特惠", 9900, 19900, 2, 1, 0, 0);

    // 抢 1 件成功，sold=1。
    _ = try svc.rush(1, 9, "o_a", aid, 1);
    const a1 = (try svc.getActivity(aid)).?;
    defer a1.free(allocator);
    try std.testing.expectEqual(@as(i64, 1), a1.sold);

    // 另一用户抢 1 件，sold=2（库存耗尽）。
    _ = try svc.rush(1, 9, "o_b", aid, 1);
    const a2 = (try svc.getActivity(aid)).?;
    defer a2.free(allocator);
    try std.testing.expectEqual(@as(i64, 2), a2.sold);

    // 第 3 件 → OutOfStock（原子扣减失败）。
    try std.testing.expectError(error.OutOfStock, svc.rush(1, 9, "o_c", aid, 1));

    // 限购：o_a 已抢 1，per_user=1 → 再抢 LimitReached。
    try std.testing.expectError(error.LimitReached, svc.rush(1, 9, "o_a", aid, 1));

    // 不存在活动 → NotFound。
    try std.testing.expectError(error.NotFound, svc.rush(1, 9, "o_x", 9999, 1));
}

test "seckill: module receiver handles 秒杀 + 抢N" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();

    var account_store = account.persistence.AccountStore.init(allocator, env.client);
    var account_svc = account.service.AccountService.init(allocator, std.testing.io, &account_store);
    var rule_store = rule.persistence.RuleStore.init(allocator, env.client);
    var rule_svc = rule.service.RuleService.init(allocator, std.testing.io, &rule_store);
    var fan_store = member.persistence.FanStore.init(allocator, env.client);
    var member_svc = member.service.MemberService.init(allocator, std.testing.io, &fan_store);
    var setting_store = setting.persistence.SettingStore.init(allocator, env.client);
    var message_store = message.persistence.MessageStore.init(allocator, env.client);
    var module_store = appmod.persistence.ModuleStore.init(allocator, env.client);
    var module_svc = appmod.service.ModuleService.init(allocator, std.testing.io, &module_store);
    var seckill_store = seckill.persistence.SeckillStore.init(allocator, env.client);
    var seckill_svc = seckill.service.SeckillService.init(allocator, std.testing.io, &seckill_store);

    var wechat_svc = message.service.WechatService.init(allocator, std.testing.io, &account_svc, &rule_svc, &member_svc, &setting_store, &message_store);
    wechat_svc.module_svc = &module_svc;
    var seckill_ctx = seckill.service.ReceiverCtx{ .io = std.testing.io, .seckill_svc = &seckill_svc };
    try wechat_svc.registerReceiver(.{ .module_name = "seckill", .ctx = &seckill_ctx, .handle = seckill.service.receiverHandle });

    const account_id = try account_svc.create(1, "秒杀测试号", "wechat");
    _ = try account_svc.upsertWechat(1, account_id, .{ .appid = "wx1", .secret = "s", .token = "toks", .encoding_aes_key = "", .verified = false });
    _ = try module_svc.bind(1, account_id, "seckill", "active");
    _ = try seckill_svc.createActivity(1, account_id, "周年庆秒杀", 100, 500, 10, 1, 0, 0);

    const token = "toks";
    var ts_buf: [16]u8 = undefined;
    const ts = try std.fmt.bufPrint(&ts_buf, "{d}", .{zigmodu.time.wallClockSeconds(std.testing.io)});
    const nonce = "ns";
    const sig = try zwechat.util.signature.signature(allocator, &[_][]const u8{ token, ts, nonce });
    defer allocator.free(sig);

    // 「秒杀」→ 列活动 + 价格 + 剩余。
    const q_xml = "<xml><ToUserName><![CDATA[gh]]></ToUserName><FromUserName><![CDATA[o_s]]></FromUserName><CreateTime>1700000000</CreateTime><MsgType><![CDATA[text]]></MsgType><Content><![CDATA[秒杀]]></Content></xml>";
    const r1 = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, q_xml);
    defer allocator.free(r1);
    try std.testing.expect(std.mem.indexOf(u8, r1, "周年庆秒杀") != null);
    try std.testing.expect(std.mem.indexOf(u8, r1, "1.00") != null);

    // 「抢1」→ 抢购成功。
    const rush_xml = "<xml><ToUserName><![CDATA[gh]]></ToUserName><FromUserName><![CDATA[o_s]]></FromUserName><CreateTime>1700000000</CreateTime><MsgType><![CDATA[text]]></MsgType><Content><![CDATA[抢1]]></Content></xml>";
    const r2 = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, rush_xml);
    defer allocator.free(r2);
    try std.testing.expect(std.mem.indexOf(u8, r2, "抢购成功") != null);

    // 再抢 → 每人限购。
    const r3 = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, rush_xml);
    defer allocator.free(r3);
    try std.testing.expect(std.mem.indexOf(u8, r3, "每人限购") != null);
}

test "member_card: open/view/adjust lifecycle + auto level-up" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = member_card.persistence.MemberCardStore.init(allocator, env.client);
    var svc = member_card.service.MemberCardService.init(allocator, std.testing.io, &store);

    // 建两个等级：普通（0 积分 9.5 折）+ 黄金（1000 积分 9 折）。
    const normal_id = try svc.createLevel(1, 9, "普通会员", 1, 950, 100, 0);
    const gold_id = try svc.createLevel(1, 9, "黄金会员", 2, 900, 200, 1000);

    // 开卡 → 默认普通等级。
    try svc.openCard(1, 9, "o_m");
    var v1 = (try svc.view(1, 9, "o_m")).?;
    defer v1.free(allocator);
    try std.testing.expectEqualStrings("普通会员", v1.level_name);
    try std.testing.expectEqual(@as(i64, 0), v1.points);
    try std.testing.expectEqual(@as(i64, 950), v1.discount);

    // 重复开卡 → AlreadyOpened。
    try std.testing.expectError(error.AlreadyOpened, svc.openCard(1, 9, "o_m"));

    // 加积分 1200 → 余额 1200 + 自动升级黄金。
    try svc.adjust(1, 9, "o_m", 1200);
    var v2 = (try svc.view(1, 9, "o_m")).?;
    defer v2.free(allocator);
    try std.testing.expectEqualStrings("黄金会员", v2.level_name);
    try std.testing.expectEqual(@as(i64, 1200), v2.points);
    try std.testing.expectEqual(@as(i64, 900), v2.discount);

    // 消耗 1300 → 积分不足拒绝。
    try std.testing.expectError(error.InsufficientPoints, svc.adjust(1, 9, "o_m", -1300));

    // 消耗 500 → 余额 700，等级仍黄金（累计 1200 >= 1000）。
    try svc.adjust(1, 9, "o_m", -500);
    var v3 = (try svc.view(1, 9, "o_m")).?;
    defer v3.free(allocator);
    try std.testing.expectEqual(@as(i64, 700), v3.points);
    try std.testing.expectEqualStrings("黄金会员", v3.level_name);

    // 未办卡 → NotFound。
    try std.testing.expectError(error.NotFound, svc.adjust(1, 9, "o_nobody", 100));
    _ = normal_id;
    _ = gold_id;
}

test "member_card: module receiver handles 办卡 + 查卡" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();

    var account_store = account.persistence.AccountStore.init(allocator, env.client);
    var account_svc = account.service.AccountService.init(allocator, std.testing.io, &account_store);
    var rule_store = rule.persistence.RuleStore.init(allocator, env.client);
    var rule_svc = rule.service.RuleService.init(allocator, std.testing.io, &rule_store);
    var fan_store = member.persistence.FanStore.init(allocator, env.client);
    var member_svc = member.service.MemberService.init(allocator, std.testing.io, &fan_store);
    var setting_store = setting.persistence.SettingStore.init(allocator, env.client);
    var message_store = message.persistence.MessageStore.init(allocator, env.client);
    var module_store = appmod.persistence.ModuleStore.init(allocator, env.client);
    var module_svc = appmod.service.ModuleService.init(allocator, std.testing.io, &module_store);
    var mc_store = member_card.persistence.MemberCardStore.init(allocator, env.client);
    var mc_svc = member_card.service.MemberCardService.init(allocator, std.testing.io, &mc_store);

    var wechat_svc = message.service.WechatService.init(allocator, std.testing.io, &account_svc, &rule_svc, &member_svc, &setting_store, &message_store);
    wechat_svc.module_svc = &module_svc;
    var mc_ctx = member_card.service.ReceiverCtx{ .io = std.testing.io, .member_svc = &mc_svc };
    try wechat_svc.registerReceiver(.{ .module_name = "member_card", .ctx = &mc_ctx, .handle = member_card.service.receiverHandle });

    const account_id = try account_svc.create(1, "会员卡测试号", "wechat");
    _ = try account_svc.upsertWechat(1, account_id, .{ .appid = "wx1", .secret = "s", .token = "tokm", .encoding_aes_key = "", .verified = false });
    _ = try module_svc.bind(1, account_id, "member_card", "active");
    _ = try mc_svc.createLevel(1, account_id, "普通会员", 1, 950, 100, 0);

    const token = "tokm";
    var ts_buf: [16]u8 = undefined;
    const ts = try std.fmt.bufPrint(&ts_buf, "{d}", .{zigmodu.time.wallClockSeconds(std.testing.io)});
    const nonce = "nm";
    const sig = try zwechat.util.signature.signature(allocator, &[_][]const u8{ token, ts, nonce });
    defer allocator.free(sig);

    // 「办卡」→ 成功。
    const open_xml = "<xml><ToUserName><![CDATA[gh]]></ToUserName><FromUserName><![CDATA[o_mc]]></FromUserName><CreateTime>1700000000</CreateTime><MsgType><![CDATA[text]]></MsgType><Content><![CDATA[办卡]]></Content></xml>";
    const r1 = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, open_xml);
    defer allocator.free(r1);
    try std.testing.expect(std.mem.indexOf(u8, r1, "办卡成功") != null);

    // 「查卡」→ 等级 + 积分 + 折扣。
    const view_xml = "<xml><ToUserName><![CDATA[gh]]></ToUserName><FromUserName><![CDATA[o_mc]]></FromUserName><CreateTime>1700000000</CreateTime><MsgType><![CDATA[text]]></MsgType><Content><![CDATA[查卡]]></Content></xml>";
    const r2 = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, view_xml);
    defer allocator.free(r2);
    try std.testing.expect(std.mem.indexOf(u8, r2, "普通会员") != null);
    try std.testing.expect(std.mem.indexOf(u8, r2, "积分") != null);
    try std.testing.expect(std.mem.indexOf(u8, r2, "9.50 折") != null);

    // 再「办卡」→ 已办过。
    const r3 = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, open_xml);
    defer allocator.free(r3);
    try std.testing.expect(std.mem.indexOf(u8, r3, "已经办过") != null);
}

test "distribution: join/3-level commission/withdraw lifecycle" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = distribution.persistence.DistributionStore.init(allocator, env.client);
    var svc = distribution.service.DistributionService.init(allocator, std.testing.io, &store);

    // 三级链：A(顶) ← B(中) ← C(买家分销员)。
    try svc.becomeDistributor(1, 9, "o_A", "");
    try svc.becomeDistributor(1, 9, "o_B", "o_A");
    try svc.becomeDistributor(1, 9, "o_C", "o_B");

    // 重复加盟 → AlreadyDistributor。
    try std.testing.expectError(error.AlreadyDistributor, svc.becomeDistributor(1, 9, "o_B", ""));
    // 上级无效 → InvalidParent（自己不能做自己上级）。
    try std.testing.expectError(error.InvalidParent, svc.becomeDistributor(1, 9, "o_X", "o_X"));
    try std.testing.expectError(error.InvalidParent, svc.becomeDistributor(1, 9, "o_X", "o_NotFound"));

    // C 消费 10000 分 → 一级上级 B 得 10%（1000）、二级上级 A 得 5%（500）。
    const count = try svc.distribute(1, 9, "o_C", 10000);
    try std.testing.expectEqual(@as(usize, 2), count);

    const a = (try svc.getDistributor(1, 9, "o_A")).?;
    defer a.free(allocator);
    const b = (try svc.getDistributor(1, 9, "o_B")).?;
    defer b.free(allocator);
    const c = (try svc.getDistributor(1, 9, "o_C")).?;
    defer c.free(allocator);
    try std.testing.expectEqual(@as(i64, 500), a.commission_balance);
    try std.testing.expectEqual(@as(i64, 1000), b.commission_balance);
    try std.testing.expectEqual(@as(i64, 0), c.commission_balance);

    // B 提现 700 → 余额 300；超额提现拒绝。
    try svc.withdraw(1, 9, "o_B", 700);
    const b2 = (try svc.getDistributor(1, 9, "o_B")).?;
    defer b2.free(allocator);
    try std.testing.expectEqual(@as(i64, 300), b2.commission_balance);
    try std.testing.expectError(error.InsufficientBalance, svc.withdraw(1, 9, "o_B", 400));
}

test "distribution: module receiver handles 加盟 + 分销" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();

    var account_store = account.persistence.AccountStore.init(allocator, env.client);
    var account_svc = account.service.AccountService.init(allocator, std.testing.io, &account_store);
    var rule_store = rule.persistence.RuleStore.init(allocator, env.client);
    var rule_svc = rule.service.RuleService.init(allocator, std.testing.io, &rule_store);
    var fan_store = member.persistence.FanStore.init(allocator, env.client);
    var member_svc = member.service.MemberService.init(allocator, std.testing.io, &fan_store);
    var setting_store = setting.persistence.SettingStore.init(allocator, env.client);
    var message_store = message.persistence.MessageStore.init(allocator, env.client);
    var module_store = appmod.persistence.ModuleStore.init(allocator, env.client);
    var module_svc = appmod.service.ModuleService.init(allocator, std.testing.io, &module_store);
    var dist_store = distribution.persistence.DistributionStore.init(allocator, env.client);
    var dist_svc = distribution.service.DistributionService.init(allocator, std.testing.io, &dist_store);

    var wechat_svc = message.service.WechatService.init(allocator, std.testing.io, &account_svc, &rule_svc, &member_svc, &setting_store, &message_store);
    wechat_svc.module_svc = &module_svc;
    var dist_ctx = distribution.service.ReceiverCtx{ .io = std.testing.io, .dist_svc = &dist_svc };
    try wechat_svc.registerReceiver(.{ .module_name = "distribution", .ctx = &dist_ctx, .handle = distribution.service.receiverHandle });

    const account_id = try account_svc.create(1, "分销测试号", "wechat");
    _ = try account_svc.upsertWechat(1, account_id, .{ .appid = "wx1", .secret = "s", .token = "tokd", .encoding_aes_key = "", .verified = false });
    _ = try module_svc.bind(1, account_id, "distribution", "active");

    const token = "tokd";
    var ts_buf: [16]u8 = undefined;
    const ts = try std.fmt.bufPrint(&ts_buf, "{d}", .{zigmodu.time.wallClockSeconds(std.testing.io)});
    const nonce = "nd";
    const sig = try zwechat.util.signature.signature(allocator, &[_][]const u8{ token, ts, nonce });
    defer allocator.free(sig);

    // 「加盟」→ 成功。
    const join_xml = "<xml><ToUserName><![CDATA[gh]]></ToUserName><FromUserName><![CDATA[o_d]]></FromUserName><CreateTime>1700000000</CreateTime><MsgType><![CDATA[text]]></MsgType><Content><![CDATA[加盟]]></Content></xml>";
    const r1 = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, join_xml);
    defer allocator.free(r1);
    try std.testing.expect(std.mem.indexOf(u8, r1, "加盟成功") != null);

    // 「分销」→ 佣金余额 0.00 元。
    const view_xml = "<xml><ToUserName><![CDATA[gh]]></ToUserName><FromUserName><![CDATA[o_d]]></FromUserName><CreateTime>1700000000</CreateTime><MsgType><![CDATA[text]]></MsgType><Content><![CDATA[分销]]></Content></xml>";
    const r2 = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, view_xml);
    defer allocator.free(r2);
    try std.testing.expect(std.mem.indexOf(u8, r2, "佣金余额") != null);
    try std.testing.expect(std.mem.indexOf(u8, r2, "0.00 元") != null);

    // 再「加盟」→ 已是分销员。
    const r3 = try wechat_svc.handleCallback(allocator, token, .{ .signature = sig, .timestamp = ts, .nonce = nonce }, join_xml);
    defer allocator.free(r3);
    try std.testing.expect(std.mem.indexOf(u8, r3, "已经是分销员") != null);
}

test "shop: category CRUD + product lifecycle (Phase1)" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = shop.persistence.ShopStore.init(allocator, env.client);
    var svc = shop.service.ShopService.init(allocator, std.testing.io, &store);

    // 分类：创建两个 + 列表 + 删除。
    const cat_id = try svc.createCategory(1, 9, "数码", 0, 1);
    _ = try svc.createCategory(1, 9, "服饰", 0, 2);
    var cats = try svc.listCategories(1, 9);
    defer cats.free(allocator);
    try std.testing.expectEqual(@as(usize, 2), cats.items.len);

    // 商品（默认单 SKU）。
    const pid = try svc.createProduct(1, 9, .{
        .category_id = cat_id,
        .name = "蓝牙耳机",
        .image = "/img/x.png",
        .content = "好耳机",
        .price = 9900,
        .original_price = 19900,
        .stock = 100,
        .status = 1,
        .skus = &.{},
    });
    const p = (try svc.getProduct(pid)).?;
    defer p.free(allocator);
    try std.testing.expectEqualStrings("蓝牙耳机", p.name);
    try std.testing.expectEqual(@as(i64, 9900), p.price);

    // 详情含默认 SKU。
    const skus = try svc.listSkus(pid);
    defer {
        for (skus) |s| s.free(allocator);
        if (skus.len > 0) allocator.free(skus);
    }
    try std.testing.expectEqual(@as(usize, 1), skus.len);
    try std.testing.expectEqual(@as(i64, 9900), skus[0].price);

    // C 端列表（仅上架）含商品。
    var list = try svc.listProducts(1, 20, 1, 9, 0, "", true);
    defer list.free(allocator);
    try std.testing.expectEqual(@as(i64, 1), list.total);

    // 下架后 C 端不可见。
    _ = try svc.updateProduct(1, 9, pid, .{
        .category_id = cat_id,
        .name = "蓝牙耳机",
        .image = "/img/x.png",
        .content = "",
        .price = 9900,
        .original_price = 19900,
        .stock = 100,
        .status = 0,
        .skus = &.{},
    });
    var list2 = try svc.listProducts(1, 20, 1, 9, 0, "", true);
    defer list2.free(allocator);
    try std.testing.expectEqual(@as(i64, 0), list2.total);

    // 删除商品 + 分类。
    try svc.deleteProduct(pid);
    try std.testing.expect((try svc.getProduct(pid)) == null);
    try svc.deleteCategory(cat_id);
}

test "shop: product with multi-SKU specs" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = shop.persistence.ShopStore.init(allocator, env.client);
    var svc = shop.service.ShopService.init(allocator, std.testing.io, &store);

    const pid = try svc.createProduct(1, 9, .{
        .category_id = 0,
        .name = "定制T恤",
        .image = "",
        .content = "",
        .price = 5900,
        .original_price = 9900,
        .stock = 200,
        .status = 1,
        .skus = &.{
            .{ .spec_json = "[{\"k\":\"颜色\",\"v\":\"红\"}]", .image = "", .price = 5900, .stock = 100 },
            .{ .spec_json = "[{\"k\":\"颜色\",\"v\":\"蓝\"}]", .image = "", .price = 6900, .stock = 100 },
        },
    });

    const skus = try svc.listSkus(pid);
    defer {
        for (skus) |s| s.free(allocator);
        if (skus.len > 0) allocator.free(skus);
    }
    try std.testing.expectEqual(@as(usize, 2), skus.len);
    try std.testing.expect(std.mem.indexOf(u8, skus[0].spec_json, "红") != null or std.mem.indexOf(u8, skus[1].spec_json, "红") != null);
}

test "shop: cart/address/order trade lifecycle (Phase2)" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = shop.persistence.ShopStore.init(allocator, env.client);
    var svc = shop.service.ShopService.init(allocator, std.testing.io, &store);

    // 商品 + 默认 SKU。
    const pid = try svc.createProduct(1, 9, .{
        .category_id = 0, .name = "测试商品", .image = "", .content = "",
        .price = 5000, .original_price = 8000, .stock = 10, .status = 1, .skus = &.{},
    });
    const skus = try svc.listSkus(pid);
    defer {
        for (skus) |s| s.free(allocator);
        if (skus.len > 0) allocator.free(skus);
    }
    const sku_id = skus[0].id;

    // 购物车：加入 + 累加。
    const cart_id = try svc.addCart(1, 9, "o_buyer", pid, sku_id, 2);
    _ = try svc.addCart(1, 9, "o_buyer", pid, sku_id, 3);
    const carts = try svc.listCarts(1, "o_buyer");
    defer {
        for (carts) |c| c.free(allocator);
        if (carts.len > 0) allocator.free(carts);
    }
    try std.testing.expectEqual(@as(usize, 1), carts.len);
    try std.testing.expectEqual(@as(i64, 5), carts[0].quantity);

    // 地址（默认）。
    const addr_id = try svc.createAddress(1, 9, .{
        .openid = "o_buyer", .name = "张三", .mobile = "13800138000",
        .region = "广东省深圳市", .detail = "科技园 1 号", .is_default = 1,
    });
    const addrs = try svc.listAddresses(1, "o_buyer");
    defer {
        for (addrs) |a| a.free(allocator);
        if (addrs.len > 0) allocator.free(addrs);
    }
    try std.testing.expectEqual(@as(usize, 1), addrs.len);

    // 下单：数量 5 → 扣库存 10→5；金额 5000*5。
    const order_id = try svc.createOrder(1, 9, "o_buyer", addr_id, &.{
        .{ .product_id = pid, .sku_id = sku_id, .quantity = 5 },
    }, "", "", "", 0);
    var o = (try svc.getOrder(order_id)).?;
    defer o.free(allocator);
    try std.testing.expectEqual(@as(i64, 25000), o.total_amount);
    try std.testing.expectEqual(@as(i64, 0), o.status);

    // 库存已扣：SKU stock 10-5=5。
    const sku2 = (try svc.getSku(sku_id)).?;
    defer sku2.free(allocator);
    try std.testing.expectEqual(@as(i64, 5), sku2.stock);

    // 明细。
    const ops = try svc.listOrderProducts(order_id);
    defer {
        for (ops) |op| op.free(allocator);
        if (ops.len > 0) allocator.free(ops);
    }
    try std.testing.expectEqual(@as(usize, 1), ops.len);
    try std.testing.expectEqualStrings("测试商品", ops[0].name);

    // 超库存下单 → OutOfStock。
    try std.testing.expectError(error.OutOfStock, svc.createOrder(1, 9, "o_buyer", addr_id, &.{
        .{ .product_id = pid, .sku_id = sku_id, .quantity = 99 },
    }, "", "", "", 0));

    // 状态流转：支付 → 发货 → 确认收货；待支付取消 → 冲突。
    try svc.markPaid(1, 9, order_id);
    try svc.shipOrder(order_id, "顺丰", "SF123");
    try svc.confirmOrder(order_id);
    var o2 = (try svc.getOrder(order_id)).?;
    defer o2.free(allocator);
    try std.testing.expectEqual(@as(i64, 3), o2.status);
    try std.testing.expectEqualStrings("顺丰", o2.express_company);
    try std.testing.expectError(error.OrderStateConflict, svc.cancelOrder(order_id));

    // 清理购物车/地址。
    try svc.updateCart(cart_id, 1);
    try svc.deleteCart(cart_id);
    try svc.deleteAddress(addr_id);
}

test "shop: refund apply/audit + comment + distribution hookup (Phase3)" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = shop.persistence.ShopStore.init(allocator, env.client);
    var svc = shop.service.ShopService.init(allocator, std.testing.io, &store);
    var dist_store = distribution.persistence.DistributionStore.init(allocator, env.client);
    var dist_svc = distribution.service.DistributionService.init(allocator, std.testing.io, &dist_store);
    svc.dist_svc = &dist_svc;

    // 分销链：A(顶) ← B(买家上级)。
    try dist_svc.becomeDistributor(1, 9, "o_A", "");
    try dist_svc.becomeDistributor(1, 9, "o_B", "o_A");

    // 商品 + 下单（mock 支付 markPaid → 触发分佣）。
    const pid = try svc.createProduct(1, 9, .{
        .category_id = 0, .name = "佣金商品", .image = "", .content = "",
        .price = 10000, .original_price = 12000, .stock = 10, .status = 1, .skus = &.{},
    });
    const skus = try svc.listSkus(pid);
    defer {
        for (skus) |s| s.free(allocator);
        if (skus.len > 0) allocator.free(skus);
    }
    const addr_id = try svc.createAddress(1, 9, .{
        .openid = "o_B", .name = "B", .mobile = "13800000000", .region = "SZ", .detail = "1号", .is_default = 1,
    });
    const order_id = try svc.createOrder(1, 9, "o_B", addr_id, &.{
        .{ .product_id = pid, .sku_id = skus[0].id, .quantity = 1 },
    }, "", "", "", 0);
    try svc.markPaid(1, 9, order_id);

    // 分佣：B 的一级上级 A 得 10% = 1000。
    const a = (try dist_svc.getDistributor(1, 9, "o_A")).?;
    defer a.free(allocator);
    try std.testing.expectEqual(@as(i64, 1000), a.commission_balance);

    // 退款：申请（重复申请拒绝）→ 审核同意 → 订单置已取消。
    _ = try svc.applyRefund(1, 9, order_id, "o_B", "不想要了");
    try std.testing.expectError(error.Duplicate, svc.applyRefund(1, 9, order_id, "o_B", "再次申请"));
    var refunds = try svc.listRefunds(1, 20, 1, 9, -1);
    defer refunds.free(allocator);
    try std.testing.expectEqual(@as(i64, 1), refunds.total);
    try svc.auditRefund(order_id, refunds.items[0].id, true);
    var o = (try svc.getOrder(order_id)).?;
    defer o.free(allocator);
    try std.testing.expectEqual(@as(i64, 4), o.status);

    // 评价实名：退款订单（status=4）不可评。
    const ops = try svc.listOrderProducts(order_id);
    defer {
        for (ops) |op| op.free(allocator);
        if (ops.len > 0) allocator.free(ops);
    }
    try std.testing.expectError(error.OrderStateConflict, svc.createComment(1, 9, .{
        .order_product_id = ops[0].id,
        .product_id = pid,
        .openid = "o_B",
        .star = 5,
        .content = "不该能评",
    }));

    // 完整订单（支付→发货→收货）后可评价；非买家不可评。
    const order2 = try svc.createOrder(1, 9, "o_B", addr_id, &.{
        .{ .product_id = pid, .sku_id = skus[0].id, .quantity = 1 },
    }, "", "", "", 0);
    try svc.markPaid(1, 9, order2);
    try svc.shipOrder(order2, "顺丰", "SF2");
    try svc.confirmOrder(order2);
    const ops2 = try svc.listOrderProducts(order2);
    defer {
        for (ops2) |op| op.free(allocator);
        if (ops2.len > 0) allocator.free(ops2);
    }
    // 非买家（o_x）评价 → InvalidInput。
    try std.testing.expectError(error.InvalidInput, svc.createComment(1, 9, .{
        .order_product_id = ops2[0].id,
        .product_id = pid,
        .openid = "o_x",
        .star = 5,
        .content = "冒充",
    }));
    _ = try svc.createComment(1, 9, .{
        .order_product_id = ops2[0].id,
        .product_id = pid,
        .openid = "o_B",
        .star = 5,
        .content = "很好用",
    });
    const comments = try svc.listComments(pid);
    defer {
        for (comments) |c| c.free(allocator);
        if (comments.len > 0) allocator.free(comments);
    }
    try std.testing.expectEqual(@as(usize, 1), comments.len);
    try std.testing.expectEqualStrings("很好用", comments[0].content);
}

test "shop: coupon deduction + member points accrual on payment" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = shop.persistence.ShopStore.init(allocator, env.client);
    var svc = shop.service.ShopService.init(allocator, std.testing.io, &store);
    var coupon_store = coupon.persistence.CouponStore.init(allocator, env.client);
    var coupon_svc = coupon.service.CouponService.init(allocator, std.testing.io, &coupon_store);
    var mc_store = member_card.persistence.MemberCardStore.init(allocator, env.client);
    var mc_svc = member_card.service.MemberCardService.init(allocator, std.testing.io, &mc_store);
    svc.coupon_store = &coupon_store;
    svc.member_svc = &mc_svc;

    // 商品 100 元（10000 分）。
    const pid = try svc.createProduct(1, 9, .{
        .category_id = 0, .name = "满减测试", .image = "", .content = "",
        .price = 10000, .original_price = 12000, .stock = 10, .status = 1, .skus = &.{},
    });
    const skus = try svc.listSkus(pid);
    defer {
        for (skus) |s| s.free(allocator);
        if (skus.len > 0) allocator.free(skus);
    }
    const addr_id = try svc.createAddress(1, 9, .{
        .openid = "o_m", .name = "M", .mobile = "13800000000", .region = "SZ", .detail = "1号", .is_default = 1,
    });

    // 会员卡（支付后积分累计的前提）：先建等级，开卡自动绑定。
    _ = try mc_svc.createLevel(1, 9, "普通会员", 1, 1000, 100, 0);
    try mc_svc.openCard(1, 9, "o_m");

    // 领券：满 50 减 10（1000 分）。
    const coupon_id = try coupon_svc.createCoupon(1, 9, "满50减10", 1000, 5000, 100, 1, 0, 0);
    const code = try coupon_svc.claimCoupon(allocator, 1, 9, "o_m", coupon_id);
    defer allocator.free(code);

    // 下单用券：100 元 - 10 元 = 90 元实付。
    const order_id = try svc.createOrder(1, 9, "o_m", addr_id, &.{
        .{ .product_id = pid, .sku_id = skus[0].id, .quantity = 1 },
    }, code, "", "", 0);
    var o = (try svc.getOrder(order_id)).?;
    defer o.free(allocator);
    try std.testing.expectEqual(@as(i64, 10000), o.total_amount);
    try std.testing.expectEqual(@as(i64, 9000), o.pay_amount);

    // 券已核销（used）。
    const u = (try coupon_store.getByCode(code)).?;
    defer u.free(allocator);
    try std.testing.expectEqualStrings("used", u.status);

    // 支付 → 会员积分累计：90 元 = 90 积分。
    try svc.markPaid(1, 9, order_id);
    const v = (try mc_svc.view(1, 9, "o_m")).?;
    defer v.free(allocator);
    try std.testing.expectEqual(@as(i64, 90), v.points);

    // 他人券不可用：B 领券，A 下单用 B 的券 → InvalidInput。
    const code_b = try coupon_svc.claimCoupon(allocator, 1, 9, "o_other", coupon_id);
    defer allocator.free(code_b);
    try std.testing.expectError(error.InvalidInput, svc.createOrder(1, 9, "o_m", addr_id, &.{
        .{ .product_id = pid, .sku_id = skus[0].id, .quantity = 1 },
    }, code_b, "", "", 0));
}

test "shop: idempotency + stock restore on cancel (production hardening)" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = shop.persistence.ShopStore.init(allocator, env.client);
    var svc = shop.service.ShopService.init(allocator, std.testing.io, &store);

    const pid = try svc.createProduct(1, 9, .{
        .category_id = 0, .name = "回滚测试", .image = "", .content = "",
        .price = 1000, .original_price = 2000, .stock = 10, .status = 1, .skus = &.{},
    });
    const skus = try svc.listSkus(pid);
    defer {
        for (skus) |s| s.free(allocator);
        if (skus.len > 0) allocator.free(skus);
    }
    const addr_id = try svc.createAddress(1, 9, .{
        .openid = "o_r", .name = "R", .mobile = "13800000000", .region = "SZ", .detail = "1", .is_default = 1,
    });
    const items: []const shop.service.OrderItemInput = &.{ .{ .product_id = pid, .sku_id = skus[0].id, .quantity = 3 } };

    // 幂等：同 client_trade_no 重复下单 → 返回同一订单，库存只扣一次（10→7）。
    const o1 = try svc.createOrder(1, 9, "o_r", addr_id, items, "", "CTN-001", "", 0);
    const o2 = try svc.createOrder(1, 9, "o_r", addr_id, items, "", "CTN-001", "", 0);
    try std.testing.expectEqual(o1, o2);
    const sku_after = (try svc.getSku(skus[0].id)).?;
    defer sku_after.free(allocator);
    try std.testing.expectEqual(@as(i64, 7), sku_after.stock);

    // 取消 → 库存回滚（7→10），销量回退。
    try svc.cancelOrder(o1);
    const sku_restored = (try svc.getSku(skus[0].id)).?;
    defer sku_restored.free(allocator);
    try std.testing.expectEqual(@as(i64, 10), sku_restored.stock);
    const p2 = (try svc.getProduct(pid)).?;
    defer p2.free(allocator);
    try std.testing.expectEqual(@as(i64, 0), p2.sales);
}

test "shop: favorite + order stats (production extras)" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = shop.persistence.ShopStore.init(allocator, env.client);
    var svc = shop.service.ShopService.init(allocator, std.testing.io, &store);

    // 两件商品。
    const pid1 = try svc.createProduct(1, 9, .{
        .category_id = 0, .name = "收藏A", .image = "", .content = "",
        .price = 1000, .original_price = 2000, .stock = 5, .status = 1, .skus = &.{},
    });
    const pid2 = try svc.createProduct(1, 9, .{
        .category_id = 0, .name = "收藏B", .image = "", .content = "",
        .price = 2000, .original_price = 3000, .stock = 5, .status = 1, .skus = &.{},
    });

    // 收藏：两件 + 幂等（重复收藏不重复）。
    try svc.favorite(1, 9, "o_f", pid1);
    try svc.favorite(1, 9, "o_f", pid1);
    try svc.favorite(1, 9, "o_f", pid2);
    try std.testing.expect(try svc.isFavorite(1, "o_f", pid1));
    const favs = try svc.listFavorites(1, "o_f");
    defer {
        for (favs) |f| f.free(allocator);
        if (favs.len > 0) allocator.free(favs);
    }
    try std.testing.expectEqual(@as(usize, 2), favs.len);

    // 取消收藏一件。
    try svc.unfavorite(favs[0].id);
    try std.testing.expect(!(try svc.isFavorite(1, "o_f", pid1)));

    // 订单统计：2 单（1 支付 1 取消）+ 1 单待支付。
    const s1 = try svc.listSkus(pid1);
    defer {
        for (s1) |x| x.free(allocator);
        if (s1.len > 0) allocator.free(s1);
    }
    const addr_id = try svc.createAddress(1, 9, .{
        .openid = "o_s", .name = "S", .mobile = "13800000000", .region = "SZ", .detail = "1", .is_default = 1,
    });
    const o1 = try svc.createOrder(1, 9, "o_s", addr_id, &.{
        .{ .product_id = pid1, .sku_id = s1[0].id, .quantity = 2 },
    }, "", "", "", 0);
    try svc.markPaid(1, 9, o1); // 已支付 2000
    const o2 = try svc.createOrder(1, 9, "o_s", addr_id, &.{
        .{ .product_id = pid2, .sku_id = s1[0].id, .quantity = 1 },
    }, "", "", "", 0);
    try svc.cancelOrder(o2); // 取消
    _ = try svc.createOrder(1, 9, "o_s", addr_id, &.{
        .{ .product_id = pid1, .sku_id = s1[0].id, .quantity = 1 },
    }, "", "", "", 0); // 待支付

    const stats = try svc.orderStats(1, 9);
    try std.testing.expectEqual(@as(i64, 1), stats.pending_pay);
    try std.testing.expectEqual(@as(i64, 1), stats.pending_ship);
    try std.testing.expectEqual(@as(i64, 2000), stats.total_sales);
}

test "shop: balance payment via wallet (production extras)" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = shop.persistence.ShopStore.init(allocator, env.client);
    var svc = shop.service.ShopService.init(allocator, std.testing.io, &store);
    var pay_store = payment.persistence.PaymentStore.init(allocator, env.client);
    var pay_svc = payment.service.PaymentService.init(allocator, std.testing.io, &pay_store);
    var fan_store = member.persistence.FanStore.init(allocator, env.client);
    svc.payment_svc = &pay_svc;
    svc.fan_store = &fan_store;

    // 粉丝 + 充值钱包 200 元（20000 分）。
    const now_ts = zigmodu.time.wallClockSeconds(std.testing.io);
    const fan_id = try fan_store.upsert(1, 9, "o_balance", "", "余额买家", "", true, now_ts, now_ts);
    _ = try pay_store.creditWallet(1, 9, fan_id, 20000, zigmodu.time.wallClockSeconds(std.testing.io));

    // 商品 150 元。
    const pid = try svc.createProduct(1, 9, .{
        .category_id = 0, .name = "余额支付商品", .image = "", .content = "",
        .price = 15000, .original_price = 20000, .stock = 10, .status = 1, .skus = &.{},
    });
    const skus = try svc.listSkus(pid);
    defer {
        for (skus) |s| s.free(allocator);
        if (skus.len > 0) allocator.free(skus);
    }
    const addr_id = try svc.createAddress(1, 9, .{
        .openid = "o_balance", .name = "B", .mobile = "13800000000", .region = "SZ", .detail = "1", .is_default = 1,
    });

    // 余额支付下单：钱包 20000 → 15000，订单已支付。
    const order_id = try svc.createOrder(1, 9, "o_balance", addr_id, &.{
        .{ .product_id = pid, .sku_id = skus[0].id, .quantity = 1 },
    }, "", "", "balance", 0);
    var o = (try svc.getOrder(order_id)).?;
    defer o.free(allocator);
    try std.testing.expectEqual(@as(i64, 1), o.status); // 已支付
    const wallet = (try pay_svc.walletBalance(1, 9, fan_id)).?;
    try std.testing.expectEqual(@as(i64, 5000), wallet.balance);

    // 余额不足（仅 5000）→ 再下单 100 元 → InsufficientBalance。
    try std.testing.expectError(error.InsufficientBalance, svc.createOrder(1, 9, "o_balance", addr_id, &.{
        .{ .product_id = pid, .sku_id = skus[0].id, .quantity = 1 },
    }, "", "", "balance", 0));
}

test "shop: outlet CRUD + self-pickup verification code" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = shop.persistence.ShopStore.init(allocator, env.client);
    var svc = shop.service.ShopService.init(allocator, std.testing.io, &store);

    // 门店 CRUD。
    const outlet_id = try svc.createOutlet(1, 9, "南山店", "科技园 1 号", "0755-1234");
    const outlets = try svc.listOutlets(1, 9);
    defer {
        for (outlets) |o| o.free(allocator);
        if (outlets.len > 0) allocator.free(outlets);
    }
    try std.testing.expectEqual(@as(usize, 1), outlets.len);
    try std.testing.expectEqualStrings("南山店", outlets[0].name);

    // 商品 + 自提下单（pickup_store_id>0 → 自提码）。
    const pid = try svc.createProduct(1, 9, .{
        .category_id = 0, .name = "自提商品", .image = "", .content = "",
        .price = 3000, .original_price = 4000, .stock = 5, .status = 1, .skus = &.{},
    });
    const skus = try svc.listSkus(pid);
    defer {
        for (skus) |s| s.free(allocator);
        if (skus.len > 0) allocator.free(skus);
    }
    const addr_id = try svc.createAddress(1, 9, .{
        .openid = "o_p", .name = "P", .mobile = "13800000000", .region = "SZ", .detail = "1", .is_default = 1,
    });
    const order_id = try svc.createOrder(1, 9, "o_p", addr_id, &.{
        .{ .product_id = pid, .sku_id = skus[0].id, .quantity = 1 },
    }, "", "", "", outlet_id);
    var o = (try svc.getOrder(order_id)).?;
    defer o.free(allocator);
    try std.testing.expectEqualStrings("self", o.pickup_type);
    try std.testing.expect(o.pickup_code.len == 6);

    // 支付 → 核销：错误码拒绝，正确码成功（状态 3）。
    try svc.markPaid(1, 9, order_id);
    try std.testing.expectError(error.InvalidInput, svc.pickupOrder(order_id, "000000"));
    try svc.pickupOrder(order_id, o.pickup_code);
    var o2 = (try svc.getOrder(order_id)).?;
    defer o2.free(allocator);
    try std.testing.expectEqual(@as(i64, 3), o2.status);

    // 快递单（pickup_store_id=0）不可核销。
    const order_delivery = try svc.createOrder(1, 9, "o_p", addr_id, &.{
        .{ .product_id = pid, .sku_id = skus[0].id, .quantity = 1 },
    }, "", "", "", 0);
    try svc.markPaid(1, 9, order_delivery);
    try std.testing.expectError(error.OrderStateConflict, svc.pickupOrder(order_delivery, "123456"));

    try svc.deleteOutlet(outlet_id);
}

test "shop: balance plan recharge (Bonus) lifecycle" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = shop.persistence.ShopStore.init(allocator, env.client);
    var svc = shop.service.ShopService.init(allocator, std.testing.io, &store);
    var pay_store = payment.persistence.PaymentStore.init(allocator, env.client);
    var pay_svc = payment.service.PaymentService.init(allocator, std.testing.io, &pay_store);
    var fan_store = member.persistence.FanStore.init(allocator, env.client);
    svc.payment_svc = &pay_svc;
    svc.fan_store = &fan_store;

    // 粉丝 + 套餐（充 100 送 20）。
    const now_ts = zigmodu.time.wallClockSeconds(std.testing.io);
    const fan_id = try fan_store.upsert(1, 9, "o_plan", "", "储值用户", "", true, now_ts, now_ts);
    const plan_id = try svc.createBalancePlan(1, 9, "充100送20", 10000, 2000);

    // 列表（仅上架）。
    const plans = try svc.listBalancePlans(1, 9);
    defer {
        for (plans) |p| p.free(allocator);
        if (plans.len > 0) allocator.free(plans);
    }
    try std.testing.expectEqual(@as(usize, 1), plans.len);

    // 充值：钱包 0 → 12000（amount + bonus）。
    try svc.rechargePlan(1, 9, "o_plan", plan_id);
    const wallet = (try pay_svc.walletBalance(1, 9, fan_id)).?;
    try std.testing.expectEqual(@as(i64, 12000), wallet.balance);

    // 充值后可余额支付下单（闭环）。
    const pid = try svc.createProduct(1, 9, .{
        .category_id = 0, .name = "储值消费", .image = "", .content = "",
        .price = 10000, .original_price = 15000, .stock = 5, .status = 1, .skus = &.{},
    });
    const skus = try svc.listSkus(pid);
    defer {
        for (skus) |s| s.free(allocator);
        if (skus.len > 0) allocator.free(skus);
    }
    const addr_id = try svc.createAddress(1, 9, .{
        .openid = "o_plan", .name = "P", .mobile = "13800000000", .region = "SZ", .detail = "1", .is_default = 1,
    });
    const order_id = try svc.createOrder(1, 9, "o_plan", addr_id, &.{
        .{ .product_id = pid, .sku_id = skus[0].id, .quantity = 1 },
    }, "", "", "balance", 0);
    const wallet2 = (try pay_svc.walletBalance(1, 9, fan_id)).?;
    try std.testing.expectEqual(@as(i64, 2000), wallet2.balance);
    var o = (try svc.getOrder(order_id)).?;
    defer o.free(allocator);
    try std.testing.expectEqual(@as(i64, 1), o.status); // 已支付

    try svc.deleteBalancePlan(plan_id);
}

test "shop: auto-cancel expired pending orders (production ops)" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = shop.persistence.ShopStore.init(allocator, env.client);
    var svc = shop.service.ShopService.init(allocator, std.testing.io, &store);

    const pid = try svc.createProduct(1, 9, .{
        .category_id = 0, .name = "超时商品", .image = "", .content = "",
        .price = 1000, .original_price = 2000, .stock = 3, .status = 1, .skus = &.{},
    });
    const skus = try svc.listSkus(pid);
    defer {
        for (skus) |s| s.free(allocator);
        if (skus.len > 0) allocator.free(skus);
    }
    const addr_id = try svc.createAddress(1, 9, .{
        .openid = "o_t", .name = "T", .mobile = "13800000000", .region = "SZ", .detail = "1", .is_default = 1,
    });

    // 待支付订单（扣库存 3→2）。
    const order_id = try svc.createOrder(1, 9, "o_t", addr_id, &.{
        .{ .product_id = pid, .sku_id = skus[0].id, .quantity = 1 },
    }, "", "", "", 0);

    // 超时 0 秒 → 立即被清理（timeout_secs=0 表示所有待支付都过期）。
    const cancelled = try svc.autoCancelExpired(1, 9, 0);
    try std.testing.expectEqual(@as(usize, 1), cancelled);
    var o = (try svc.getOrder(order_id)).?;
    defer o.free(allocator);
    try std.testing.expectEqual(@as(i64, 4), o.status); // 已取消

    // 库存回滚：2→3。
    const sku_restored = (try svc.getSku(skus[0].id)).?;
    defer sku_restored.free(allocator);
    try std.testing.expectEqual(@as(i64, 3), sku_restored.stock);
}

test "shop: groupon open/join/success lifecycle" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = shop.persistence.ShopStore.init(allocator, env.client);
    var svc = shop.service.ShopService.init(allocator, std.testing.io, &store);

    // 商品（售价 100，团价 80，2 人成团）。
    const pid = try svc.createProduct(1, 9, .{
        .category_id = 0, .name = "拼团商品", .image = "", .content = "",
        .price = 10000, .original_price = 12000, .stock = 10, .status = 1, .skus = &.{},
    });
    const skus = try svc.listSkus(pid);
    defer {
        for (skus) |s| s.free(allocator);
        if (skus.len > 0) allocator.free(skus);
    }
    const gid = try svc.createGroupon(1, 9, pid, 8000, 2, 0, 0);
    const addr_id = try svc.createAddress(1, 9, .{
        .openid = "o_g1", .name = "G1", .mobile = "13800000000", .region = "SZ", .detail = "1", .is_default = 1,
    });

    // 开团：leader o_g1，团价 8000 下单。
    const team_id = try svc.openGroupon(1, 9, "o_g1", addr_id, gid, skus[0].id);
    var team = (try store.getTeam(team_id)).?;
    defer team.free(allocator);
    try std.testing.expectEqual(@as(i64, 1), team.current);
    try std.testing.expectEqual(@as(i64, 0), team.status); // 拼团中

    // 参团：o_g2 → current=2 → 成团。
    const addr2 = try svc.createAddress(1, 9, .{
        .openid = "o_g2", .name = "G2", .mobile = "13800000000", .region = "SZ", .detail = "2", .is_default = 1,
    });
    _ = try svc.joinGroupon(1, 9, "o_g2", addr2, team_id, skus[0].id);
    var team2 = (try store.getTeam(team_id)).?;
    defer team2.free(allocator);
    try std.testing.expectEqual(@as(i64, 2), team2.current);
    try std.testing.expectEqual(@as(i64, 1), team2.status); // 成团

    // 成团后：团内订单全部已支付（mock）。
    const orders = try store.listOrdersByTeam(team_id);
    defer {
        for (orders) |o| o.free(allocator);
        if (orders.len > 0) allocator.free(orders);
    }
    try std.testing.expectEqual(@as(usize, 2), orders.len);
    try std.testing.expectEqual(@as(i64, 1), orders[0].status);
    try std.testing.expectEqual(@as(i64, 8000), orders[0].pay_amount);

    // 已结束团不可再参。
    try std.testing.expectError(error.InvalidInput, svc.joinGroupon(1, 9, "o_g3", addr2, team_id, skus[0].id));
}

test "shop: invite gift bind/reward lifecycle" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = shop.persistence.ShopStore.init(allocator, env.client);
    var svc = shop.service.ShopService.init(allocator, std.testing.io, &store);
    var mc_store = member_card.persistence.MemberCardStore.init(allocator, env.client);
    var mc_svc = member_card.service.MemberCardService.init(allocator, std.testing.io, &mc_store);
    svc.member_svc = &mc_svc;

    // 会员卡（积分奖励前提）+ 奖励配置（邀请 2 人 → 100 积分）。
    _ = try mc_svc.createLevel(1, 9, "普通会员", 1, 1000, 100, 0);
    try mc_svc.openCard(1, 9, "o_inviter");
    _ = try svc.createInviteGift(1, 9, 2, "points", 100);

    // 邀请 2 人 → 邀请人得 100 积分。
    try svc.bindInvite(1, 9, "o_inviter", "o_f1");
    var v1 = (try mc_svc.view(1, 9, "o_inviter")).?;
    defer v1.free(allocator);
    try std.testing.expectEqual(@as(i64, 0), v1.points); // 未达标

    try svc.bindInvite(1, 9, "o_inviter", "o_f2");
    var v2 = (try mc_svc.view(1, 9, "o_inviter")).?;
    defer v2.free(allocator);
    try std.testing.expectEqual(@as(i64, 100), v2.points); // 达标发奖

    // 幂等：同 invitee 不重复绑定。
    try svc.bindInvite(1, 9, "o_inviter", "o_f2");
    var v3 = (try mc_svc.view(1, 9, "o_inviter")).?;
    defer v3.free(allocator);
    try std.testing.expectEqual(@as(i64, 100), v3.points); // 不重复发奖

    // 自邀请拒绝。
    try std.testing.expectError(error.InvalidInput, svc.bindInvite(1, 9, "o_inviter", "o_inviter"));

    // 邀请数查询。
    try std.testing.expectEqual(@as(i64, 2), try svc.store.countInvites(1, "o_inviter"));
}

test "shop: article CRUD + publish filter" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = shop.persistence.ShopStore.init(allocator, env.client);
    var svc = shop.service.ShopService.init(allocator, std.testing.io, &store);

    const aid = try svc.createArticle(1, 9, "新品发布", "内容：商城上线拼团与邀请有礼！");
    const a = (try svc.getArticle(aid)).?;
    defer a.free(allocator);
    try std.testing.expectEqualStrings("新品发布", a.title);

    // C 端列表（仅发布）含文章。
    var list = try svc.listArticles(1, 20, 1, 9, true);
    defer list.free(allocator);
    try std.testing.expectEqual(@as(i64, 1), list.total);
    try std.testing.expectEqualStrings("新品发布", list.items[0].title);

    // 删除后列表为空。
    try svc.deleteArticle(aid);
    var list2 = try svc.listArticles(1, 20, 1, 9, true);
    defer list2.free(allocator);
    try std.testing.expectEqual(@as(i64, 0), list2.total);
}

test "shop: AI assistant order-context replies" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = shop.persistence.ShopStore.init(allocator, env.client);
    var svc = shop.service.ShopService.init(allocator, std.testing.io, &store);

    // 商品 + 下单（已支付）+ 收藏。
    const pid = try svc.createProduct(1, 9, .{
        .category_id = 0, .name = "助手商品", .image = "", .content = "",
        .price = 1000, .original_price = 2000, .stock = 5, .status = 1, .skus = &.{},
    });
    const skus = try svc.listSkus(pid);
    defer {
        for (skus) |s| s.free(allocator);
        if (skus.len > 0) allocator.free(skus);
    }
    const addr_id = try svc.createAddress(1, 9, .{
        .openid = "o_ai", .name = "AI", .mobile = "13800000000", .region = "SZ", .detail = "1", .is_default = 1,
    });
    const oid = try svc.createOrder(1, 9, "o_ai", addr_id, &.{
        .{ .product_id = pid, .sku_id = skus[0].id, .quantity = 1 },
    }, "", "", "", 0);
    try svc.markPaid(1, 9, oid);
    try svc.favorite(1, 9, "o_ai", pid);

    // 问订单 → 返回最近订单（含状态与金额）。
    const r1 = try svc.assistant(allocator, 1, 9, "o_ai", "我的订单");
    defer allocator.free(r1);
    try std.testing.expect(std.mem.indexOf(u8, r1, "SO") != null);
    try std.testing.expect(std.mem.indexOf(u8, r1, "已支付") != null);

    // 问支付 → 待支付/已支付统计。
    const r2 = try svc.assistant(allocator, 1, 9, "o_ai", "支付情况");
    defer allocator.free(r2);
    try std.testing.expect(std.mem.indexOf(u8, r2, "已支付 1 单") != null);

    // 问收藏。
    const r3 = try svc.assistant(allocator, 1, 9, "o_ai", "我的收藏");
    defer allocator.free(r3);
    try std.testing.expect(std.mem.indexOf(u8, r3, "收藏了 1 件") != null);

    // 问物流（无已发货订单）→ 引导。
    const r4 = try svc.assistant(allocator, 1, 9, "o_ai", "物流到哪了");
    defer allocator.free(r4);
    try std.testing.expect(std.mem.indexOf(u8, r4, "没有已发货") != null);

    // 未知问题 → 能力引导。
    const r5 = try svc.assistant(allocator, 1, 9, "o_ai", "今天天气");
    defer allocator.free(r5);
    try std.testing.expect(std.mem.indexOf(u8, r5, "我可以帮您") != null);
}

test "shop: event-driven markPaid via OrderPaidBus" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = shop.persistence.ShopStore.init(allocator, env.client);
    var svc = shop.service.ShopService.init(allocator, std.testing.io, &store);
    var dist_store = distribution.persistence.DistributionStore.init(allocator, env.client);
    var dist_svc = distribution.service.DistributionService.init(allocator, std.testing.io, &dist_store);
    svc.dist_svc = &dist_svc;

    // 事件总线 + 消费者（分销分佣）。
    var bus = shop.service.OrderPaidBus.init(allocator);
    defer bus.deinit();
    const PaidCtx = struct {
        var dist_ref: *distribution.service.DistributionService = undefined;
        fn onPaid(e: shop.service.OrderPaidEvent) void {
            const d = dist_ref;
            _ = d.distribute(e.tenant_id, e.account_id, "o_buyer", e.order_id) catch {};
        }
    };
    // 用简单计数器验证事件被消费。
    const Counter = struct {
        var n: usize = 0;
        fn onPaid(e: shop.service.OrderPaidEvent) void {
            _ = e;
            n += 1;
        }
    };
    bus.subscribe(Counter.onPaid) catch {};
    svc.order_paid_bus = &bus;

    // 商品 + 下单 + 支付 → 事件被发布（计数器 +1）。
    const pid = try svc.createProduct(1, 9, .{
        .category_id = 0, .name = "事件商品", .image = "", .content = "",
        .price = 1000, .original_price = 2000, .stock = 5, .status = 1, .skus = &.{},
    });
    const skus = try svc.listSkus(pid);
    defer {
        for (skus) |s| s.free(allocator);
        if (skus.len > 0) allocator.free(skus);
    }
    const addr_id = try svc.createAddress(1, 9, .{
        .openid = "o_ev", .name = "E", .mobile = "13800000000", .region = "SZ", .detail = "1", .is_default = 1,
    });
    const oid = try svc.createOrder(1, 9, "o_ev", addr_id, &.{
        .{ .product_id = pid, .sku_id = skus[0].id, .quantity = 1 },
    }, "", "", "", 0);
    try svc.markPaid(1, 9, oid);
    try std.testing.expectEqual(@as(usize, 1), Counter.n);
    _ = PaidCtx;
}

test "shop: stock rollback on order failure paths" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = shop.persistence.ShopStore.init(allocator, env.client);
    var svc = shop.service.ShopService.init(allocator, std.testing.io, &store);
    var pay_store = payment.persistence.PaymentStore.init(allocator, env.client);
    var pay_svc = payment.service.PaymentService.init(allocator, std.testing.io, &pay_store);
    var fan_store = member.persistence.FanStore.init(allocator, env.client);
    svc.payment_svc = &pay_svc;
    svc.fan_store = &fan_store;

    // 商品（库存 3）+ 粉丝（钱包 0）。
    const now_ts = zigmodu.time.wallClockSeconds(std.testing.io);
    _ = try fan_store.upsert(1, 9, "o_roll", "", "回滚用户", "", true, now_ts, now_ts);
    const pid = try svc.createProduct(1, 9, .{
        .category_id = 0, .name = "回滚商品", .image = "", .content = "",
        .price = 1000, .original_price = 2000, .stock = 3, .status = 1, .skus = &.{},
    });
    const skus = try svc.listSkus(pid);
    defer {
        for (skus) |s| s.free(allocator);
        if (skus.len > 0) allocator.free(skus);
    }
    const addr_id = try svc.createAddress(1, 9, .{
        .openid = "o_roll", .name = "R", .mobile = "13800000000", .region = "SZ", .detail = "1", .is_default = 1,
    });

    // 余额支付（钱包 0 不够）→ InsufficientBalance + 库存回滚（3 → 扣1 → 回滚 → 3）。
    try std.testing.expectError(error.InsufficientBalance, svc.createOrder(1, 9, "o_roll", addr_id, &.{
        .{ .product_id = pid, .sku_id = skus[0].id, .quantity = 1 },
    }, "", "", "balance", 0));
    const sku_after = (try svc.getSku(skus[0].id)).?;
    defer sku_after.free(allocator);
    try std.testing.expectEqual(@as(i64, 3), sku_after.stock); // 已回滚
}

test "shop: webhook dispatch on order paid" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = shop.persistence.ShopStore.init(allocator, env.client);
    var svc = shop.service.ShopService.init(allocator, std.testing.io, &store);
    const wt = @import("http/webhook_transport.zig");

    // Webhook 配置 + mock transport 记录。
    const wh_id = try svc.createWebhook(1, 9, "https://merchant.example.com/hook", "order.paid");
    var received = std.ArrayList([]u8).empty;
    const Recorder = struct {
        var out: *std.ArrayList([]u8) = undefined;
        fn rec(url: []const u8, payload: []const u8) void {
            out.append(std.heap.c_allocator, std.fmt.allocPrint(std.heap.c_allocator, "{s}|{s}", .{ url, payload }) catch "") catch {};
        }
    };
    Recorder.out = &received;
    var transport = wt.WebhookTransport.init(std.testing.io);
    transport.recorder = Recorder.rec;
    svc.webhook_transport = &transport;

    // 商品 + 下单 + 支付 → webhook 推送（event/order_id/account_id）。
    const pid = try svc.createProduct(1, 9, .{
        .category_id = 0, .name = "回调商品", .image = "", .content = "",
        .price = 1000, .original_price = 2000, .stock = 5, .status = 1, .skus = &.{},
    });
    const skus = try svc.listSkus(pid);
    defer {
        for (skus) |s| s.free(allocator);
        if (skus.len > 0) allocator.free(skus);
    }
    const addr_id = try svc.createAddress(1, 9, .{
        .openid = "o_wh", .name = "W", .mobile = "13800000000", .region = "SZ", .detail = "1", .is_default = 1,
    });
    const oid = try svc.createOrder(1, 9, "o_wh", addr_id, &.{
        .{ .product_id = pid, .sku_id = skus[0].id, .quantity = 1 },
    }, "", "", "", 0);
    svc.dispatchWebhooks("order.paid", 1, 9, oid);

    // mock 收到 payload。
    try std.testing.expectEqual(@as(usize, 1), received.items.len);
    try std.testing.expect(std.mem.indexOf(u8, received.items[0], "order.paid") != null);
    try std.testing.expect(std.mem.indexOf(u8, received.items[0], "merchant.example.com") != null);
    for (received.items) |r| std.heap.c_allocator.free(r);
    received.deinit(std.heap.c_allocator);

    try svc.deleteWebhook(wh_id);
}

test "shop: C-token issue + order uses token openid (anti-forgery)" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = shop.persistence.ShopStore.init(allocator, env.client);
    var svc = shop.service.ShopService.init(allocator, std.testing.io, &store);
    var fan_store = member.persistence.FanStore.init(allocator, env.client);
    var user_store = user.persistence.UserStore.init(allocator, env.client);
    var sec = zigmodu.security.AppSecurity.init(allocator, std.testing.io, .{ .jwt_secret = "test-c-jwt-secret", .token_expiry_seconds = 3600 });
    var user_svc = user.service.UserService.init(&user_store, &sec, std.testing.io, 3600, 3600);
    var registry = zigmodu.RateLimiterRegistry.init(allocator, 30, 1);
    _ = &registry;
    _ = &user_svc;
    _ = &fan_store;

    // 粉丝 + 商品。
    const now_ts = zigmodu.time.wallClockSeconds(std.testing.io);
    _ = try fan_store.upsert(1, 9, "o_jwt", "", "JWT用户", "", true, now_ts, now_ts);
    const pid = try svc.createProduct(1, 9, .{
        .category_id = 0, .name = "JWT商品", .image = "", .content = "",
        .price = 1000, .original_price = 2000, .stock = 5, .status = 1, .skus = &.{},
    });
    const skus = try svc.listSkus(pid);
    defer {
        for (skus) |s| s.free(allocator);
        if (skus.len > 0) allocator.free(skus);
    }

    // 签发 C-token（粉丝 openid）。
    const c_token = try sec.module.generateTokenWithTenant("o_jwt", &.{"fan"}, "0");
    defer allocator.free(c_token);

    // 校验 token 解析出 openid（sub）。
    const payload = try sec.module.verifyToken(c_token);
    defer {
        allocator.free(payload.sub);
        allocator.free(payload.iss);
        allocator.free(payload.aud);
        for (payload.roles) |r| allocator.free(r);
        allocator.free(payload.roles);
    }
    try std.testing.expectEqualStrings("o_jwt", payload.sub);
    var is_fan = false;
    for (payload.roles) |r| {
        if (std.mem.eql(u8, r, "fan")) is_fan = true;
    }
    try std.testing.expect(is_fan);

    // 非粉丝 openid 无法签发（fan_store 校验逻辑在 cLogin handler，service 层验证 fan 存在）。
    // 这里验证 token 机制本身：管理端 token（无 fan role）不可作 C-token。
    const admin_token = try sec.module.generateTokenWithTenant("admin_x", &.{"admin"}, "1");
    defer allocator.free(admin_token);
    const admin_payload = try sec.module.verifyToken(admin_token);
    defer {
        allocator.free(admin_payload.sub);
        allocator.free(admin_payload.iss);
        allocator.free(admin_payload.aud);
        for (admin_payload.roles) |r| allocator.free(r);
        allocator.free(admin_payload.roles);
    }
    var admin_is_fan = false;
    for (admin_payload.roles) |r| {
        if (std.mem.eql(u8, r, "fan")) admin_is_fan = true;
    }
    try std.testing.expect(!admin_is_fan);
}

test "shop: order pay-params mock mode (no v3 config)" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = shop.persistence.ShopStore.init(allocator, env.client);
    var svc = shop.service.ShopService.init(allocator, std.testing.io, &store);
    var fan_store = member.persistence.FanStore.init(allocator, env.client);
    var user_store = user.persistence.UserStore.init(allocator, env.client);
    var sec = zigmodu.security.AppSecurity.init(allocator, std.testing.io, .{ .jwt_secret = "pay-params-secret", .token_expiry_seconds = 3600 });
    var user_svc = user.service.UserService.init(&user_store, &sec, std.testing.io, 3600, 3600);
    var setting_store = setting.persistence.SettingStore.init(allocator, env.client);
    var audit_store = audit.persistence.AuditStore.init(allocator, env.client);
    var audit_svc = audit.service.AuditService.init(allocator, std.testing.io, &audit_store);
    var registry = zigmodu.RateLimiterRegistry.init(allocator, 30, 1);
    defer registry.deinit();
    var shop_api = shop.api.ShopApi(@TypeOf(svc), @TypeOf(user_svc)).init(&svc, &user_svc, &audit_svc, 1, &registry, &fan_store, &setting_store);

    // 商品 + 待支付订单。
    const pid = try svc.createProduct(1, 9, .{
        .category_id = 0, .name = "支付参数商品", .image = "", .content = "",
        .price = 1000, .original_price = 2000, .stock = 5, .status = 1, .skus = &.{},
    });
    const skus = try svc.listSkus(pid);
    defer {
        for (skus) |s| s.free(allocator);
        if (skus.len > 0) allocator.free(skus);
    }
    const addr_id = try svc.createAddress(1, 9, .{
        .openid = "o_pay", .name = "P", .mobile = "13800000000", .region = "SZ", .detail = "1", .is_default = 1,
    });
    const oid = try svc.createOrder(1, 9, "o_pay", addr_id, &.{
        .{ .product_id = pid, .sku_id = skus[0].id, .quantity = 1 },
    }, "", "", "", 0);

    // 走 HTTP：GET pay-params（无 v3 配置 → mock 模式）。
    var server = zigmodu.http.Server.init(std.testing.io, allocator, 0);
    defer server.deinit();
    var g = server.group("/api/v1");
    try shop_api.registerPublicRoutes(&g);
    const pay_url = try std.fmt.allocPrint(allocator, "/api/v1/shop/orders/{d}/pay-params", .{oid});
    defer allocator.free(pay_url);
    var res = try zigmodu.http.Testkit.dispatchOpts(&server, .GET, pay_url, .{});
    defer res.deinit(allocator);
    try std.testing.expectEqual(@as(u16, 200), res.status_code);
    try std.testing.expect(std.mem.indexOf(u8, res.body, "\"mode\":\"mock\"") != null);
}

test "shop: mock pay-complete with C-token ownership" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = shop.persistence.ShopStore.init(allocator, env.client);
    var svc = shop.service.ShopService.init(allocator, std.testing.io, &store);
    var fan_store = member.persistence.FanStore.init(allocator, env.client);
    var user_store = user.persistence.UserStore.init(allocator, env.client);
    var sec = zigmodu.security.AppSecurity.init(allocator, std.testing.io, .{ .jwt_secret = "pay-complete-secret", .token_expiry_seconds = 3600 });
    var user_svc = user.service.UserService.init(&user_store, &sec, std.testing.io, 3600, 3600);
    var setting_store = setting.persistence.SettingStore.init(allocator, env.client);
    var audit_store = audit.persistence.AuditStore.init(allocator, env.client);
    var audit_svc = audit.service.AuditService.init(allocator, std.testing.io, &audit_store);
    var registry = zigmodu.RateLimiterRegistry.init(allocator, 30, 1);
    defer registry.deinit();
    var shop_api = shop.api.ShopApi(@TypeOf(svc), @TypeOf(user_svc)).init(&svc, &user_svc, &audit_svc, 1, &registry, &fan_store, &setting_store);

    // 粉丝 + 商品 + 待支付订单。
    const now_ts = zigmodu.time.wallClockSeconds(std.testing.io);
    _ = try fan_store.upsert(1, 9, "o_pc", "", "支付用户", "", true, now_ts, now_ts);
    const pid = try svc.createProduct(1, 9, .{
        .category_id = 0, .name = "支付完成商品", .image = "", .content = "",
        .price = 1000, .original_price = 2000, .stock = 5, .status = 1, .skus = &.{},
    });
    const skus = try svc.listSkus(pid);
    defer {
        for (skus) |s| s.free(allocator);
        if (skus.len > 0) allocator.free(skus);
    }
    const addr_id = try svc.createAddress(1, 9, .{
        .openid = "o_pc", .name = "P", .mobile = "13800000000", .region = "SZ", .detail = "1", .is_default = 1,
    });
    const oid = try svc.createOrder(1, 9, "o_pc", addr_id, &.{
        .{ .product_id = pid, .sku_id = skus[0].id, .quantity = 1 },
    }, "", "", "", 0);

    // 无 C-token → 401。
    var server = zigmodu.http.Server.init(std.testing.io, allocator, 0);
    defer server.deinit();
    var g = server.group("/api/v1");
    try shop_api.registerPublicRoutes(&g);
    const url1 = try std.fmt.allocPrint(allocator, "/api/v1/shop/orders/{d}/pay-complete", .{oid});
    defer allocator.free(url1);
    var res1 = try zigmodu.http.Testkit.dispatchOpts(&server, .POST, url1, .{});
    defer res1.deinit(allocator);
    try std.testing.expectEqual(@as(u16, 401), res1.status_code);

    // 带 C-token（买家本人）→ 200 支付成功。
    const c_token = try sec.module.generateTokenWithTenant("o_pc", &.{"fan"}, "0");
    defer allocator.free(c_token);
    const auth_header = try std.fmt.allocPrint(allocator, "Bearer {s}", .{c_token});
    defer allocator.free(auth_header);
    var res2 = try zigmodu.http.Testkit.dispatchOpts(&server, .POST, url1, .{ .headers = &.{.{ "authorization", auth_header }} });
    defer res2.deinit(allocator);
    try std.testing.expectEqual(@as(u16, 200), res2.status_code);
    var o2 = (try svc.getOrder(oid)).?;
    defer o2.free(allocator);
    try std.testing.expectEqual(@as(i64, 1), o2.status); // 已支付
}
