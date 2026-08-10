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
const cache_svc = @import("services/cache.zig");
const mail = @import("services/mail.zig");

/// In-memory SQLite store with every schema group migrated.
fn openMemory(allocator: std.mem.Allocator) !db_mod.StoreEnv(schema.infos, .{
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
}) {
    return db_mod.StoreEnv(schema.infos, .{
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
    }).open(allocator, .sqlite, ":memory:");
}

test "health: zigmodu + zent importable together" {
    _ = zigmodu;
    _ = zent;
    try std.testing.expect(true);
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

test "HTTP dispatch: public auth flow (register -> me) via Testkit" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = user.persistence.UserStore.init(allocator, env.client);
    var sec = zigmodu.security.AppSecurity.init(allocator, std.testing.io, .{ .jwt_secret = "testkit-secret" });
    var svc = user.service.UserService.init(&store, &sec, std.testing.io, 3600, 86400);
    var limiter = try zigmodu.RateLimiter.init(allocator, "test", 100, 1);
    defer limiter.deinit();
    var mailer = mail.Mailer.init(allocator, std.testing.io, "", 587, "", "", "test@localhost", true, false);
    var task_store = task.persistence.TaskStore.init(allocator, env.client);
    var task_svc = task.service.TaskService.init(&task_store, std.testing.io, 3);
    var notify_store = notify.persistence.NotificationStore.init(allocator, env.client);
    var notify_svc = notify.service.NotificationService.init(allocator, std.testing.io, &notify_store);
    var audit_store = audit.persistence.AuditStore.init(allocator, env.client);
    var audit_svc = audit.service.AuditService.init(allocator, std.testing.io, &audit_store);
    var template_store = mail_template.persistence.TemplateStore.init(allocator, env.client);
    var template_svc = mail_template.service.MailTemplateService.init(allocator, std.testing.io, &template_store);
    var auth_api = auth.api.AuthApi(@TypeOf(svc)).init(&svc, "http://localhost:3001", &limiter, &mailer, &task_svc, &notify_svc, &audit_svc, &template_svc, 1);

    var server = zigmodu.http.Server.init(std.testing.io, allocator, 0);
    defer server.deinit();
    var g = server.group("/api/v1");
    try auth_api.registerRoutes(&g);

    var resp = try zigmodu.http.Testkit.dispatch(&server, .POST, "/api/v1/auth/register", "{\"name\":\"Tester\",\"email\":\"t@example.com\",\"password\":\"password123\"}");
    defer resp.deinit(allocator);
    try std.testing.expectEqual(@as(u16, 201), resp.status_code);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"code\":0") != null);
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
    const ts = "1700000000";
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
    const ts = "1700000000";
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
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var module_store = appmod.persistence.ModuleStore.init(allocator, env.client);
    var module_svc = appmod.service.ModuleService.init(allocator, std.testing.io, &module_store);
    var cloud_store = cloud.persistence.CloudStore.init(allocator, env.client);
    var cloud_svc = cloud.service.CloudService.init(allocator, std.testing.io, &cloud_store, &module_svc);

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
    _ = try cloud_svc.publishPackage(1, "shop", "商城", "1.0.0", "多商户商城", "https://cdn.example.com/shop.zip");
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
    var material_svc = material.service.MaterialService.init(allocator, std.testing.io, &material_store);

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

    _ = try ai_store.createRun(0, 7, 1, "chat", "hi", 0, 0, "ok", "", 100);
    _ = try ai_store.createRun(0, 7, 1, "chat", "hi", 0, 0, "ok", "", 200);
    _ = try ai_store.createRun(0, 8, 1, "chat", "hi", 0, 0, "ok", "", 300);
    try std.testing.expectEqual(@as(i64, 2), try ai_store.runCountForUser(7, 50));

    // 无 LLM 的健康工作流:两个只读技能按序执行。
    var result = try svc.runHealthWorkflow(allocator, 1, 1);
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 2), result.steps.items.len);
    try std.testing.expectEqualStrings("task_stats", result.steps.items[0].name);
    try std.testing.expectEqualStrings("tenant_list", result.steps.items[1].name);
}
