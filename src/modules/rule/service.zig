//! Rule service — keyword auto-reply engine. No HTTP/SQL leakage.

const std = @import("std");
const zigmodu = @import("zigmodu");
const persist = @import("persistence.zig");

pub const RuleRow = persist.RuleRow;
pub const RuleKeywordRow = persist.RuleKeywordRow;
pub const RuleReplyRow = persist.RuleReplyRow;
pub const RuleListResult = persist.RuleListResult;

pub const RuleError = error{
    InvalidName,
    InvalidStatus,
    InvalidKeyword,
    InvalidMatchType,
    InvalidReplyType,
    NotFound,
    Unexpected,
};

pub fn validStatus(status: []const u8) bool {
    return std.mem.eql(u8, status, "active") or std.mem.eql(u8, status, "disabled");
}

pub fn validMatchType(mt: []const u8) bool {
    return std.mem.eql(u8, mt, "full") or std.mem.eql(u8, mt, "contain");
}

pub fn validReplyType(rt: []const u8) bool {
    return std.mem.eql(u8, rt, "text") or std.mem.eql(u8, rt, "news");
}

/// Deep-copy a reply row into caller-owned memory (the source slice/rows are
/// freed by the caller's defer).
fn dupReplyRow(allocator: std.mem.Allocator, src: persist.RuleReplyRow) !persist.RuleReplyRow {
    const reply_type = try allocator.dupe(u8, src.reply_type);
    errdefer allocator.free(reply_type);
    const content = try allocator.dupe(u8, src.content);
    errdefer allocator.free(content);
    const news_title = try allocator.dupe(u8, src.news_title);
    errdefer allocator.free(news_title);
    const news_description = try allocator.dupe(u8, src.news_description);
    errdefer allocator.free(news_description);
    const news_pic_url = try allocator.dupe(u8, src.news_pic_url);
    errdefer allocator.free(news_pic_url);
    const news_url = try allocator.dupe(u8, src.news_url);
    errdefer allocator.free(news_url);
    return .{
        .id = src.id,
        .rule_id = src.rule_id,
        .reply_type = reply_type,
        .content = content,
        .news_title = news_title,
        .news_description = news_description,
        .news_pic_url = news_pic_url,
        .news_url = news_url,
    };
}

pub const RuleService = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    store: *persist.RuleStore,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, store: *persist.RuleStore) RuleService {
        return .{ .allocator = allocator, .io = io, .store = store };
    }

    fn now(self: *RuleService) i64 {
        return zigmodu.time.wallClockSeconds(self.io);
    }

    pub fn createRule(self: *RuleService, tenant_id: i64, account_id: i64, name: []const u8) RuleError!i64 {
        if (std.mem.trim(u8, name, " \t").len == 0) return error.InvalidName;
        return self.store.createRule(tenant_id, account_id, name, "active", self.now()) catch error.Unexpected;
    }

    pub fn getRule(self: *RuleService, id: i64) RuleError!?RuleRow {
        return self.store.getRule(id) catch error.Unexpected;
    }

    pub fn listRules(self: *RuleService, page: usize, page_size: usize, tenant_id: i64, account_id: i64) RuleError!RuleListResult {
        return self.store.listRules(page, page_size, tenant_id, account_id) catch error.Unexpected;
    }

    pub fn updateRule(self: *RuleService, id: i64, name: []const u8, status: []const u8) RuleError!void {
        if (std.mem.trim(u8, name, " \t").len == 0) return error.InvalidName;
        if (!validStatus(status)) return error.InvalidStatus;
        self.store.updateRule(id, name, status, self.now()) catch return error.Unexpected;
    }

    pub fn deleteRule(self: *RuleService, id: i64) RuleError!void {
        self.store.deleteRule(id) catch return error.Unexpected;
    }

    // ── Keywords / replies ────────────────────────────────────────

    pub fn addKeyword(self: *RuleService, tenant_id: i64, account_id: i64, rule_id: i64, keyword: []const u8, match_type: []const u8) RuleError!i64 {
        if (std.mem.trim(u8, keyword, " \t").len == 0) return error.InvalidKeyword;
        if (!validMatchType(match_type)) return error.InvalidMatchType;
        return self.store.addKeyword(tenant_id, account_id, rule_id, keyword, match_type, self.now()) catch error.Unexpected;
    }

    pub fn removeKeyword(self: *RuleService, id: i64) RuleError!void {
        self.store.removeKeyword(id) catch return error.Unexpected;
    }

    pub fn addReply(self: *RuleService, tenant_id: i64, account_id: i64, rule_id: i64, reply_type: []const u8, content: []const u8, news_title: []const u8, news_description: []const u8, news_pic_url: []const u8, news_url: []const u8) RuleError!i64 {
        if (!validReplyType(reply_type)) return error.InvalidReplyType;
        if (std.mem.eql(u8, reply_type, "text") and std.mem.trim(u8, content, " \t").len == 0) return error.InvalidReplyType;
        return self.store.addReply(tenant_id, account_id, rule_id, reply_type, content, news_title, news_description, news_pic_url, news_url, self.now()) catch error.Unexpected;
    }

    pub fn removeReply(self: *RuleService, id: i64) RuleError!void {
        self.store.removeReply(id) catch return error.Unexpected;
    }

    /// Match a message against the account's keyword rules. Returns a
    /// caller-owned copy of the first active rule's first reply, or null.
    pub fn match(self: *RuleService, allocator: std.mem.Allocator, tenant_id: i64, account_id: i64, content: []const u8) RuleError!?RuleReplyRow {
        if (content.len == 0) return null;
        const keywords = self.store.listKeywordsForAccount(tenant_id, account_id) catch return error.Unexpected;
        defer {
            for (keywords) |k| k.free(allocator);
            allocator.free(keywords);
        }

        // First matching rule wins (keywords ordered by rule_id).
        for (keywords) |k| {
            const hit = if (std.mem.eql(u8, k.match_type, "full"))
                std.mem.eql(u8, k.keyword, content)
            else
                std.mem.indexOf(u8, content, k.keyword) != null;
            if (!hit) continue;

            const rule_opt = self.store.getRule(k.rule_id) catch return error.Unexpected;
            const rule = rule_opt orelse continue;
            const active = std.mem.eql(u8, rule.status, "active");
            rule.free(allocator);
            if (!active) continue;

            const replies = self.store.listRepliesForRule(k.rule_id) catch return error.Unexpected;
            defer {
                for (replies) |r| r.free(allocator);
                allocator.free(replies);
            }
            if (replies.len == 0) return null;
            return dupReplyRow(allocator, replies[0]) catch return error.Unexpected;
        }
        return null;
    }
};
