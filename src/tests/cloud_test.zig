//! 云服务：license 生命周期 + 市场安装、远端校验与同步（mock transport）、fail-closed 状态检查、manifest SQL 白名单沙箱与迁移执行。
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
    cloud_svc.setDriver(env.asDriver());
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
    const d = env.asDriver();
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
