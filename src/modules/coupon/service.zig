//! Coupon service — 优惠券模板/领券/核销业务 + message 模块 Receiver 接入。
//!
//! 完整电商营销场景：券模板（面额/门槛/总量/每人限领/有效期）→ 用户领券
//! （库存 + 限领 + 有效期校验，生成券码）→ 核销（unused→used 幂等）。
//! 公众号消息「领券」经 Receiver 领取第一个可领的券。

const std = @import("std");
const zigmodu = @import("zigmodu");
const persist = @import("persistence.zig");
const message_mod = @import("../message/service.zig");
const module_mod = @import("../module/service.zig");

pub const CouponRow = persist.CouponRow;
pub const CouponListResult = persist.CouponListResult;
pub const CouponUserRow = persist.CouponUserRow;
pub const CouponUserListResult = persist.CouponUserListResult;

pub const CouponError = error{
    InvalidInput,
    NotFound,
    OutOfStock,
    LimitReached,
    NotStarted,
    Expired,
    AlreadyUsed,
    Unexpected,
};

pub const CouponService = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    store: *persist.CouponStore,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, store: *persist.CouponStore) CouponService {
        return .{ .allocator = allocator, .io = io, .store = store };
    }

    fn now(self: *CouponService) i64 {
        return zigmodu.time.wallClockSeconds(self.io);
    }

    pub fn createCoupon(self: *CouponService, tenant_id: i64, account_id: i64, title: []const u8, amount: i64, min_amount: i64, total: i64, per_user: i64, start_at: i64, end_at: i64) CouponError!i64 {
        if (std.mem.trim(u8, title, " \t").len == 0) return error.InvalidInput;
        if (amount < 0 or min_amount < 0 or total < 0) return error.InvalidInput;
        if (per_user < 1) return error.InvalidInput;
        return self.store.createCoupon(tenant_id, account_id, title, amount, min_amount, total, @max(1, per_user), start_at, end_at, self.now()) catch error.Unexpected;
    }

    pub fn listCoupons(self: *CouponService, page: usize, page_size: usize, tenant_id: i64, account_id: i64) CouponError!CouponListResult {
        return self.store.listCoupons(page, page_size, tenant_id, account_id) catch error.Unexpected;
    }

    pub fn getCoupon(self: *CouponService, id: i64) CouponError!?CouponRow {
        return self.store.getCoupon(id) catch error.Unexpected;
    }

    pub fn deleteCoupon(self: *CouponService, id: i64) CouponError!void {
        self.store.deleteCoupon(id) catch return error.Unexpected;
    }

    /// 领券：库存 + 每人限领 + 有效期校验，通过后生成券码落库。返回券码（caller free）。
    pub fn claimCoupon(self: *CouponService, allocator: std.mem.Allocator, tenant_id: i64, account_id: i64, openid: []const u8, coupon_id: i64) CouponError![]u8 {
        const c_opt = self.store.getCoupon(coupon_id) catch return error.Unexpected;
        const c = c_opt orelse return error.NotFound;
        defer c.free(self.allocator);

        const now_secs = self.now();
        if (c.start_at > 0 and now_secs < c.start_at) return error.NotStarted;
        if (c.end_at > 0 and now_secs > c.end_at) return error.Expired;

        // 库存检查（total=0 不限量）。
        if (c.total > 0) {
            const issued = self.store.countIssued(coupon_id) catch return error.Unexpected;
            if (issued >= c.total) return error.OutOfStock;
        }
        // 每人限领。
        const held = self.store.countUserCoupons(tenant_id, coupon_id, openid) catch return error.Unexpected;
        if (held >= c.per_user) return error.LimitReached;

        const code = self.genCode(allocator) catch return error.Unexpected;
        errdefer allocator.free(code);
        _ = self.store.createUserCoupon(tenant_id, account_id, openid, coupon_id, code, now_secs) catch return error.Unexpected;
        return code;
    }

    /// 核销：unused→used（幂等）。已 used 返回 AlreadyUsed。
    pub fn useCoupon(self: *CouponService, code: []const u8) CouponError!void {
        const u_opt = self.store.getByCode(code) catch return error.Unexpected;
        const u = u_opt orelse return error.NotFound;
        defer u.free(self.allocator);
        if (std.mem.eql(u8, u.status, "used")) return error.AlreadyUsed;
        if (std.mem.eql(u8, u.status, "expired")) return error.Expired;
        self.store.setStatus(u.id, "used", self.now()) catch return error.Unexpected;
    }

    pub fn listUserCoupons(self: *CouponService, page: usize, page_size: usize, tenant_id: i64, account_id: i64, openid: ?[]const u8) CouponError!CouponUserListResult {
        return self.store.listUserCoupons(page, page_size, tenant_id, account_id, openid) catch error.Unexpected;
    }

    /// 生成券码 `CP-XXXXXXXX`（8 字节 hex）。
    fn genCode(self: *CouponService, allocator: std.mem.Allocator) ![]u8 {
        var buf: [8]u8 = undefined;
        var file = try std.Io.Dir.cwd().openFile(self.io, "/dev/urandom", .{});
        defer file.close(self.io);
        const read = try file.readPositionalAll(self.io, &buf, 0);
        if (read != buf.len) return error.Unexpected;
        return std.fmt.allocPrint(allocator, "CP-{x:0>16}", .{std.mem.readInt(u64, &buf, .little)});
    }
};

/// Receiver context — 模块注册表（判断账号已绑定）+ 优惠券服务。
pub const ReceiverCtx = struct {
    module_svc: *module_mod.ModuleService,
    coupon_svc: *CouponService,
    io: std.Io,
};

/// `Receiver.handle`：识别「领券」，领取该账号第一个可领的券并回复券码。
pub fn receiverHandle(ctx: ?*anyopaque, allocator: std.mem.Allocator, msg: message_mod.IncomingMessage) anyerror!?message_mod.Reply {
    const c: *ReceiverCtx = @ptrCast(@alignCast(ctx orelse return null));
    if (!std.mem.eql(u8, msg.msg_type, "text")) return null;
    if (!std.mem.eql(u8, msg.content, "领券")) return null;

    // 取该账号下第一个可领的券（按创建倒序）。
    var coupons = c.coupon_svc.listCoupons(1, 10, msg.tenant_id, msg.account_id) catch return null;
    defer coupons.free(allocator);
    if (coupons.items.len == 0) return null;

    var claimed: ?[]u8 = null;
    for (coupons.items) |cp| {
        claimed = c.coupon_svc.claimCoupon(allocator, msg.tenant_id, msg.account_id, msg.openid, cp.id) catch |err| switch (err) {
            error.OutOfStock, error.LimitReached, error.Expired, error.NotStarted => continue,
            else => null,
        };
        if (claimed != null) break;
    }
    const code = claimed orelse {
        return try message_mod.Reply.text(allocator, "优惠券已领完或暂未开放");
    };
    defer allocator.free(code);

    const text = try std.fmt.allocPrint(allocator, "🎫 领券成功！券码：{s}（核销时出示）", .{code});
    defer allocator.free(text);
    return try message_mod.Reply.text(allocator, text);
}
