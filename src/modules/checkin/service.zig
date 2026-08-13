//! Checkin service — 签到业务 + message 模块 Receiver 接入。
//!
//! 这是「场景应用」的标准形态：业务逻辑（checkin）+ 一个 `receiverHandle`
//! 钩子，后者在 main.zig 里通过 `wechat_svc.registerReceiver` 注册进回调
//! 引擎。分发链为：关键词规则 → 已绑定模块的 receiver → AI → 默认回复。

const std = @import("std");
const zigmodu = @import("zigmodu");
const persist = @import("persistence.zig");
const message_mod = @import("../message/service.zig");
const module_mod = @import("../module/service.zig");

pub const CheckinRecordRow = persist.CheckinRecordRow;
pub const CheckinListResult = persist.CheckinListResult;

pub const CheckinError = error{
    Unexpected,
};

pub const CheckinService = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    store: *persist.CheckinStore,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, store: *persist.CheckinStore) CheckinService {
        return .{ .allocator = allocator, .io = io, .store = store };
    }

    fn now(self: *CheckinService) i64 {
        return zigmodu.time.wallClockSeconds(self.io);
    }

    /// Record a check-in for `day` (天序号). Returns true when newly checked
    /// in, false when the openid already checked in that day (idempotent).
    pub fn checkin(self: *CheckinService, tenant_id: i64, account_id: i64, openid: []const u8, day: i64, points: i64) CheckinError!bool {
        if (self.store.findByDay(tenant_id, account_id, openid, day) catch return error.Unexpected) |row| {
            defer row.free(self.allocator);
            return false;
        }
        _ = self.store.create(tenant_id, account_id, openid, day, points, self.now()) catch return error.Unexpected;
        return true;
    }

    pub fn list(self: *CheckinService, page: usize, page_size: usize, tenant_id: i64, account_id: i64) CheckinError!CheckinListResult {
        return self.store.list(page, page_size, tenant_id, account_id) catch error.Unexpected;
    }
};

/// Receiver context — 把模块注册表（读 per-account config）与签到服务接进
/// 回调引擎。由 main.zig 在装配时填充。
pub const ReceiverCtx = struct {
    module_svc: *module_mod.ModuleService,
    checkin_svc: *CheckinService,
    io: std.Io,
};

/// `Receiver.handle` 实现：识别关键词「签到」，读模块 config 中的积分
/// 奖励（config 为纯整数串，如 `"5"`，非法/空串按 0），幂等签到后回复。
pub fn receiverHandle(ctx: ?*anyopaque, allocator: std.mem.Allocator, msg: message_mod.IncomingMessage) anyerror!?message_mod.Reply {
    const c: *ReceiverCtx = @ptrCast(@alignCast(ctx orelse return null));
    if (!std.mem.eql(u8, msg.msg_type, "text")) return null;
    if (!std.mem.eql(u8, msg.content, "签到")) return null;

    const cfg = c.module_svc.getConfig(allocator, msg.tenant_id, msg.account_id, "checkin") catch null;
    defer if (cfg) |x| allocator.free(x);
    const points = parsePoints(cfg orelse "");
    const day = @divTrunc(zigmodu.time.wallClockSeconds(c.io), 86400);

    const fresh = c.checkin_svc.checkin(msg.tenant_id, msg.account_id, msg.openid, day, points) catch return null;

    const text = if (fresh)
        try std.fmt.allocPrint(allocator, "签到成功！获得 {d} 积分", .{points})
    else
        try allocator.dupe(u8, "你今天已经签到过啦");
    defer allocator.free(text);
    return try message_mod.Reply.text(allocator, text);
}

fn parsePoints(s: []const u8) i64 {
    return std.fmt.parseInt(i64, std.mem.trim(u8, s, " \t"), 10) catch 0;
}
