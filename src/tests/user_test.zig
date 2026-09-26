//! 用户与会话：资料更新、邮箱占用检测、密码 token、邮箱验证、改密、注册租户绑定（JWT aud）、用户列表租户过滤、token_version 会话吊销。
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
    // zigmodu 0.33.4 起存储哈希必须可解码：verifyPassword 对畸形哈希报 MalformedStoredHash
    // （我们这侧出错 → 500），不再折成"口令不匹配"。所以这里必须存真实哈希，
    // "旧口令不对"的场景要由合法哈希 + 错误口令来覆盖。
    const real_hash = try sec.module.hashPassword("oldpassword123");
    defer sec.module.allocator.free(real_hash);
    const id = try store.createUser("Alice", "alice@example.com", real_hash, false, false, 1, 100);

    // 旧口令不对（存储哈希合法，verifyPassword 返回 false）→ InvalidCredentials
    try std.testing.expectError(error.InvalidCredentials, svc.changePassword(id, "wrong", "newpassword123"));
    // 新口令太短在校验旧口令之前拦截 → InvalidPassword
    try std.testing.expectError(error.InvalidPassword, svc.changePassword(id, "oldpassword123", "short"));
    // 正确旧口令 → 修改成功，新口令可登录
    try svc.changePassword(id, "oldpassword123", "newpassword123");
    var session = (try svc.login(allocator, "alice@example.com", "newpassword123")) orelse return error.InvalidCredentials;
    defer svc.freeSession(&session);
}

test "register binds tenant and JWT aud carries it" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = user.persistence.UserStore.init(allocator, env.client);
    var sec = zigmodu.security.AppSecurity.init(allocator, std.testing.io, .{ .jwt_secret = "test-secret" });
    var svc = user.service.UserService.init(&store, &sec, std.testing.io, 3600, 86400);

    var session = try svc.register(allocator, "Alice", "alice@example.com", "password123", false, 7);
    defer svc.freeSession(&session);
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

test "session revocation: token_version bump invalidates old JWTs" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = user.persistence.UserStore.init(allocator, env.client);
    var sec = zigmodu.security.AppSecurity.init(allocator, std.testing.io, .{ .jwt_secret = "testkit-secret" });
    const uid = try store.createUser("Alice", "a@x.com", "hash", false, false, 1, 100);

    const Whoami = struct {
        fn h(ctx: *zigmodu.http.Context) !void {
            const uid_ = ctx.userIdInt(i64) orelse {
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
    guarded = try guarded.use(@import("../middleware/auth.zig").tokenVersionGuard(&sec, &store));
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
