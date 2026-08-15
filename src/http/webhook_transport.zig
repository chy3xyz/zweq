//! Webhook HTTP 传输抽象（事件推送出口）。
//! 生产走 zigmodu HttpClient（zhttp 底层）；测试注入 mock 记录 payload。

const std = @import("std");
const zigmodu = @import("zigmodu");

pub const WebhookTransport = struct {
    /// 可选记录器（测试注入：收到 (url, payload) 时回调）。
    recorder: ?*const fn (url: []const u8, payload: []const u8) void = null,
    io: std.Io = undefined,

    pub fn init(io: std.Io) WebhookTransport {
        return .{ .io = io };
    }

    pub fn post(self: *WebhookTransport, url: []const u8, payload: []const u8) !void {
        if (self.recorder) |r| {
            r(url, payload);
            return;
        }
        // 生产：zigmodu HttpClient POST（JSON）。
        var client = zigmodu.http.HttpClient.init(std.heap.c_allocator, self.io, 4, 10_000);
        defer client.deinit();
        var res = try client.post(url, payload);
        defer res.deinit();
        _ = &res;
    }
};
