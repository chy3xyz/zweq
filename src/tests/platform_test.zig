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
const scheduled = @import("../scheduled.zig");

test "task queue: enqueue -> claim -> done" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var task_store = task.persistence.TaskStore.init(allocator, env.client);
    var task_svc = task.service.TaskService.init(&task_store, std.testing.io, 3);

    const id = try task_svc.enqueueNow("mail.send", "{}", 1);
    const claimed = (try task_store.claimNext(1000, "disp-a-1", 300)).?;
    defer claimed.free(allocator);
    try std.testing.expectEqual(id, claimed.id);
    try std.testing.expectEqualStrings("claimed", claimed.status);
    // fencing token:owner 写入,租约 = now + stale_after。
    try std.testing.expectEqualStrings("disp-a-1", claimed.claim_owner);
    try std.testing.expectEqual(@as(i64, 1300), claimed.claimed_until);
    try std.testing.expect(try task_store.markDone(id, "disp-a-1", 1001));
    const row = (try task_store.getTaskById(id)).?;
    defer row.free(allocator);
    try std.testing.expectEqualStrings("done", row.status);
    // 已终结的行不再接受任何收尾写(fencing 谓词 status='claimed')。
    try std.testing.expect(!(try task_store.markDone(id, "disp-a-1", 1002)));
}

test "task queue: retry backoff and failure budget" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var task_store = task.persistence.TaskStore.init(allocator, env.client);

    const id = try task_store.createTask("mail.send", "{}", "pending", 1, 0, 2, "", 0, 100);
    const c1 = (try task_store.claimNext(100, "disp-a-1", 300)).?;
    defer c1.free(allocator);
    try std.testing.expect(try task_store.markFailedOrRetry(id, c1.claim_owner, c1.attempts, c1.max_attempts, "boom", 200, 60));
    const after = (try task_store.getTaskById(id)).?;
    defer after.free(allocator);
    try std.testing.expectEqualStrings("pending", after.status);
    try std.testing.expectEqual(@as(i64, 260), after.available_at);
    // 重试排队后 fencing 已清零,旧 token 不能再写。
    try std.testing.expectEqualStrings("", after.claim_owner);
    try std.testing.expect(!(try task_store.markFailedOrRetry(id, "disp-a-1", 1, 2, "late", 250, 60)));

    const c2 = (try task_store.claimNext(300, "disp-b-1", 300)).?;
    defer c2.free(allocator);
    try std.testing.expect(try task_store.markFailedOrRetry(id, c2.claim_owner, c2.attempts, c2.max_attempts, "boom", 300, 60));
    const failed = (try task_store.getTaskById(id)).?;
    defer failed.free(allocator);
    try std.testing.expectEqualStrings("failed", failed.status);
}

