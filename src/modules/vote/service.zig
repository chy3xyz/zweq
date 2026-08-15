//! Vote service — 投票主题/投票/计票业务 + message 模块 Receiver 接入。
//!
//! 互动场景：投票主题（选项 JSON）→ 用户投票（防重：同 openid 同投票仅一票）
//! → 计票。公众号「投票」列出最新题目，「投N」投票。

const std = @import("std");
const zigmodu = @import("zigmodu");
const persist = @import("persistence.zig");
const message_mod = @import("../message/service.zig");
const module_mod = @import("../module/service.zig");

pub const VoteRow = persist.VoteRow;
pub const VoteListResult = persist.VoteListResult;

pub const VoteError = error{
    InvalidInput,
    NotFound,
    AlreadyVoted,
    Ended,
    InvalidOption,
    Unexpected,
};

pub const VoteService = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    store: *persist.VoteStore,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, store: *persist.VoteStore) VoteService {
        return .{ .allocator = allocator, .io = io, .store = store };
    }

    fn now(self: *VoteService) i64 {
        return zigmodu.time.wallClockSeconds(self.io);
    }

    pub fn createVote(self: *VoteService, tenant_id: i64, account_id: i64, title: []const u8, options_json: []const u8, end_at: i64) VoteError!i64 {
        if (std.mem.trim(u8, title, " \t").len == 0) return error.InvalidInput;
        return self.store.createVote(tenant_id, account_id, title, options_json, end_at, self.now()) catch error.Unexpected;
    }

    pub fn listVotes(self: *VoteService, page: usize, page_size: usize, tenant_id: i64, account_id: i64) VoteError!VoteListResult {
        return self.store.listVotes(page, page_size, tenant_id, account_id) catch error.Unexpected;
    }

    pub fn getVote(self: *VoteService, id: i64) VoteError!?VoteRow {
        return self.store.getVote(id) catch error.Unexpected;
    }

    /// 投票：防重 + 选项合法性 + 截止校验。
    pub fn vote(self: *VoteService, tenant_id: i64, account_id: i64, openid: []const u8, vote_id: i64, option_index: i64) VoteError!void {
        const v_opt = self.store.getVote(vote_id) catch return error.Unexpected;
        const v = v_opt orelse return error.NotFound;
        defer v.free(self.allocator);

        const options = self.parseOptions(self.allocator, v.options_json);
        defer freeOptions(self.allocator, options);
        if (option_index < 0 or option_index >= @as(i64, @intCast(options.len))) return error.InvalidOption;
        if (v.end_at > 0 and self.now() > v.end_at) return error.Ended;

        if (self.store.findRecord(tenant_id, vote_id, openid) catch return error.Unexpected) return error.AlreadyVoted;
        _ = self.store.createRecord(tenant_id, account_id, openid, vote_id, option_index, self.now()) catch return error.Unexpected;
    }

    /// 计票：各选项票数（caller free）。
    pub fn tally(self: *VoteService, allocator: std.mem.Allocator, vote_id: i64) VoteError![]i64 {
        const v_opt = self.store.getVote(vote_id) catch return error.Unexpected;
        const v = v_opt orelse return error.NotFound;
        defer v.free(self.allocator);
        const options = self.parseOptions(self.allocator, v.options_json);
        defer freeOptions(self.allocator, options);
        return self.store.tally(allocator, vote_id, options.len) catch error.Unexpected;
    }

    /// 解析选项 JSON 数组（caller freeOptions）。
    pub fn parseOptions(self: *VoteService, allocator: std.mem.Allocator, options_json: []const u8) [][]const u8 {
        _ = self;
        var parsed = std.json.parseFromSlice(std.json.Value, allocator, options_json, .{}) catch return &.{};
        defer parsed.deinit();
        var out = std.ArrayList([]const u8).empty;
        errdefer {
            for (out.items) |o| allocator.free(o);
            out.deinit(allocator);
        }
        switch (parsed.value) {
            .array => |arr| {
                for (arr.items) |item| {
                    const s = switch (item) {
                        .string => |s| s,
                        else => continue,
                    };
                    const dup = allocator.dupe(u8, s) catch continue;
                    out.append(allocator, dup) catch {
                        allocator.free(dup);
                        continue;
                    };
                }
            },
            else => {},
        }
        return out.toOwnedSlice(allocator) catch &.{};
    }
};

fn freeOptions(allocator: std.mem.Allocator, options: [][]const u8) void {
    for (options) |o| allocator.free(o);
    if (options.len > 0) allocator.free(options);
}

/// Receiver context。
pub const ReceiverCtx = struct {
    module_svc: *module_mod.ModuleService,
    vote_svc: *VoteService,
    io: std.Io,
};

/// `Receiver.handle`：识别「投票」（列题目）与「投N」（投票）。
pub fn receiverHandle(ctx: ?*anyopaque, allocator: std.mem.Allocator, msg: message_mod.IncomingMessage) anyerror!?message_mod.Reply {
    const c: *ReceiverCtx = @ptrCast(@alignCast(ctx orelse return null));
    if (!std.mem.eql(u8, msg.msg_type, "text")) return null;

    if (std.mem.eql(u8, msg.content, "投票")) {
        const v_opt = c.vote_svc.store.latestVote(msg.tenant_id, msg.account_id) catch return null;
        const v = v_opt orelse return null;
        defer v.free(allocator);
        const options = c.vote_svc.parseOptions(allocator, v.options_json);
        defer freeOptions(allocator, options);
        if (options.len == 0) return null;
        var buf = std.ArrayList(u8).empty;
        defer buf.deinit(allocator);
        try buf.appendSlice(allocator, "📊 ");
        try buf.appendSlice(allocator, v.title);
        try buf.appendSlice(allocator, "\n回复「投N」投票：");
        for (options, 0..) |o, i| {
            const line = std.fmt.allocPrint(allocator, "\n{d}. {s}", .{ i + 1, o }) catch continue;
            defer allocator.free(line);
            try buf.appendSlice(allocator, line);
        }
        return try message_mod.Reply.text(allocator, buf.items);
    }

    if (std.mem.startsWith(u8, msg.content, "投")) {
        const num_str = std.mem.trim(u8, msg.content[3..], " \t");
        const n = std.fmt.parseInt(i64, num_str, 10) catch return null;
        const v_opt = c.vote_svc.store.latestVote(msg.tenant_id, msg.account_id) catch return null;
        const v = v_opt orelse return null;
        defer v.free(allocator);
        c.vote_svc.vote(msg.tenant_id, msg.account_id, msg.openid, v.id, n - 1) catch |err| switch (err) {
            error.AlreadyVoted => return try message_mod.Reply.text(allocator, "你已经投过票啦"),
            error.InvalidOption => return null,
            error.Ended => return try message_mod.Reply.text(allocator, "投票已结束"),
            else => return null,
        };
        return try message_mod.Reply.text(allocator, "✅ 投票成功，谢谢参与！");
    }
    return null;
}
