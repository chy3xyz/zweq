//! Webhook HTTP 传输抽象（事件推送出口）。
//! 生产走 zigmodu HttpClient（zhttp 底层）；测试注入 mock 记录 payload。

const std = @import("std");
const zigmodu = @import("zigmodu");

pub const WebhookTransport = struct {
    /// 可选记录器（测试注入：收到 (url, payload) 时回调）。
    recorder: ?*const fn (url: []const u8, payload: []const u8) void = null,
    /// 测试注入：mock 路径返回的 HTTP 状态码（默认 200）。
    mock_status: u16 = 200,
    /// 测试注入：非空时 mock 路径直接返回该错误（模拟网络层失败）。
    mock_error: ?anyerror = null,
    io: std.Io = undefined,

    pub fn init(io: std.Io) WebhookTransport {
        return .{ .io = io };
    }

    /// POST payload 到 url，返回 HTTP 状态码。网络层错误（DNS/连接/超时）
    /// 以 error 返回；4xx/5xx 不报错——按状态码决定是否重试由调用方
    /// （webhook.deliver 任务 handler）判定：5xx 重试、4xx 终态。
    pub fn post(self: *WebhookTransport, url: []const u8, payload: []const u8) !u16 {
        if (self.recorder) |r| {
            r(url, payload);
            if (self.mock_error) |e| return e;
            return self.mock_status;
        }
        // 生产：zigmodu HttpClient POST（JSON）。
        var client = zigmodu.http.HttpClient.init(std.heap.c_allocator, self.io, 4, 10_000);
        defer client.deinit();
        var res = try client.post(url, payload);
        defer res.deinit();
        return res.status_code;
    }
};