test "jobs: webhook.deliver 2xx/4xx/5xx/网络错误 重试语义" {
    const allocator = std.testing.allocator;
    const wt = @import("../http/webhook_transport.zig");
    const jobs = @import("../jobs.zig");

    // mock transport：记录 (url, payload)，状态码/网络错误可注入。
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

    // 与生产同惯例序列化任务参数（payload 是内嵌 JSON 文本，需转义）。
    const task_payload = try std.fmt.allocPrint(allocator, "{f}", .{std.json.fmt(.{
        .endpoint = "https://merchant.example.com/hook",
        .event = "order.paid",
        .payload = "{\"event\":\"order.paid\",\"order_id\":7,\"account_id\":9}",
    }, .{})});
    defer allocator.free(task_payload);

    // 2xx → 成功（handler 正常返回，Dispatcher 记 done）。
    transport.mock_status = 200;
    try jobs.webhookDeliver(&transport, allocator, std.testing.io, task_payload);

    // 4xx → 对端拒绝：按成功收尾，任务终态不再重试。
    transport.mock_status = 400;
    try jobs.webhookDeliver(&transport, allocator, std.testing.io, task_payload);

    // 5xx → 返回 error，Dispatcher markFailedOrRetry 退避重试。
    transport.mock_status = 500;
    try std.testing.expectError(error.WebhookServerError, jobs.webhookDeliver(&transport, allocator, std.testing.io, task_payload));

    // 网络错误 → 同样返回 error 触发重试。
    transport.mock_error = error.ConnectionRefused;
    try std.testing.expectError(error.WebhookTransportFailed, jobs.webhookDeliver(&transport, allocator, std.testing.io, task_payload));
    transport.mock_error = null;

    // 四次投递全部到达 mock，且内嵌 JSON 文本完整往返。
    try std.testing.expectEqual(@as(usize, 4), received.items.len);
    try std.testing.expect(std.mem.indexOf(u8, received.items[0], "merchant.example.com/hook") != null);
    try std.testing.expect(std.mem.indexOf(u8, received.items[0], "\"order_id\":7") != null);

    // 畸形 payload → BadPayload（Dispatcher 侧同样走失败链路，不 panic）。
    try std.testing.expectError(error.BadPayload, jobs.webhookDeliver(&transport, allocator, std.testing.io, "not-json"));

    for (received.items) |r| std.heap.c_allocator.free(r);
    received.deinit(std.heap.c_allocator);
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

    const id = try file_store.create("a.txt", "key1", "text/plain", 4, 9, 1, 0, 100);
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

test "file: upload content sniffing rejects spoofed active content" {
    const UploadGuard = zigmodu.http.UploadGuard;
    // 用的就是生产策略本身，策略漂移会被这条钉住。
    const policy = file.service.upload_policy;
    // 声明头由客户端写、可伪造：`说明.png` + `image/png` 里装 HTML —— 字节嗅探必须拦下。
    try std.testing.expectError(error.ActiveContentNotAllowed, UploadGuard.check("说明.png", "<html><script>alert(1)</script></html>", policy));
    try std.testing.expectError(error.ActiveContentNotAllowed, UploadGuard.check("logo.svg", "<svg xmlns=\"http://www.w3.org/2000/svg\"><script/></svg>", policy));
    // 反向：真实 PNG 字节即便扩展名不符也放行——通用文件管理故意**不**要求扩展名与
    // 内容一致（docx/xlsx 内容本就是 ZIP、heic/rar 无魔数，对齐会把正常上传判死）。
    const png = "\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01";
    _ = try UploadGuard.check("photo.bin", png, policy);
    // 无魔数的二进制同样放行：unknown 不等于主动内容。
    _ = try UploadGuard.check("blob.dat", "\x01\x02\x03\x04\x05", policy);
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

    _ = try file_store.create("t1.txt", "k1", "text/plain", 3, 1, 1, 0, 100);
    _ = try file_store.create("t2.txt", "k2", "text/plain", 3, 1, 2, 0, 101);

    var tenant1 = try file_store.list(1, 20, null, 1, 0, null, null, false);
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

test "cron lock: 两副本抢同一把锁只有一个成功,过期后可接管" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    // 两个 store 对象共用同一个 DB,模拟两个副本。
    var store_a = task.persistence.CronLockStore.init(allocator, env.client);
    var store_b = task.persistence.CronLockStore.init(allocator, env.client);

    // 首抢:A 插入成功,B 撞未过期租约失败。
    try std.testing.expect(try store_a.tryLock("tokens.cleanup", "sched-a", 1000, 300));
    try std.testing.expect(!(try store_b.tryLock("tokens.cleanup", "sched-b", 1000, 300)));

    // A 的自有未过期租约可直接续期(CAS on expires_at),续期后 B 仍失败。
    try std.testing.expect(try store_a.tryLock("tokens.cleanup", "sched-a", 1100, 300));
    try std.testing.expect(!(try store_b.tryLock("tokens.cleanup", "sched-b", 1200, 300)));

    // A 崩溃:租约(1100 续期至 1400)过期后,B 在 1500 CAS 接管,
    // 此后 A 的迟到续期(锁已是别人的)失败。
    try std.testing.expect(try store_b.tryLock("tokens.cleanup", "sched-b", 1500, 300));
    try std.testing.expect(!(try store_a.tryLock("tokens.cleanup", "sched-a", 1600, 300)));
}

test "scheduled runner: 两副本同 tick 只有一副本执行 job,crash 后另一副本接管" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var lock_store = task.persistence.CronLockStore.init(allocator, env.client);

    const Ctx = struct { counter: *std.atomic.Value(u32) };
    const S = struct {
        fn run(ctx: ?*anyopaque) void {
            const c: *Ctx = @ptrCast(@alignCast(ctx.?));
            _ = c.counter.fetchAdd(1, .monotonic);
        }
    };
    var counter = std.atomic.Value(u32).init(0);
    var ctx = Ctx{ .counter = &counter };

    var jobs_a = [_]scheduled.ScheduledJob{.{ .name = "notify.prune", .interval_seconds = 10, .run = S.run, .ctx = &ctx }};
    var jobs_b = [_]scheduled.ScheduledJob{.{ .name = "notify.prune", .interval_seconds = 10, .run = S.run, .ctx = &ctx }};
    var runner_a = scheduled.ScheduledRunner{ .jobs = &jobs_a, .lock_store = &lock_store };
    var runner_b = scheduled.ScheduledRunner{ .jobs = &jobs_b, .lock_store = &lock_store };

    // 同一周期两副本都到点:只有持锁副本真正执行。
    runner_a.tick(1000);
    runner_b.tick(1000);
    try std.testing.expectEqual(@as(u32, 1), counter.load(.monotonic));

    // 下一周期:A 对自有租约续期执行,B 让位。
    runner_a.tick(1010);
    runner_b.tick(1010);
    try std.testing.expectEqual(@as(u32, 2), counter.load(.monotonic));

    // A 崩溃:租约 TTL = max(10×2, 300) = 300,过期于 1310。
    // B 一直让位(推进 last_run),租约过期后接管执行。
    var t: i64 = 1020;
    while (t <= 1310) : (t += 10) runner_b.tick(t);
    try std.testing.expectEqual(@as(u32, 3), counter.load(.monotonic));
}

