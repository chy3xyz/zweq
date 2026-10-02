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
const mw_auth = @import("common.zig").mw_auth;
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

fn b64urlDecode(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    const dec = std.base64.url_safe_no_pad.Decoder;
    const n = try dec.calcSizeForSlice(s);
    const out = try allocator.alloc(u8, n);
    errdefer allocator.free(out);
    try dec.decode(out, s);
    return out;
}

fn b64urlEncode(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    const enc = std.base64.url_safe_no_pad.Encoder;
    const out = try allocator.alloc(u8, enc.calcSize(s.len));
    errdefer allocator.free(out);
    _ = enc.encode(out, s);
    return out;
}

test "jwt kid: kidForSecret 确定性且互不相同" {
    const k1 = mw_auth.kidForSecret("kid-secret-a-0123456789abcdef");
    const k2 = mw_auth.kidForSecret("kid-secret-a-0123456789abcdef");
    const k3 = mw_auth.kidForSecret("kid-secret-b-0123456789abcdef");
    try std.testing.expectEqual(k1, k2);
    try std.testing.expect(!std.mem.eql(u8, &k1, &k3));
    // 12 个 lowercase hex 字符。
    for (k1) |c| try std.testing.expect(std.mem.indexOfScalar(u8, "0123456789abcdef", c) != null);
}

test "jwt kid: buildJwtKeyring 解析 PREVIOUS csv（去空白/跳过空段/跳过与主密钥重复）" {
    const allocator = std.testing.allocator;
    const cur = "ring-current-secret-0123456789abcdef";
    const old_a = "ring-old-secret-a-0123456789abcdef";
    const old_b = "ring-old-secret-b-0123456789abcdef";
    var ring = try mw_auth.buildJwtKeyring(allocator, cur, "  ring-old-secret-a-0123456789abcdef , , ring-old-secret-b-0123456789abcdef,ring-current-secret-0123456789abcdef ,");
    defer ring.deinit();

    try std.testing.expectEqual(@as(usize, 3), ring.count());
    try std.testing.expectEqualStrings(&mw_auth.kidForSecret(cur), ring.getPrimaryKey().?.kid);
    try std.testing.expect(ring.getKey(&mw_auth.kidForSecret(old_a)) != null);
    try std.testing.expect(ring.getKey(&mw_auth.kidForSecret(old_b)) != null);
}

test "jwt kid: 无 kid 旧 token 挂环后仍验过（回退主密钥）" {
    const allocator = std.testing.allocator;
    const v1 = "rotate-old-secret-0123456789abcdef";
    // 旧行为签发：未挂 keyring，token 无 kid。
    var legacy_sec = zigmodu.security.AppSecurity.init(allocator, std.testing.io, .{ .jwt_secret = v1 });
    const old_token = try legacy_sec.module.generateTokenWithTenant("42", &.{"user"}, "1");
    defer allocator.free(old_token);

    // 部署 keyring（同主密钥、无 PREVIOUS）后旧 token 必须仍验过。
    var ring = try mw_auth.buildJwtKeyring(allocator, v1, "");
    defer ring.deinit();
    var sec = zigmodu.security.AppSecurity.init(allocator, std.testing.io, .{ .jwt_secret = v1 });
    sec.module.setKeyring(&ring);
    const payload = try sec.module.verifyToken(old_token);
    defer sec.module.freePayload(payload);
    try std.testing.expectEqualStrings("42", payload.sub);
}

test "jwt kid: 新 token 带主密钥 kid 签发并按 kid 验签" {
    const allocator = std.testing.allocator;
    const v1 = "signing-secret-v1-0123456789abcdef";
    var ring = try mw_auth.buildJwtKeyring(allocator, v1, "");
    defer ring.deinit();
    var sec = zigmodu.security.AppSecurity.init(allocator, std.testing.io, .{ .jwt_secret = v1 });
    sec.module.setKeyring(&ring);

    const token = try sec.module.generateTokenWithTenantAndVersion("7", &.{"admin"}, "1", 3);
    defer allocator.free(token);

    // header 带主密钥的 kid（无状态派生，重启后不变）。
    try std.testing.expectEqualStrings(&mw_auth.kidForSecret(v1), sec.module.signingKid().?);
    var parts = std.mem.splitScalar(u8, token, '.');
    const header_json = try b64urlDecode(allocator, parts.next().?);
    defer allocator.free(header_json);
    const kid_pat = try std.fmt.allocPrint(allocator, "\"kid\":\"{s}\"", .{&mw_auth.kidForSecret(v1)});
    defer allocator.free(kid_pat);
    try std.testing.expect(std.mem.indexOf(u8, header_json, kid_pat) != null);

    const payload = try sec.module.verifyToken(token);
    defer sec.module.freePayload(payload);
    try std.testing.expectEqualStrings("7", payload.sub);
    try std.testing.expectEqual(@as(i64, 3), payload.ver);
}

