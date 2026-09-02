//! MemberCard service — 卡等级 + 会员积分账户业务 + message 模块 Receiver 接入。
//!
//! 经典会员体系：公众号「办卡」开卡（自动匹配最低等级）、「查卡」查积分/
//! 等级/折扣；积分调整（消费累计、兑换消耗）自动触发升降级。

const std = @import("std");
const zigmodu = @import("zigmodu");
const zent = @import("zent");
const persist = @import("persistence.zig");
const message_mod = @import("../message/service.zig");

pub const MemberCardLevelRow = persist.MemberCardLevelRow;
pub const MemberAccountRow = persist.MemberAccountRow;
pub const LevelListResult = persist.LevelListResult;

pub const MemberCardError = error{
    InvalidInput,
    NotFound,
    AlreadyOpened,
    InsufficientPoints,
    InvalidState,
    Unexpected,
};

pub const AccountView = struct {
    openid: []const u8,
    level_name: []const u8,
    level: i64,
    discount: i64,
    points: i64,
    total_points: i64,
    created_at: i64,

    pub fn free(self: AccountView, allocator: std.mem.Allocator) void {
        allocator.free(self.openid);
        allocator.free(self.level_name);
    }
};

pub const MemberCardService = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    store: *persist.MemberCardStore,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, store: *persist.MemberCardStore) MemberCardService {
        return .{ .allocator = allocator, .io = io, .store = store };
    }

    fn now(self: *MemberCardService) i64 {
        return zigmodu.time.wallClockSeconds(self.io);
    }

    pub fn createLevel(self: *MemberCardService, tenant_id: i64, account_id: i64, name: []const u8, level: i64, discount: i64, points_ratio: i64, threshold: i64, status: i64) MemberCardError!i64 {
        if (std.mem.trim(u8, name, " \t").len == 0 or discount <= 0 or discount > 1000) return error.InvalidInput;
        return self.store.createLevel(tenant_id, account_id, name, level, discount, points_ratio, threshold, status, self.now()) catch error.Unexpected;
    }

    /// `status` 为 -1 表示不过滤；0 停用 / 1 启用。
    pub fn listLevels(self: *MemberCardService, page: usize, page_size: usize, tenant_id: i64, account_id: i64, keyword: []const u8, status: i64) MemberCardError!LevelListResult {
        return self.store.listLevels(page, page_size, tenant_id, account_id, keyword, status) catch error.Unexpected;
    }

    /// 启停等级：1 启用 / 0 停用。已开卡会员的等级不受影响。
    pub fn setLevelStatus(self: *MemberCardService, id: i64, status: i64) MemberCardError!bool {
        return self.store.setLevelStatus(id, status, self.now()) catch error.Unexpected;
    }

    /// 整体更新卡等级（account 作用域不变：account_id 不参与更新）。
    /// `name` 空或 `discount` 越界（千分比须在 (0,1000]，同 `createLevel`，不做
    /// 单位换算）→ InvalidInput；等级不存在或不属于本 tenant → NotFound。
    /// store 影响 0 行也视为成功（幂等）。
    pub fn updateLevel(self: *MemberCardService, tenant_id: i64, id: i64, name: []const u8, level: i64, discount: i64, points_ratio: i64, threshold: i64, status: i64) MemberCardError!void {
        if (std.mem.trim(u8, name, " \t").len == 0 or discount <= 0 or discount > 1000) return error.InvalidInput;
        const l_opt = self.store.getById(tenant_id, id) catch return error.Unexpected;
        const l = l_opt orelse return error.NotFound;
        defer l.free(self.allocator);
        _ = self.store.updateLevel(id, name, level, discount, points_ratio, threshold, status, self.now()) catch return error.Unexpected;
    }

    /// 删除卡等级（不级联）：等级不存在或不属于本 tenant → NotFound；
    /// 有会员引用该等级（删除守卫）→ InvalidState（先迁走会员等级再删）。
    pub fn deleteLevel(self: *MemberCardService, tenant_id: i64, id: i64) MemberCardError!void {
        const l_opt = self.store.getById(tenant_id, id) catch return error.Unexpected;
        const l = l_opt orelse return error.NotFound;
        defer l.free(self.allocator);
        const refs = self.store.countMembersByLevel(id) catch return error.Unexpected;
        if (refs > 0) return error.InvalidState;
        self.store.deleteLevel(id) catch return error.Unexpected;
    }

    pub fn listAccounts(self: *MemberCardService, page: usize, page_size: usize, tenant_id: i64, account_id: i64, keyword: []const u8) MemberCardError!persist.MemberAccountListResult {
        return self.store.listAccounts(page, page_size, tenant_id, account_id, keyword) catch error.Unexpected;
    }

    /// 开卡：openid 一卡唯一；自动匹配最低等级（threshold 最小的等级）。
    pub fn openCard(self: *MemberCardService, tenant_id: i64, account_id: i64, openid: []const u8) MemberCardError!void {
        if (std.mem.trim(u8, openid, " \t").len == 0) return error.InvalidInput;
        if (self.store.getAccountByOpenid(tenant_id, account_id, openid) catch return error.Unexpected) |existing| {
            existing.free(self.allocator);
            return error.AlreadyOpened;
        }
        // 最低等级：threshold=0 的等级；若无则 level 最小的等级。
        const base = self.baseLevel(tenant_id, account_id) catch return error.Unexpected;
        const base_id = base orelse {
            // 无等级配置 → 先建默认「普通会员」。
            _ = self.store.createAccount(tenant_id, account_id, openid, 0, self.now()) catch return error.Unexpected;
            return;
        };
        defer base_id.free(self.allocator);
        _ = self.store.createAccount(tenant_id, account_id, openid, base_id.id, self.now()) catch return error.Unexpected;
    }

    fn baseLevel(self: *MemberCardService, tenant_id: i64, account_id: i64) !?MemberCardLevelRow {
        var q = self.store.client.member_card_level.Query();
        defer q.deinit();
        const preds = self.store.client.member_card_level.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        // 停用等级不再匹配给新开卡会员（已有会员保留原等级）。
        _ = try q.Where(.{preds.statusEQ(.{ .int = 1 })});
        _ = try q.OrderBy(&[_]zent.sql.Order{ zent.sql.OrderAsc("threshold"), zent.sql.OrderAsc("level") });
        _ = q.Limit(1);
        const entity_opt = try q.First();
        var entity = entity_opt orelse return null;
        defer zent.codegen.deinitEntity(persist.infos, persist.MemberCardLevelInfo, &entity, self.allocator);
        const name = try self.allocator.dupe(u8, entity.name);
        errdefer self.allocator.free(name);
        return .{
            .id = entity.id,
            .account_id = entity.account_id,
            .name = name,
            .level = entity.level,
            .discount = entity.discount,
            .points_ratio = entity.points_ratio,
            .threshold = entity.threshold,
            .status = entity.status,
            .created_at = entity.created_at orelse 0,
        };
    }

    /// 查卡：openid → 账户 + 等级视图。
    pub fn view(self: *MemberCardService, tenant_id: i64, account_id: i64, openid: []const u8) MemberCardError!?AccountView {
        const acc_opt = self.store.getAccountByOpenid(tenant_id, account_id, openid) catch return error.Unexpected;
        const acc = acc_opt orelse return null;
        defer acc.free(self.allocator);
        const lvl_opt = self.store.getLevel(acc.level_id) catch return error.Unexpected;
        const lvl = lvl_opt orelse return null;
        defer lvl.free(self.allocator);
        const openid_dup = self.allocator.dupe(u8, acc.openid) catch return error.Unexpected;
        errdefer self.allocator.free(openid_dup);
        const name_dup = self.allocator.dupe(u8, lvl.name) catch return error.Unexpected;
        errdefer self.allocator.free(name_dup);
        return .{
            .openid = openid_dup,
            .level_name = name_dup,
            .level = lvl.level,
            .discount = lvl.discount,
            .points = acc.points,
            .total_points = acc.total_points,
            .created_at = acc.created_at,
        };
    }

    /// 积分调整：delta>0 加积分（累计+余额），delta<0 消耗（余额不足拒绝）；
    /// 调整后按累计积分自动升降级。
    pub fn adjust(self: *MemberCardService, tenant_id: i64, account_id: i64, openid: []const u8, delta: i64) MemberCardError!void {
        const acc_opt = self.store.getAccountByOpenid(tenant_id, account_id, openid) catch return error.Unexpected;
        const acc = acc_opt orelse return error.NotFound;
        defer acc.free(self.allocator);
        if (delta < 0 and acc.points + delta < 0) return error.InsufficientPoints;
        if (!(self.store.adjustPoints(acc.id, delta) catch return error.Unexpected)) return error.Unexpected;

        // 升降级：按累计积分匹配最高等级。
        const new_total = acc.total_points + @max(delta, 0);
        if (self.store.levelForPoints(tenant_id, account_id, new_total) catch return error.Unexpected) |lvl| {
            defer lvl.free(self.allocator);
            if (lvl.id != acc.level_id) {
                self.store.setLevel(acc.id, lvl.id) catch {};
            }
        }
    }
};

