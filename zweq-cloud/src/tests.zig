//! Unit tests for zweq-cloud.

const std = @import("std");
const zigmodu = @import("zigmodu");
const zent = @import("zent");
const db_mod = @import("db.zig");
const schema = @import("schema.zig");
const storage = @import("storage.zig");
const license = @import("modules/license/root.zig");
const market = @import("modules/market/root.zig");

const all_infos = .{
    license.persistence.infos,
    market.persistence.infos,
};

fn openMemory(allocator: std.mem.Allocator) !db_mod.StoreEnv(schema.infos, all_infos) {
    return db_mod.StoreEnv(schema.infos, all_infos).open(allocator, .sqlite, ":memory:");
}

test "health: deps importable" {
    _ = zigmodu;
    _ = zent;
    try std.testing.expect(true);
}

test "license: generate/verify/revoke lifecycle" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = license.persistence.LicenseStore.init(allocator, env.client);
    var svc = license.service.LicenseService.init(allocator, std.testing.io, &store);

    const row = try svc.generate(allocator, 30);
    defer row.free(allocator);
    try std.testing.expect(std.mem.startsWith(u8, row.license_key, "WEQ-"));
    try std.testing.expectEqualStrings("active", row.status);

    // 校验有效授权码。
    try std.testing.expect(try svc.verify(row.license_key));
    // 未知授权码 → InvalidLicense。
    try std.testing.expectError(error.InvalidLicense, svc.verify("WEQ-00000000-00000000-00000000"));
    // 撤销 → 不再有效。
    try svc.revoke(row.id);
    try std.testing.expectError(error.InvalidLicense, svc.verify(row.license_key));
    // 非法天数。
    try std.testing.expectError(error.InvalidDays, svc.generate(allocator, 0));
}

test "market: publish/verifyChecksum/list/getByName" {
    const allocator = std.testing.allocator;
    var env = try openMemory(allocator);
    defer env.deinit();
    var store = market.persistence.MarketStore.init(allocator, env.client);
    var local = storage.LocalArtifactStorage.init(allocator, std.testing.io, "/tmp/zweq-cloud-artifacts-test");
    var svc = market.service.MarketService.init(allocator, std.testing.io, &store, local.storage());

    // verifyChecksum：匹配/不匹配/空期望。
    try std.testing.expect(market.service.MarketService.verifyChecksum("hello", "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"));
    try std.testing.expect(!market.service.MarketService.verifyChecksum("hello", "0000000000000000000000000000000000000000000000000000000000000000"));
    try std.testing.expect(market.service.MarketService.verifyChecksum("hello", ""));
    // safeArtifactComponent：防路径逃逸。
    try std.testing.expect(market.service.MarketService.safeArtifactComponent("shop"));
    try std.testing.expect(!market.service.MarketService.safeArtifactComponent("../etc"));
    try std.testing.expect(!market.service.MarketService.safeArtifactComponent(""));

    // publish + list + getByName。
    const id = try svc.publish("shop", "商城", "1.0.0", "多商户商城", "", "");
    _ = id;
    var list = try svc.list(1, 20);
    defer list.free(allocator);
    try std.testing.expectEqual(@as(i64, 1), list.total);
    const pkg = (try svc.getByName("shop")).?;
    defer pkg.free(allocator);
    try std.testing.expectEqualStrings("商城", pkg.title);
    // 非法包名拒绝。
    try std.testing.expectError(error.InvalidName, svc.publish("../evil", "x", "1.0.0", "", "", ""));
}

test "storage: local backend put/get/exists + sigv4 format" {
    const a = std.testing.allocator;
    var local = storage.LocalArtifactStorage.init(a, std.testing.io, "/tmp/zweq-cloud-storage-test");
    const st = local.storage();

    const key = "shop-1.0.0.bin";
    const content = "{\"kind\":\"shop\"}";
    try st.put(a, key, content);
    try st.put(a, key, content); // 幂等
    try std.testing.expect(st.exists(key));
    const got = try st.get(a, key);
    defer a.free(got);
    try std.testing.expectEqualStrings(content, got);
    try std.testing.expect(!st.exists("nope.bin"));
    try std.testing.expectError(error.NotFound, st.get(a, "nope.bin"));

    // SigV4 格式：前缀 + 64-hex signature。
    const auth = try storage.signV4(a, .{
        .method = "GET",
        .host = "s3.amazonaws.com",
        .canonical_uri = "/bucket/key.bin",
        .payload = "",
    }, "AKIDEXAMPLE", "secret", "us-east-1", "s3", "20150830T123600Z", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    defer a.free(auth);
    try std.testing.expect(std.mem.startsWith(u8, auth, "AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20150830/us-east-1/s3/aws4_request, SignedHeaders=host;x-amz-content-sha256;x-amz-date, Signature="));
    const sig = auth[std.mem.lastIndexOfScalar(u8, auth, '=').? + 1 ..];
    try std.testing.expectEqual(@as(usize, 64), sig.len);

    var cwd = std.Io.Dir.cwd();
    cwd.deleteFile(std.testing.io, "/tmp/zweq-cloud-storage-test/shop-1.0.0.bin") catch {};
    cwd.deleteDir(std.testing.io, "/tmp/zweq-cloud-storage-test") catch {};
}