test "jwt kid: 轮换窗口双 key 都验过（旧 token 不掉线、新 token 正常）" {
    const allocator = std.testing.allocator;
    const v1 = "rotate-old-secret-0123456789abcdef";
    const v2 = "rotate-new-secret-0123456789abcdef";

    // 轮换前：v1 为主签发键。
    var ring_v1 = try mw_auth.buildJwtKeyring(allocator, v1, "");
    defer ring_v1.deinit();
    var sec_v1 = zigmodu.security.AppSecurity.init(allocator, std.testing.io, .{ .jwt_secret = v1 });
    sec_v1.module.setKeyring(&ring_v1);
    const t_old = try sec_v1.module.generateTokenWithTenant("u-old", &.{"user"}, "1");
    defer allocator.free(t_old);

    // 轮换：v2 顶上为主签发键，v1 挪进 PREVIOUS 只验不签。
    var ring_v2 = try mw_auth.buildJwtKeyring(allocator, v2, v1);
    defer ring_v2.deinit();
    var sec_v2 = zigmodu.security.AppSecurity.init(allocator, std.testing.io, .{ .jwt_secret = v2 });
    sec_v2.module.setKeyring(&ring_v2);

    // 旧 token（kid=v1）在轮换窗口内仍验过 —— 不再全员强制重登。
    const p_old = try sec_v2.module.verifyToken(t_old);
    defer sec_v2.module.freePayload(p_old);
    try std.testing.expectEqualStrings("u-old", p_old.sub);

    // 新 token 由 v2 签发（kid=v2）并验过。
    const t_new = try sec_v2.module.generateTokenWithTenant("u-new", &.{"user"}, "1");
    defer allocator.free(t_new);
    const p_new = try sec_v2.module.verifyToken(t_new);
    defer sec_v2.module.freePayload(p_new);
    try std.testing.expectEqualStrings("u-new", p_new.sub);
    try std.testing.expectEqualStrings(&mw_auth.kidForSecret(v2), sec_v2.module.signingKid().?);
}

test "jwt kid: 环内不存在的 kid 拒绝（UnknownKeyId，不回退主密钥）" {
    const allocator = std.testing.allocator;
    const v1 = "kid-forge-secret-0123456789abcdef";
    var ring = try mw_auth.buildJwtKeyring(allocator, v1, "");
    defer ring.deinit();
    var sec = zigmodu.security.AppSecurity.init(allocator, std.testing.io, .{ .jwt_secret = v1 });
    sec.module.setKeyring(&ring);
    const token = try sec.module.generateTokenWithTenant("u", &.{"user"}, "1");
    defer allocator.free(token);

    // 篡改 header kid 为环内不存在的值，payload/signature 不动：
    // 即使签名本身是主密钥算的，带未知 kid 也必须拒，而不是静默回退。
    var parts = std.mem.splitScalar(u8, token, '.');
    _ = parts.next();
    const payload_b64 = parts.next().?;
    const sig = parts.next().?;
    const forged_header = try b64urlEncode(allocator, "{\"alg\":\"HS256\",\"typ\":\"JWT\",\"kid\":\"no-such-key\"}");
    defer allocator.free(forged_header);
    const forged = try std.fmt.allocPrint(allocator, "{s}.{s}.{s}", .{ forged_header, payload_b64, sig });
    defer allocator.free(forged);
    try std.testing.expectError(error.UnknownKeyId, sec.module.verifyToken(forged));
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
    var cache = cache_svc.CacheService.init(allocator, std.testing.io, 16, 60);
    defer cache.deinit();
    try cache.set("user:1", "{\"name\":\"Alice\"}");
    try std.testing.expectEqualStrings("{\"name\":\"Alice\"}", cache.get("user:1").?);
    try std.testing.expect(cache.remove("user:1"));
    try std.testing.expect(cache.get("user:1") == null);
}

