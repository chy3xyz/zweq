//! Payment service — recharge orders, wallet ledger, withdraws.
//! No HTTP/SQL leakage. The WeChat Pay v3 gateway (zwechat.pay.v3) plugs into
//! `completeRecharge` on payment notify; dev builds use the mock channel.

const std = @import("std");
const zigmodu = @import("zigmodu");
const zwechat = @import("zwechat");
const persist = @import("persistence.zig");

pub const WalletRow = persist.WalletRow;
pub const RechargeOrderRow = persist.RechargeOrderRow;
pub const RechargeOrderListResult = persist.RechargeOrderListResult;
pub const WithdrawRow = persist.WithdrawRow;
pub const WithdrawListResult = persist.WithdrawListResult;

pub const PaymentError = error{
    InvalidAmount,
    InvalidOrderNo,
    OrderNotFound,
    WithdrawInsufficient,
    InvalidPayConfig,
    PrepayFailed,
    RefundFailed,
    TransferFailed,
    Unexpected,
};

/// WeChat Pay v3 merchant configuration (read from site settings).
pub const PayConfig = struct {
    mch_id: []const u8 = "",
    app_id: []const u8 = "",
    serial_no: []const u8 = "",
    private_key_pem: []const u8 = "",
    notify_url: []const u8 = "",
    platform_cert: []const u8 = "",

    pub fn deinit(self: PayConfig, allocator: std.mem.Allocator) void {
        // 仅 free 实际 dupe 过的字段（readPayConfig 只 dupe 非空值；
        // 未配置字段保持 "" 字面量，free 会崩溃）。
        if (self.mch_id.len > 0) allocator.free(self.mch_id);
        if (self.app_id.len > 0) allocator.free(self.app_id);
        if (self.serial_no.len > 0) allocator.free(self.serial_no);
        if (self.private_key_pem.len > 0) allocator.free(self.private_key_pem);
        if (self.notify_url.len > 0) allocator.free(self.notify_url);
        if (self.platform_cert.len > 0) allocator.free(self.platform_cert);
    }
};

/// V2 商户配置（退款 / 企业付款等 mTLS 接口用，从站点设置读）。
pub const PayV2Config = struct {
    app_id: []const u8 = "",
    mch_id: []const u8 = "",
    key: []const u8 = "",
    notify_url: []const u8 = "",
    /// 商户证书 P12 文件路径（mTLS 双向认证；密码 = mch_id）。
    root_ca: []const u8 = "",

    pub fn deinit(self: PayV2Config, allocator: std.mem.Allocator) void {
        // 仅 free 实际 dupe 过的字段（readPayV2Config 只 dupe 非空值）。
        if (self.app_id.len > 0) allocator.free(self.app_id);
        if (self.mch_id.len > 0) allocator.free(self.mch_id);
        if (self.key.len > 0) allocator.free(self.key);
        if (self.notify_url.len > 0) allocator.free(self.notify_url);
        if (self.root_ca.len > 0) allocator.free(self.root_ca);
    }
};

const JSAPI_ORDER_URL = "https://api.mch.weixin.qq.com/v3/pay/transactions/jsapi";
const JSAPI_ORDER_PATH = "/v3/pay/transactions/jsapi";
const REFUND_URL = "https://api.mch.weixin.qq.com/v3/refund/domestic/refunds";
const REFUND_PATH = "/v3/refund/domestic/refunds";
const TRANSFER_URL = "https://api.mch.weixin.qq.com/v3/transfer/batches";
const TRANSFER_PATH = "/v3/transfer/batches";

/// A prepared JSAPI unified-order request (caller frees).
pub const PrepayRequest = struct {
    url: []const u8,
    body: []const u8,
    auth: []const u8,

    pub fn deinit(self: PrepayRequest, allocator: std.mem.Allocator) void {
        allocator.free(self.url);
        allocator.free(self.body);
        allocator.free(self.auth);
    }
};