/// Receiver context。
pub const ReceiverCtx = struct {
    io: std.Io,
    member_svc: *MemberCardService,
};

/// `Receiver.handle`：识别「办卡」（开卡）与「查卡」（查积分/等级/折扣）。
pub fn receiverHandle(ctx: ?*anyopaque, allocator: std.mem.Allocator, msg: message_mod.IncomingMessage) anyerror!?message_mod.Reply {
    const c: *ReceiverCtx = @ptrCast(@alignCast(ctx orelse return null));
    if (!std.mem.eql(u8, msg.msg_type, "text")) return null;

    if (std.mem.eql(u8, msg.content, "办卡")) {
        c.member_svc.openCard(msg.tenant_id, msg.account_id, msg.openid) catch |err| switch (err) {
            error.AlreadyOpened => return try message_mod.Reply.text(allocator, "你已经办过会员卡啦，回复「查卡」查看"),
            else => return null,
        };
        return try message_mod.Reply.text(allocator, "🎫 办卡成功！欢迎加入会员，回复「查卡」查看等级与积分");
    }

    if (std.mem.eql(u8, msg.content, "查卡")) {
        const v_opt = c.member_svc.view(msg.tenant_id, msg.account_id, msg.openid) catch return null;
        const v = v_opt orelse return try message_mod.Reply.text(allocator, "你还没有会员卡，回复「办卡」免费开通");
        defer v.free(allocator);
        var buf = std.ArrayList(u8).empty;
        defer buf.deinit(allocator);
        try buf.appendSlice(allocator, "🎫 会员卡：");
        try buf.appendSlice(allocator, v.level_name);
        try buf.appendSlice(allocator, "\n💳 积分：");
        const pts = std.fmt.allocPrint(allocator, "{d}", .{v.points}) catch "?";
        defer allocator.free(pts);
        try buf.appendSlice(allocator, pts);
        try buf.appendSlice(allocator, "\n🏷 折扣：");
        const discount_yuan = @divTrunc(v.discount, 100);
        const discount_fen = @mod(v.discount, 100);
        const discount_str = if (discount_fen == 0)
            (std.fmt.allocPrint(allocator, "{d} 折", .{discount_yuan}) catch "?")
        else
            (std.fmt.allocPrint(allocator, "{d}.{d} 折", .{ discount_yuan, discount_fen }) catch "?");
        defer allocator.free(discount_str);
        try buf.appendSlice(allocator, discount_str);
        return try message_mod.Reply.text(allocator, buf.items);
    }
    return null;
}