test "cache service setIfAbsent is atomic first-write wins" {
    const allocator = std.testing.allocator;
    var cache = cache_svc.CacheService.init(allocator, std.testing.io, 16, 60);
    defer cache.deinit();
    try std.testing.expect(try cache.setIfAbsent("nonce:a", "1"));
    try std.testing.expect(!(try cache.setIfAbsent("nonce:a", "1")));
    try std.testing.expectEqualStrings("1", cache.get("nonce:a").?);
    try std.testing.expect(cache.remove("nonce:a"));
    try std.testing.expect(try cache.setIfAbsent("nonce:a", "2"));
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
    try std.testing.expectEqual(@as(u16, 200), resp.status_code);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"code\":0") != null);
}

test "rate limit: registry max_keys bounds per-key memory growth" {
    // 键取自 IP / openid（可轮换），无上限即"换一个 key 涨一份内存"；生产配置用
    // mw_rate.registry_max_keys，这里用小上界验证机制本身生效。
    const allocator = std.testing.allocator;
    var registry = zigmodu.RateLimiterRegistry.initWithCapacity(allocator, 5, 1, 8);
    defer registry.deinit();

    var key_buf: [32]u8 = undefined;
    var i: usize = 0;
    while (i < 64) : (i += 1) {
        const key = try std.fmt.bufPrint(&key_buf, "ip-{d}", .{i});
        _ = try registry.getOrCreateForClient(key, 5, 1);
    }
    try std.testing.expect(registry.count() <= 8);
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

test "url_guard: 出站 URL 校验（SSRF 基线）" {
    const url_guard = @import("../http/url_guard.zig");
    // 合法：https / http / 带端口。
    try std.testing.expect(url_guard.isAcceptableOutboundUrl("https://api.openai.com/v1/chat"));
    try std.testing.expect(url_guard.isAcceptableOutboundUrl("http://example.com/webhook"));
    try std.testing.expect(url_guard.isAcceptableOutboundUrl("https://api.example.com:8443/hook"));
    // 拒绝：非 http(s) scheme 与空 host。
    try std.testing.expect(!url_guard.isAcceptableOutboundUrl("ftp://example.com/file"));
    try std.testing.expect(!url_guard.isAcceptableOutboundUrl("file:///etc/passwd"));
    try std.testing.expect(!url_guard.isAcceptableOutboundUrl(""));
    try std.testing.expect(!url_guard.isAcceptableOutboundUrl("http://"));
    try std.testing.expect(!url_guard.isAcceptableOutboundUrl("https:///path"));
    // 拒绝：字面回环/内网地址。
    try std.testing.expect(!url_guard.isAcceptableOutboundUrl("http://localhost/hook"));
    try std.testing.expect(!url_guard.isAcceptableOutboundUrl("http://localhost:9000/hook"));
    try std.testing.expect(!url_guard.isAcceptableOutboundUrl("http://127.0.0.1/hook"));
    try std.testing.expect(!url_guard.isAcceptableOutboundUrl("http://10.1.2.3/hook"));
    try std.testing.expect(!url_guard.isAcceptableOutboundUrl("http://172.16.0.9/hook"));
    try std.testing.expect(!url_guard.isAcceptableOutboundUrl("http://172.31.255.255/hook"));
    try std.testing.expect(!url_guard.isAcceptableOutboundUrl("http://192.168.1.4/hook"));
    try std.testing.expect(!url_guard.isAcceptableOutboundUrl("http://169.254.169.254/latest/meta-data"));
    try std.testing.expect(!url_guard.isAcceptableOutboundUrl("http://[::1]/hook"));
    try std.testing.expect(!url_guard.isAcceptableOutboundUrl("http://[::1]:8080/hook"));
    // 边界：172.15 / 172.32 不在私网段，字面判断下放行。
    try std.testing.expect(url_guard.isAcceptableOutboundUrl("http://172.15.0.1/hook"));
    try std.testing.expect(url_guard.isAcceptableOutboundUrl("http://172.32.0.1/hook"));
}
