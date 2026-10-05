//! C 端（fan）声明式鉴权迁移测试：`.jwt`/`.optional` 路由矩阵、RBAC 兼容
//! （fan 无角色不被 permissionGate 403）、管理端 token 被薄壳拒绝、
//! per-openid 限流改读框架注入身份后的按 openid 维度计数。
//! 中间件链与 main.zig 一致：jwtAuthFromCatalogWithPermissions →
//! permissionGateWith(.rbac) → tokenVersionGuard → scope per-openid 限流。

const std = @import("common.zig").std;
const zigmodu = @import("common.zig").zigmodu;
const db_mod = @import("common.zig").db_mod;
const schema = @import("common.zig").schema;
const user = @import("common.zig").user;
const permission = @import("common.zig").permission;
const member = @import("common.zig").member;
const appmod = @import("common.zig").appmod;
const payment = @import("common.zig").payment;
const checkin = @import("common.zig").checkin;
const lucky_draw = @import("common.zig").lucky_draw;
const coupon = @import("common.zig").coupon;
const vote = @import("common.zig").vote;
const seckill = @import("common.zig").seckill;
const member_card = @import("common.zig").member_card;
const distribution = @import("common.zig").distribution;
const points = @import("common.zig").points;
const mw_rate = @import("common.zig").mw_rate;
const all_infos = @import("common.zig").all_infos;
const openMemory = @import("common.zig").openMemory;
const app_bff = @import("../modules/app_bff/root.zig");
const catalog_permissions = @import("../middleware/catalog_permissions.zig");
const mw_auth = @import("../middleware/auth.zig");