test "task fencing: requeue 不回收未过期认领,迟到的 markDone 被拒不写穿" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var task_store = task.persistence.TaskStore.init(allocator, env.client);

    const id = try task_store.createTask("mail.send", "{}", "pending", 1, 0, 3, "", 0, 100);
    // A 在 now=1000 抢单,租约到 1300。
    const claimed_a = (try task_store.claimNext(1000, "disp-a-1", 300)).?;
    defer claimed_a.free(allocator);
    try std.testing.expectEqualStrings("disp-a-1", claimed_a.claim_owner);

    // 租约未过期(1200 < 1300):B requeue 抢不走。
    try std.testing.expectEqual(@as(usize, 0), try task_store.requeueStale(1200, 300));
    var row = (try task_store.getTaskById(id)).?;
    try std.testing.expectEqualStrings("claimed", row.status);
    try std.testing.expectEqualStrings("disp-a-1", row.claim_owner);
    row.free(allocator);

    // A 跑超时(crash 假象):1400 已过租约,requeue 收回 → pending,fencing 清零。
    try std.testing.expectEqual(@as(usize, 1), try task_store.requeueStale(1400, 300));
    var row2 = (try task_store.getTaskById(id)).?;
    try std.testing.expectEqualStrings("pending", row2.status);
    try std.testing.expectEqualStrings("", row2.claim_owner);
    try std.testing.expectEqual(@as(i64, 0), row2.claimed_until);
    row2.free(allocator);

    // B 重新抢单,拿到新 fencing token。
    const claimed_b = (try task_store.claimNext(1400, "disp-b-1", 300)).?;
    defer claimed_b.free(allocator);
    try std.testing.expectEqualStrings("disp-b-1", claimed_b.claim_owner);

    // A 的迟到 markDone:token 已易主 → false,状态不被写穿。
    try std.testing.expect(!(try task_store.markDone(id, "disp-a-1", 1500)));
    var row3 = (try task_store.getTaskById(id)).?;
    try std.testing.expectEqualStrings("claimed", row3.status);
    try std.testing.expectEqualStrings("disp-b-1", row3.claim_owner);
    row3.free(allocator);

    // A 的迟到 markFailedOrRetry 同样被拒。
    try std.testing.expect(!(try task_store.markFailedOrRetry(id, "disp-a-1", 1, 3, "late", 1500, 60)));

    // 现任 owner B 正常完成:true。
    try std.testing.expect(try task_store.markDone(id, "disp-b-1", 1600));
}
