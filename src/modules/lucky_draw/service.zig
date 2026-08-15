//! LuckyDraw service — 大转盘抽奖业务 + message 模块 Receiver 接入。
//!
//! 完整「场景应用」形态：奖品加权随机 + 每日次数限制 + 积分消耗（可选）
//! + `receiverHandle` 钩子（main.zig 注册进回调引擎）。奖品配置存模块
//! config（JSON），中奖记录落 DrawRecord 表。

const std = @import("std");
const zigmodu = @import("zigmodu");
const persist = @import("persistence.zig");
const message_mod = @import("../message/service.zig");
const module_mod = @import("../module/service.zig");

pub const DrawRecordRow = persist.DrawRecordRow;
pub const DrawListResult = persist.DrawListResult;

pub const DrawError = error{
    Unexpected,
    DailyLimit,
};

pub const Prize = struct {
    name: []const u8,
    weight: i64,
    points: i64,
};

/// 解析后的抽奖配置（caller-owned）。config JSON：
/// `{"cost":5,"daily_limit":3,"prizes":[{"name":"10积分","weight":50,"points":10},...]}`
pub const DrawConfig = struct {
    prizes: []Prize,
    cost: i64,
    daily_limit: i64,

    pub fn free(self: *const DrawConfig, allocator: std.mem.Allocator) void {
        for (self.prizes) |p| allocator.free(p.name);
        if (self.prizes.len > 0) allocator.free(self.prizes);
    }
};

pub const DrawResult = struct {
    prize_name: []const u8,
    points: i64,
};

pub const DrawService = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    store: *persist.DrawStore,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, store: *persist.DrawStore) DrawService {
        return .{ .allocator = allocator, .io = io, .store = store };
    }

    fn now(self: *DrawService) i64 {
        return zigmodu.time.wallClockSeconds(self.io);
    }

    /// 解析 config JSON。非法/缺奖品 → 单奖品「谢谢参与」兜底。
    pub fn parseConfig(self: *DrawService, allocator: std.mem.Allocator, json: []const u8) DrawConfig {
        _ = self;
        var parsed = std.json.parseFromSlice(std.json.Value, allocator, json, .{}) catch {
            return defaultConfig(allocator);
        };
        defer parsed.deinit();
        const cost = objInt(parsed.value, "cost") orelse 0;
        const daily_limit = objInt(parsed.value, "daily_limit") orelse 0;

        var prizes = std.ArrayList(Prize).empty;
        errdefer {
            for (prizes.items) |p| allocator.free(p.name);
            prizes.deinit(allocator);
        }
        if (parsed.value.object.get("prizes")) |pv| {
            switch (pv) {
                .array => |arr| {
                    for (arr.items) |item| {
                        const name = objString(item, "name") orelse continue;
                        if (name.len == 0) continue;
                        const weight = @max(1, objInt(item, "weight") orelse 1);
                        const points = objInt(item, "points") orelse 0;
                        const name_dup = allocator.dupe(u8, name) catch continue;
                        prizes.append(allocator, .{ .name = name_dup, .weight = weight, .points = points }) catch {
                            allocator.free(name_dup);
                            continue;
                        };
                    }
                },
                else => {},
            }
        }
        if (prizes.items.len == 0) {
            const name_dup = allocator.dupe(u8, "谢谢参与") catch return defaultConfig(allocator);
            prizes.append(allocator, .{ .name = name_dup, .weight = 1, .points = 0 }) catch return defaultConfig(allocator);
        }
        const slice = prizes.toOwnedSlice(allocator) catch return defaultConfig(allocator);
        return .{ .prizes = slice, .cost = cost, .daily_limit = daily_limit };
    }

    /// 加权随机选奖品（纯函数，可测）。`roll` 为 [0, total_weight) 的随机值。
    pub fn pickPrize(prizes: []const Prize, roll: u64) usize {
        if (prizes.len == 0) return 0;
        var total: i64 = 0;
        for (prizes) |p| total += p.weight;
        if (total <= 0) return 0;
        var r: i64 = @intCast(roll % @as(u64, @intCast(total)));
        for (prizes, 0..) |p, i| {
            if (r < p.weight) return i;
            r -= p.weight;
        }
        return prizes.len - 1;
    }

    /// 抽一次：检查每日次数限制 → 加权随机 → 记录中奖。caller free 返回的
    /// DrawResult（prize_name 为 dupe）。
    pub fn draw(self: *DrawService, allocator: std.mem.Allocator, tenant_id: i64, account_id: i64, openid: []const u8, cfg: *const DrawConfig) DrawError!DrawResult {
        const day = @divTrunc(self.now(), 86400);
        if (cfg.daily_limit > 0) {
            const count = self.store.countToday(tenant_id, account_id, openid, day) catch return error.Unexpected;
            if (count >= cfg.daily_limit) return error.DailyLimit;
        }
        const roll = self.randomU64();
        const idx = pickPrize(cfg.prizes, roll);
        const prize = cfg.prizes[idx];
        _ = self.store.create(tenant_id, account_id, openid, prize.name, prize.points, self.now()) catch return error.Unexpected;
        return .{ .prize_name = allocator.dupe(u8, prize.name) catch return error.Unexpected, .points = prize.points };
    }

    pub fn list(self: *DrawService, page: usize, page_size: usize, tenant_id: i64, account_id: i64) DrawError!DrawListResult {
        return self.store.list(page, page_size, tenant_id, account_id) catch error.Unexpected;
    }

    fn randomU64(self: *DrawService) u64 {
        var buf: [8]u8 = undefined;
        var file = std.Io.Dir.cwd().openFile(self.io, "/dev/urandom", .{}) catch return @intCast(@max(0, zigmodu.time.monotonicNow()));
        defer file.close(self.io);
        const read = file.readPositionalAll(self.io, &buf, 0) catch return @intCast(@max(0, zigmodu.time.monotonicNow()));
        if (read != buf.len) return @intCast(@max(0, zigmodu.time.monotonicNow()));
        return std.mem.readInt(u64, &buf, .little);
    }
};