test "fan 声明式鉴权：.jwt 401 / .optional 公开 / RBAC 不拦 fan / 限流按 openid" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();

    // ── 服务装配（链路与 main.zig 相同）──
    var user_store = user.persistence.UserStore.init(allocator, env.client);
    var sec = zigmodu.security.AppSecurity.init(allocator, std.testing.io, .{ .jwt_secret = "fan-auth-secret" });
    var user_svc = user.service.UserService.init(&user_store, &sec, std.testing.io, 3600, 86400);
    var role_store = permission.persistence.RoleStore.init(allocator, env.client);
    catalog_permissions.init(&role_store);

    var fan_store = member.persistence.FanStore.init(allocator, env.client);
    var points_store = points.persistence.PointsStore.init(allocator, env.client);
    var points_svc = points.service.PointsService.init(allocator, std.testing.io, &points_store, &fan_store);
    var coupon_store = coupon.persistence.CouponStore.init(allocator, env.client);
    var coupon_svc = coupon.service.CouponService.init(allocator, std.testing.io, &coupon_store);
    var draw_store = lucky_draw.persistence.DrawStore.init(allocator, env.client);
    var draw_svc = lucky_draw.service.DrawService.init(allocator, std.testing.io, &draw_store);
    var module_store = appmod.persistence.ModuleStore.init(allocator, env.client);
    var module_svc = appmod.service.ModuleService.init(allocator, std.testing.io, &module_store);
    var payment_store = payment.persistence.PaymentStore.init(allocator, env.client);
    var payment_svc = payment.service.PaymentService.init(allocator, std.testing.io, &payment_store);
    var checkin_store = checkin.persistence.CheckinStore.init(allocator, env.client);
    var checkin_svc = checkin.service.CheckinService.init(allocator, std.testing.io, &checkin_store);
    var vote_store = vote.persistence.VoteStore.init(allocator, env.client);
    var vote_svc = vote.service.VoteService.init(allocator, std.testing.io, &vote_store);
    var seckill_store = seckill.persistence.SeckillStore.init(allocator, env.client);
    var seckill_svc = seckill.service.SeckillService.init(allocator, std.testing.io, &seckill_store);
    var mc_store = member_card.persistence.MemberCardStore.init(allocator, env.client);
    var mc_svc = member_card.service.MemberCardService.init(allocator, std.testing.io, &mc_store);
    var dist_store = distribution.persistence.DistributionStore.init(allocator, env.client);
    var dist_svc = distribution.service.DistributionService.init(allocator, std.testing.io, &dist_store);

    var fan_app_api = app_bff.fan_api.DefaultFanAppApi.init(&user_svc, &fan_store, &points_svc, &coupon_svc, &draw_svc, &module_svc, &payment_svc, 1);
    var fan_scene_api = app_bff.fan_scene_api.DefaultFanSceneApi.init(&user_svc, &checkin_svc, &vote_svc, &seckill_svc, &mc_svc, &dist_svc, &module_svc, 1);

    var fan_registry = zigmodu.RateLimiterRegistry.initWithCapacity(allocator, 10, 1, mw_rate.registry_max_keys);
    defer fan_registry.deinit();
    // 与 main.zig fan_econ_rules 同形；这里只挂一条并把阈值压到 2 便于触发。
    const test_rules = [_]mw_rate.OpenidRule{
        .{ .name = "points-redeem", .path = "api/v1/app/points/redeem", .max = 2 },
    };
    var fan_openid_limiter = mw_rate.PerOpenidLimiter{
        .backend = .{ .registry = &fan_registry },
        .sec = &sec,
        .rules = &test_rules,
    };

    var server = zigmodu.http.Server.init(std.testing.io, allocator, 0);
    defer server.deinit();
    var slot: zigmodu.http.CatalogSlot = .{};
    defer slot.deinit();
    try server.addMiddleware(try zigmodu.http.http_middleware.jwtAuthFromCatalogWithPermissions(&sec.module, &slot, catalog_permissions.load, .{}));
    try server.addMiddleware(try zigmodu.http.http_middleware.permissionGateWith(&slot, .{ .mode = .rbac }));
    try server.addMiddleware(mw_auth.tokenVersionGuard(&sec, &user_store));

    var app_state: void = {};
    var router = zigmodu.http.Router(void).init(std.testing.io, allocator, &server, &app_state);
    defer router.deinit();
    var v1_scope = router.scope("/api/v1");
    var fan_limited = try v1_scope.use(mw_rate.perOpenidRateLimit(&fan_openid_limiter));
    try fan_limited.mount(app_bff.fan_api.DefaultFanAppApi, &fan_app_api);
    try fan_limited.mount(app_bff.fan_scene_api.DefaultFanSceneApi, &fan_scene_api);
    slot.set(try router.finish());

    // 粉丝夹具（wallet/redeem 按 openid 查 fan 记录）。
    const now = zigmodu.time.wallClockSeconds(std.testing.io);
    _ = try fan_store.upsert(1, 0, "o_fan1", "", "粉丝一", "", true, now, now);
    _ = try fan_store.upsert(1, 0, "o_fan2", "", "粉丝二", "", true, now, now);
    _ = try fan_store.upsert(1, 0, "o_fan3", "", "粉丝三", "", true, now, now);

    const fan1_token = try sec.module.generateTokenWithTenant("o_fan1", &.{"fan"}, "0");
    defer allocator.free(fan1_token);
    const fan2_token = try sec.module.generateTokenWithTenant("o_fan2", &.{"fan"}, "0");
    defer allocator.free(fan2_token);
    const fan3_token = try sec.module.generateTokenWithTenant("o_fan3", &.{"fan"}, "0");
    defer allocator.free(fan3_token);
    // 管理端 token：与 fan token 同一 AppSecurity 签发（sub = 用户 id）。
    const admin_token = try sec.module.generateTokenWithTenant("7", &.{"admin"}, "1");
    defer allocator.free(admin_token);

    var h1: [1024]u8 = undefined;
    var h2: [1024]u8 = undefined;
    var h3: [1024]u8 = undefined;
    const fan1_hdr = try std.fmt.bufPrint(&h1, "Bearer {s}", .{fan1_token});
    const fan2_hdr = try std.fmt.bufPrint(&h2, "Bearer {s}", .{fan2_token});
    const fan3_hdr = try std.fmt.bufPrint(&h3, "Bearer {s}", .{fan3_token});

    // ── .jwt（需身份）：无 token → 401（原行为保持，改由框架中间件拒绝）──
    var anon = try zigmodu.http.Testkit.dispatch(&server, .GET, "/api/v1/app/wallet", null);
    defer anon.deinit(allocator);
    try std.testing.expectEqual(@as(u16, 401), anon.status_code);

    // ── 关键坑实测：fan 在 permission 表无角色，带 fan token 走完整 RBAC
    //    链必须是 200 而非 403（permissionGate 默认不拦未声明 permission
    //    的路由；permissions loader 对非数字 sub 返回空 CSV 不报错）──
    var authed = try zigmodu.http.Testkit.dispatchOpts(&server, .GET, "/api/v1/app/wallet", .{ .headers = &.{.{ "authorization", fan1_hdr }} });
    defer authed.deinit(allocator);
    try std.testing.expectEqual(@as(u16, 200), authed.status_code);
    try std.testing.expect(std.mem.indexOf(u8, authed.body, "\"balance\":0") != null);

    // 管理端 token（roles=admin）打 C 端 .jwt 接口 → 薄壳 fan 角色校验 401（旧语义保持）。
    var admin_hdr_buf: [1024]u8 = undefined;
    const admin_hdr = try std.fmt.bufPrint(&admin_hdr_buf, "Bearer {s}", .{admin_token});
    var admin_try = try zigmodu.http.Testkit.dispatchOpts(&server, .GET, "/api/v1/app/wallet", .{ .headers = &.{.{ "authorization", admin_hdr }} });
    defer admin_try.deinit(allocator);
    try std.testing.expectEqual(@as(u16, 401), admin_try.status_code);

    // ── .optional（公开列表但可个性化）：无 token 200 / 无效 token 200
    //    （永不 401）/ 合法 fan token 200（响应与匿名一致，行为不变）──
    var anon_list = try zigmodu.http.Testkit.dispatch(&server, .GET, "/api/v1/app/points/products", null);
    defer anon_list.deinit(allocator);
    try std.testing.expectEqual(@as(u16, 200), anon_list.status_code);

    var bad_list = try zigmodu.http.Testkit.dispatchOpts(&server, .GET, "/api/v1/app/points/products", .{ .headers = &.{.{ "authorization", "Bearer garbage.token.here" }} });
    defer bad_list.deinit(allocator);
    try std.testing.expectEqual(@as(u16, 200), bad_list.status_code);

    var fan_list = try zigmodu.http.Testkit.dispatchOpts(&server, .GET, "/api/v1/app/points/products", .{ .headers = &.{.{ "authorization", fan1_hdr }} });
    defer fan_list.deinit(allocator);
    try std.testing.expectEqual(@as(u16, 200), fan_list.status_code);

    // scene 模块同样迁移：checkin 需身份（.jwt），votes 列表公开（.optional）。
    var anon_checkin = try zigmodu.http.Testkit.dispatch(&server, .POST, "/api/v1/app/checkin", "{\"account_id\":0}");
    defer anon_checkin.deinit(allocator);
    try std.testing.expectEqual(@as(u16, 401), anon_checkin.status_code);

    var anon_votes = try zigmodu.http.Testkit.dispatch(&server, .GET, "/api/v1/app/votes", null);
    defer anon_votes.deinit(allocator);
    try std.testing.expectEqual(@as(u16, 200), anon_votes.status_code);

    // ── 经济接口带 token 通过鉴权（业务校验照旧）：不存在的商品 → 400 ──
    var redeem = try zigmodu.http.Testkit.dispatchOpts(&server, .POST, "/api/v1/app/points/redeem", .{
        .body = "{\"account_id\":0,\"product_id\":999999}",
        .headers = &.{.{ "authorization", fan2_hdr }},
    });
    defer redeem.deinit(allocator);
    try std.testing.expectEqual(@as(u16, 400), redeem.status_code);

    // ── per-openid 限流：openid 取自框架注入的 ctx 身份（user_id = fan
    //    token 的 sub），不再本地验签。规则 max=2：o_fan3 第 3 次 → 429；
    //    o_fan2 与 o_fan3 不同桶，不受其耗尽影响（仍 400 而非 429）。──
    var r3a = try zigmodu.http.Testkit.dispatchOpts(&server, .POST, "/api/v1/app/points/redeem", .{
        .body = "{\"account_id\":0,\"product_id\":999999}",
        .headers = &.{.{ "authorization", fan3_hdr }},
    });
    defer r3a.deinit(allocator);
    try std.testing.expectEqual(@as(u16, 400), r3a.status_code);
    var r3b = try zigmodu.http.Testkit.dispatchOpts(&server, .POST, "/api/v1/app/points/redeem", .{
        .body = "{\"account_id\":0,\"product_id\":999999}",
        .headers = &.{.{ "authorization", fan3_hdr }},
    });
    defer r3b.deinit(allocator);
    try std.testing.expectEqual(@as(u16, 400), r3b.status_code);
    var r3c = try zigmodu.http.Testkit.dispatchOpts(&server, .POST, "/api/v1/app/points/redeem", .{
        .body = "{\"account_id\":0,\"product_id\":999999}",
        .headers = &.{.{ "authorization", fan3_hdr }},
    });
    defer r3c.deinit(allocator);
    try std.testing.expectEqual(@as(u16, 429), r3c.status_code);

    var r2b = try zigmodu.http.Testkit.dispatchOpts(&server, .POST, "/api/v1/app/points/redeem", .{
        .body = "{\"account_id\":0,\"product_id\":999999}",
        .headers = &.{.{ "authorization", fan2_hdr }},
    });
    defer r2b.deinit(allocator);
    try std.testing.expectEqual(@as(u16, 400), r2b.status_code);
}
