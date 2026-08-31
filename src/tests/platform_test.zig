//! 基础设施模块：任务队列、通知存储、文件存储（含 XSS 校验）、租户默认引导、审计日志、邮件模板、权限 RBAC、设置 KV、模块注册表。
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

    var result = try tenant_svc.list(1, 20, "", "");
    defer result.free(allocator);
    try std.testing.expectEqual(@as(i64, 2), result.total);
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

test "permission: role_permission binding + effective codes" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var r_store = permission.persistence.RoleStore.init(allocator, env.client);
    var r_svc = permission.service.RoleService.init(allocator, std.testing.io, &r_store);

    const role_id = try r_svc.create(1, "运营", "operator", "");
    const perm_id = try r_svc.grant(1, 0, "shop", "read");
    _ = try r_svc.bindPermission(1, role_id, perm_id);
    _ = try r_svc.assignRole(1, 42, role_id);

    const csv = try r_store.collectPermissionCodes(allocator, 42);
    defer allocator.free(csv);
    try std.testing.expect(std.mem.indexOf(u8, csv, "operator") != null);
    try std.testing.expect(std.mem.indexOf(u8, csv, "shop:read") != null);

    const catalog_permissions = @import("../middleware/catalog_permissions.zig");
    catalog_permissions.init(&r_store);
    const codes = try catalog_permissions.listCodes(allocator, 42);
    defer {
        for (codes) |c| allocator.free(c);
        allocator.free(codes);
    }
    try std.testing.expectEqual(@as(usize, 2), codes.len);
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