pub const PaymentService = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    store: *persist.PaymentStore,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, store: *persist.PaymentStore) PaymentService {
        return .{ .allocator = allocator, .io = io, .store = store };
    }

    fn now(self: *PaymentService) i64 {
        return zigmodu.time.wallClockSeconds(self.io);
    }

    /// Generate a unique order number: `R<unix>_<8 hex>`.
    fn genOrderNo(self: *PaymentService, allocator: std.mem.Allocator) ![]const u8 {
        var rand_bytes: [4]u8 = undefined;
        {
            var file = try std.Io.Dir.cwd().openFile(self.io, "/dev/urandom", .{});
            errdefer file.close(self.io);
            const read = try file.readPositionalAll(self.io, &rand_bytes, 0);
            if (read != rand_bytes.len) return error.Unexpected;
        }
        return std.fmt.allocPrint(allocator, "R{d}_{x:0>2}{x:0>2}{x:0>2}{x:0>2}", .{
            self.now(),
            rand_bytes[0],
            rand_bytes[1],
            rand_bytes[2],
            rand_bytes[3],
        });
    }

    /// Create a recharge order (status pending). `fan_id` 0 = anonymous order.
    pub fn createRechargeOrder(self: *PaymentService, allocator: std.mem.Allocator, tenant_id: i64, account_id: i64, fan_id: i64, amount: i64) PaymentError!RechargeOrderRow {
        if (amount <= 0) return error.InvalidAmount;
        const order_no = self.genOrderNo(allocator) catch return error.Unexpected;
        errdefer allocator.free(order_no);
        _ = self.store.createOrder(tenant_id, account_id, order_no, fan_id, amount, "mock", self.now()) catch return error.Unexpected;
        // Return the fresh order (re-read so the row has all fields).
        const row_opt = self.store.getOrderByNo(tenant_id, order_no) catch return error.Unexpected;
        const row = row_opt orelse return error.OrderNotFound;
        allocator.free(order_no);
        return row;
    }

    /// Complete a recharge: flip pending → paid and credit the wallet.
    /// Idempotent: a second notify for the same order does nothing.
    pub fn completeRecharge(self: *PaymentService, tenant_id: i64, order_no: []const u8) PaymentError!bool {
        const paid = self.store.markOrderPaid(tenant_id, order_no, self.now()) catch return error.Unexpected;
        if (!paid) return false;
        const row_opt = self.store.getOrderByNo(tenant_id, order_no) catch return error.Unexpected;
        const row = row_opt orelse return error.OrderNotFound;
        defer row.free(self.allocator);
        if (row.amount > 0) {
            _ = self.store.creditWallet(tenant_id, row.account_id, row.fan_id, row.amount, self.now()) catch return error.Unexpected;
        }
        return true;
    }

    pub fn walletBalance(self: *PaymentService, tenant_id: i64, account_id: i64, fan_id: i64) PaymentError!?WalletRow {
        return self.store.getWallet(tenant_id, account_id, fan_id) catch error.Unexpected;
    }

    pub fn listOrders(self: *PaymentService, page: usize, page_size: usize, tenant_id: i64, account_id: i64) PaymentError!RechargeOrderListResult {
        return self.store.listOrders(page, page_size, tenant_id, account_id) catch error.Unexpected;
    }

    /// Request a withdraw (pending). Balance is debited on approval (Phase 4).
    pub fn requestWithdraw(self: *PaymentService, tenant_id: i64, account_id: i64, fan_id: i64, amount: i64) PaymentError!i64 {
        if (amount <= 0) return error.InvalidAmount;
        const wallet_opt = self.store.getWallet(tenant_id, account_id, fan_id) catch return error.Unexpected;
        const wallet = wallet_opt orelse return error.WithdrawInsufficient;
        if (wallet.balance < amount) return error.WithdrawInsufficient;
        return self.store.createWithdraw(tenant_id, account_id, fan_id, amount, self.now()) catch error.Unexpected;
    }

    pub fn listWithdraws(self: *PaymentService, page: usize, page_size: usize, tenant_id: i64, account_id: i64) PaymentError!WithdrawListResult {
        return self.store.listWithdraws(page, page_size, tenant_id, account_id) catch error.Unexpected;
    }

    /// Build a WeChat Pay v3 JSAPI unified-order request (body + auth header).
    /// Testable without network. Caller frees via `PrepayRequest.deinit`.
    pub fn buildPrepayRequest(self: *PaymentService, allocator: std.mem.Allocator, cfg: PayConfig, order_no: []const u8, amount: i64, description: []const u8, openid: []const u8) !PrepayRequest {
        _ = self;
        const body = try std.fmt.allocPrint(
            allocator,
            "{{\"appid\":\"{s}\",\"mchid\":\"{s}\",\"description\":\"{s}\",\"out_trade_no\":\"{s}\",\"notify_url\":\"{s}\",\"amount\":{{\"total\":{d},\"currency\":\"CNY\"}},\"payer\":{{\"openid\":\"{s}\"}}}}",
            .{ cfg.app_id, cfg.mch_id, description, order_no, cfg.notify_url, amount, openid },
        );
        errdefer allocator.free(body);

        const v3cfg = zwechat.pay.v3.Config{
            .app_id = cfg.app_id,
            .mch_id = cfg.mch_id,
            .serial_no = cfg.serial_no,
            .private_key_pem = cfg.private_key_pem,
            .notify_url = cfg.notify_url,
        };
        var sig = try zwechat.pay.v3.signer.buildAuthorizationHeader(allocator, v3cfg, "POST", JSAPI_ORDER_PATH, body);
        defer sig.deinit(allocator);
        const auth = try allocator.dupe(u8, sig.authorization);
        errdefer allocator.free(auth);
        const url = try allocator.dupe(u8, JSAPI_ORDER_URL);
        errdefer allocator.free(url);
        return .{ .url = url, .body = body, .auth = auth };
    }

    /// Create a recharge order via real WeChat Pay v3 JSAPI prepay.
    /// Requires merchant config; returns error.PrepayFailed on API failure.
    pub fn createV3RechargeOrder(self: *PaymentService, allocator: std.mem.Allocator, tenant_id: i64, account_id: i64, fan_id: i64, amount: i64, openid: []const u8, cfg: PayConfig) PaymentError!RechargeOrderRow {
        if (amount <= 0) return error.InvalidAmount;
        if (cfg.mch_id.len == 0 or cfg.app_id.len == 0 or cfg.serial_no.len == 0 or cfg.private_key_pem.len == 0) return error.InvalidPayConfig;

        const order_no = self.genOrderNo(allocator) catch return error.Unexpected;
        errdefer allocator.free(order_no);

        var req_data = self.buildPrepayRequest(allocator, cfg, order_no, amount, "zweq recharge", openid) catch return error.PrepayFailed;
        defer req_data.deinit(allocator);

        var client = zigmodu.http.HttpClient.init(allocator, self.io, 4, 10_000);
        defer client.deinit();
        var req = zigmodu.http.HttpClient.HttpRequest.init(allocator, "POST", req_data.url);
        defer req.deinit();
        req.setHeader("Authorization", req_data.auth) catch return error.PrepayFailed;
        req.setHeader("Content-Type", "application/json") catch return error.PrepayFailed;
        req.setBody(req_data.body) catch return error.PrepayFailed;
        var resp = client.request(req) catch return error.PrepayFailed;
        defer resp.deinit();
        if (!resp.isSuccess()) return error.PrepayFailed;

        var parsed = std.json.parseFromSlice(std.json.Value, allocator, resp.body, .{}) catch return error.PrepayFailed;
        defer parsed.deinit();
        _ = objString(parsed.value, "prepay_id") orelse return error.PrepayFailed;

        _ = self.store.createOrder(tenant_id, account_id, order_no, fan_id, amount, "wxpay_v3", self.now()) catch return error.Unexpected;
        const row_opt = self.store.getOrderByNo(tenant_id, order_no) catch return error.Unexpected;
        const row = row_opt orelse return error.OrderNotFound;
        allocator.free(order_no);
        return row;
    }

    /// 构造 v3 退款请求（url/body/auth，无网络）。可单测。
    pub fn buildRefundV3Request(self: *PaymentService, allocator: std.mem.Allocator, cfg: PayConfig, out_trade_no: []const u8, out_refund_no: []const u8, refund_amount: i64, total_amount: i64) PaymentError!PrepayRequest {
        _ = self;
        const body = std.fmt.allocPrint(
            allocator,
            "{{\"out_trade_no\":\"{s}\",\"out_refund_no\":\"{s}\",\"amount\":{{\"refund\":{d},\"total\":{d},\"currency\":\"CNY\"}}}}",
            .{ out_trade_no, out_refund_no, refund_amount, total_amount },
        ) catch return error.PrepayFailed;
        errdefer allocator.free(body);
        const v3cfg = zwechat.pay.v3.Config{
            .app_id = cfg.app_id,
            .mch_id = cfg.mch_id,
            .serial_no = cfg.serial_no,
            .private_key_pem = cfg.private_key_pem,
            .notify_url = cfg.notify_url,
        };
        var sig = zwechat.pay.v3.signer.buildAuthorizationHeader(allocator, v3cfg, "POST", REFUND_PATH, body) catch return error.PrepayFailed;
        defer sig.deinit(allocator);
        const auth = allocator.dupe(u8, sig.authorization) catch return error.PrepayFailed;
        errdefer allocator.free(auth);
        const url = allocator.dupe(u8, REFUND_URL) catch return error.PrepayFailed;
        return .{ .url = url, .body = body, .auth = auth };
    }

    /// v3 退款（refund/domestic/refunds）。需商户证书配置。
    pub fn refundV3(self: *PaymentService, allocator: std.mem.Allocator, cfg: PayConfig, out_trade_no: []const u8, out_refund_no: []const u8, refund_amount: i64, total_amount: i64) PaymentError!void {
        if (cfg.mch_id.len == 0 or cfg.serial_no.len == 0 or cfg.private_key_pem.len == 0) return error.InvalidPayConfig;
        var req_data = self.buildRefundV3Request(allocator, cfg, out_trade_no, out_refund_no, refund_amount, total_amount) catch return error.PrepayFailed;
        defer req_data.deinit(allocator);

        var client = zigmodu.http.HttpClient.init(allocator, self.io, 4, 10_000);
        defer client.deinit();
        var req = zigmodu.http.HttpClient.HttpRequest.init(allocator, "POST", req_data.url);
        defer req.deinit();
        req.setHeader("Authorization", req_data.auth) catch return error.PrepayFailed;
        req.setHeader("Content-Type", "application/json") catch return error.PrepayFailed;
        req.setBody(req_data.body) catch return error.PrepayFailed;
        var resp = client.request(req) catch return error.PrepayFailed;
        defer resp.deinit();
        if (!resp.isSuccess()) return error.PrepayFailed;
    }

    /// 构造 v3 商家转账请求（transfer/batches，无网络）。可单测。
    pub fn buildTransferV3Request(self: *PaymentService, allocator: std.mem.Allocator, cfg: PayConfig, openid: []const u8, amount: i64, out_batch_no: []const u8, out_detail_no: []const u8, remark: []const u8) PaymentError!PrepayRequest {
        _ = self;
        const body = std.fmt.allocPrint(
            allocator,
            "{{\"appid\":\"{s}\",\"out_batch_no\":\"{s}\",\"batch_name\":\"zweq transfer\",\"batch_remark\":\"{s}\",\"total_amount\":{d},\"total_num\":1,\"transfer_detail_list\":[{{\"out_detail_no\":\"{s}\",\"transfer_amount\":{d},\"transfer_remark\":\"{s}\",\"openid\":\"{s}\"}}]}}",
            .{ cfg.app_id, out_batch_no, remark, amount, out_detail_no, amount, remark, openid },
        ) catch return error.PrepayFailed;
        errdefer allocator.free(body);
        const v3cfg = zwechat.pay.v3.Config{
            .app_id = cfg.app_id,
            .mch_id = cfg.mch_id,
            .serial_no = cfg.serial_no,
            .private_key_pem = cfg.private_key_pem,
            .notify_url = cfg.notify_url,
        };
        var sig = zwechat.pay.v3.signer.buildAuthorizationHeader(allocator, v3cfg, "POST", TRANSFER_PATH, body) catch return error.PrepayFailed;
        defer sig.deinit(allocator);
        const auth = allocator.dupe(u8, sig.authorization) catch return error.PrepayFailed;
        errdefer allocator.free(auth);
        const url = allocator.dupe(u8, TRANSFER_URL) catch return error.PrepayFailed;
        return .{ .url = url, .body = body, .auth = auth };
    }

    /// v3 商家转账到零钱（transfer/batches）。需商户证书配置。
    pub fn transferV3(self: *PaymentService, allocator: std.mem.Allocator, cfg: PayConfig, openid: []const u8, amount: i64, out_batch_no: []const u8, out_detail_no: []const u8, remark: []const u8) PaymentError!void {
        if (cfg.mch_id.len == 0 or cfg.serial_no.len == 0 or cfg.private_key_pem.len == 0) return error.InvalidPayConfig;
        var req_data = self.buildTransferV3Request(allocator, cfg, openid, amount, out_batch_no, out_detail_no, remark) catch return error.PrepayFailed;
        defer req_data.deinit(allocator);

        var client = zigmodu.http.HttpClient.init(allocator, self.io, 4, 10_000);
        defer client.deinit();
        var req = zigmodu.http.HttpClient.HttpRequest.init(allocator, "POST", req_data.url);
        defer req.deinit();
        req.setHeader("Authorization", req_data.auth) catch return error.PrepayFailed;
        req.setHeader("Content-Type", "application/json") catch return error.PrepayFailed;
        req.setBody(req_data.body) catch return error.PrepayFailed;
        var resp = client.request(req) catch return error.PrepayFailed;
        defer resp.deinit();
        if (!resp.isSuccess()) return error.PrepayFailed;
    }

    /// V2 退款（secapi/pay/refund，需证书双向认证）。复用 zwechat pay.refund
    /// （v0.4.x 起 RefundResult 持有 _raw + deinit，UAF 已修）。
    pub fn refundV2(self: *PaymentService, allocator: std.mem.Allocator, cfg: PayV2Config, out_trade_no: []const u8, out_refund_no: []const u8, total_fee: []const u8, refund_fee: []const u8, refund_desc: []const u8) PaymentError!void {
        _ = self;
        var r = zwechat.pay.Refund.init(.{
            .app_id = cfg.app_id,
            .mch_id = cfg.mch_id,
            .key = cfg.key,
            .notify_url = cfg.notify_url,
            .root_ca = cfg.root_ca,
        });
        var result = r.refund(allocator, .{
            .out_trade_no = out_trade_no,
            .out_refund_no = out_refund_no,
            .total_fee = total_fee,
            .refund_fee = refund_fee,
            .notify_url = cfg.notify_url,
            .refund_desc = refund_desc,
        }) catch return error.RefundFailed;
        defer result.deinit();
        if (!std.mem.eql(u8, result.return_code, "SUCCESS") or !std.mem.eql(u8, result.result_code, "SUCCESS")) return error.RefundFailed;
    }

    /// 企业付款到零钱（V2 transfer，需证书双向认证）。复用 zwechat pay.transfer
    /// （v0.4.x 起 TransferWalletResult 持有 _raw + deinit，UAF 已修）。
    pub fn transferToWallet(self: *PaymentService, allocator: std.mem.Allocator, cfg: PayV2Config, open_id: []const u8, amount: i64, desc: []const u8, partner_trade_no: []const u8) PaymentError!void {
        _ = self;
        var t = zwechat.pay.Transfer.init(.{
            .app_id = cfg.app_id,
            .mch_id = cfg.mch_id,
            .key = cfg.key,
            .notify_url = cfg.notify_url,
            .root_ca = cfg.root_ca,
        });
        var result = t.toWallet(allocator, .{
            .open_id = open_id,
            .amount = amount,
            .desc = desc,
            .partner_trade_no = partner_trade_no,
        }) catch return error.TransferFailed;
        defer result.deinit();
        if (!std.mem.eql(u8, result.return_code, "SUCCESS")) return error.TransferFailed;
    }

    /// Verify a WeChat Pay v3 notify signature (RSA-SHA256, platform public
    /// key). Content = "{timestamp}\n{nonce}\n{body}\n".
    pub fn verifyV3NotifySignature(self: *PaymentService, allocator: std.mem.Allocator, platform_cert_pem: []const u8, timestamp: []const u8, nonce: []const u8, signature_b64: []const u8, body: []const u8) !bool {
        _ = self;
        const content = try std.fmt.allocPrint(allocator, "{s}\n{s}\n{s}\n", .{ timestamp, nonce, body });
        defer allocator.free(content);
        return zwechat.util.rsa.rsaVerify(allocator, content, signature_b64, platform_cert_pem) catch false;
    }

    /// Handle a WeChat Pay v3 notify: decrypt the AES-256-GCM resource, extract
    /// out_trade_no + trade_state, and complete the recharge (idempotent).
    /// Returns true when an order was processed, false when the notify is
    /// malformed/irrelevant.
    pub fn handleV3Notify(self: *PaymentService, allocator: std.mem.Allocator, api_v3_key: []const u8, body: []const u8) !bool {
        if (api_v3_key.len == 0) return false;
        var parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch return false;
        defer parsed.deinit();
        const resource = parsed.value.object.get("resource") orelse return false;
        const ciphertext = objString(resource, "ciphertext") orelse return false;
        const aad = objString(resource, "associated_data") orelse "";
        const nonce = objString(resource, "nonce") orelse return false;

        const plain = zwechat.pay.v3.decryptNotifyResource(allocator, api_v3_key, ciphertext, aad, nonce) catch return false;
        defer allocator.free(plain);

        var inner = std.json.parseFromSlice(std.json.Value, allocator, plain, .{}) catch return false;
        defer inner.deinit();
        const trade_state = objString(inner.value, "trade_state") orelse return false;
        const out_trade_no = objString(inner.value, "out_trade_no") orelse return false;
        if (!std.mem.eql(u8, trade_state, "SUCCESS")) return false;

        // Resolve tenant from the order (notify carries no tenant id).
        const row_opt = self.store.getOrderByNoAny(out_trade_no) catch return false;
        const row = row_opt orelse return false;
        defer row.free(self.allocator);
        return self.completeRecharge(row.tenant_id, out_trade_no) catch false;
    }
};

/// Read a JSON string field from a `std.json.Value` object (type-safe).
fn objString(v: std.json.Value, key: []const u8) ?[]const u8 {
    const field = v.object.get(key) orelse return null;
    return if (field == .string) field.string else null;
}
