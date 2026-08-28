//! 支付：PayConfig 局部释放安全、充值闭环幂等入账、v3 回调解密完成充值、v3 prepay/refund/transfer 报文构造（无网络）。
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
    try std.testing.expectEqualStrings("1000", order.amount);
    try std.testing.expectEqualStrings("pending", order.status);
    try std.testing.expect(order.order_no.len > 0);

    // complete → wallet credited
    try std.testing.expect(try payment_svc.completeRecharge(1, order.order_no));
    const wallet = (try payment_svc.walletBalance(1, 5, 42)).?;
    defer wallet.free(allocator);
    try std.testing.expectEqualStrings("1000", wallet.balance);

    // second complete is a no-op (idempotent)
    try std.testing.expect(!try payment_svc.completeRecharge(1, order.order_no));
    const wallet2 = (try payment_svc.walletBalance(1, 5, 42)).?;
    defer wallet2.free(allocator);
    try std.testing.expectEqualStrings("1000", wallet2.balance);

    // withdraw
    const wid = try payment_svc.requestWithdraw(1, 5, 42, 300);
    _ = wid;
    try std.testing.expectError(error.WithdrawInsufficient, payment_svc.requestWithdraw(1, 5, 42, 99999));

    // invalid amount
    try std.testing.expectError(error.InvalidAmount, payment_svc.createRechargeOrder(allocator, 1, 5, 42, 0));
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
    defer wallet.free(allocator);
    try std.testing.expectEqualStrings("500", wallet.balance);

    // duplicate notify is a no-op (idempotent)
    try std.testing.expect(!try payment_svc.handleV3Notify(allocator, api_v3_key, body));

    // wrong key → false
    try std.testing.expect(!try payment_svc.handleV3Notify(allocator, "99999999999999999999999999999999", body));
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