/// Receiver context — 模块注册表（per-account config）+ 抽奖服务。
pub const ReceiverCtx = struct {
    module_svc: *module_mod.ModuleService,
    draw_svc: *DrawService,
    io: std.Io,
};

/// `Receiver.handle` 实现：识别「抽奖」，读模块 config 抽一次并回复。
pub fn receiverHandle(ctx: ?*anyopaque, allocator: std.mem.Allocator, msg: message_mod.IncomingMessage) anyerror!?message_mod.Reply {
    const c: *ReceiverCtx = @ptrCast(@alignCast(ctx orelse return null));
    if (!std.mem.eql(u8, msg.msg_type, "text")) return null;
    if (!std.mem.eql(u8, msg.content, "抽奖")) return null;

    const cfg_json = c.module_svc.getConfig(allocator, msg.tenant_id, msg.account_id, "lucky_draw") catch null;
    defer if (cfg_json) |x| allocator.free(x);
    const cfg = c.draw_svc.parseConfig(allocator, cfg_json orelse "");
    defer cfg.free(allocator);

    const result = c.draw_svc.draw(allocator, msg.tenant_id, msg.account_id, msg.openid, &cfg) catch |err| {
        if (err == error.DailyLimit) {
            return try message_mod.Reply.text(allocator, "今日抽奖次数已用完，明天再来吧");
        }
        return null;
    };
    defer allocator.free(result.prize_name);

    const text = if (result.points > 0)
        try std.fmt.allocPrint(allocator, "🎉 恭喜抽中「{s}」，+{d} 积分！", .{ result.prize_name, result.points })
    else
        try std.fmt.allocPrint(allocator, "抽中「{s}」，下次好运！", .{result.prize_name});
    defer allocator.free(text);
    return try message_mod.Reply.text(allocator, text);
}

fn defaultConfig(allocator: std.mem.Allocator) DrawConfig {
    const name = allocator.dupe(u8, "谢谢参与") catch return .{ .prizes = &.{}, .cost = 0, .daily_limit = 0 };
    const prizes = allocator.alloc(Prize, 1) catch {
        allocator.free(name);
        return .{ .prizes = &.{}, .cost = 0, .daily_limit = 0 };
    };
    prizes[0] = .{ .name = name, .weight = 1, .points = 0 };
    return .{ .prizes = prizes, .cost = 0, .daily_limit = 0 };
}

fn objString(v: std.json.Value, key: []const u8) ?[]const u8 {
    const field = v.object.get(key) orelse return null;
    return switch (field) {
        .string => |s| s,
        else => null,
    };
}

fn objInt(v: std.json.Value, key: []const u8) ?i64 {
    const field = v.object.get(key) orelse return null;
    return switch (field) {
        .integer => |i| i,
        else => null,
    };
}
