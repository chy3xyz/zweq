//! Persistence over the zent Client — auto-reply rules, keywords, replies.

const std = @import("std");
const zent = @import("zent");
const model = @import("model.zig");
const schema = @import("../../schema.zig");

const graph = zent.codegen.graph.buildGraph(&.{ model.Rule, model.RuleKeyword, model.RuleReply });
pub const infos = graph.types;
/// Shared, application-wide typed client (all schemas registered in schema.zig).
pub const Client = schema.Client;
pub const RuleInfo = infos[0];
pub const RuleKeywordInfo = infos[1];
pub const RuleReplyInfo = infos[2];

pub const RuleRow = struct {
    id: i64,
    tenant_id: i64,
    account_id: i64,
    name: []const u8,
    status: []const u8,
    created_at: i64,
    updated_at: i64,

    pub fn free(self: RuleRow, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.status);
    }
};

pub const RuleListResult = struct {
    items: []RuleRow,
    total: i64,

    pub fn free(self: *RuleListResult, allocator: std.mem.Allocator) void {
        for (self.items) |r| r.free(allocator);
        allocator.free(self.items);
    }
};

pub const RuleKeywordRow = struct {
    id: i64,
    rule_id: i64,
    keyword: []const u8,
    match_type: []const u8,

    pub fn free(self: RuleKeywordRow, allocator: std.mem.Allocator) void {
        allocator.free(self.keyword);
        allocator.free(self.match_type);
    }
};

pub const RuleReplyRow = struct {
    id: i64,
    rule_id: i64,
    reply_type: []const u8,
    content: []const u8,
    news_title: []const u8,
    news_description: []const u8,
    news_pic_url: []const u8,
    news_url: []const u8,

    pub fn free(self: RuleReplyRow, allocator: std.mem.Allocator) void {
        allocator.free(self.reply_type);
        allocator.free(self.content);
        allocator.free(self.news_title);
        allocator.free(self.news_description);
        allocator.free(self.news_pic_url);
        allocator.free(self.news_url);
    }
};

pub const RuleStore = struct {
    allocator: std.mem.Allocator,
    client: Client,

    pub fn init(allocator: std.mem.Allocator, client: Client) RuleStore {
        return .{ .allocator = allocator, .client = client };
    }

    fn dupRule(self: *RuleStore, e: anytype) !RuleRow {
        const name = try self.allocator.dupe(u8, e.name);
        errdefer self.allocator.free(name);
        const status = try self.allocator.dupe(u8, e.status);
        errdefer self.allocator.free(status);
        return .{
            .id = e.id,
            .tenant_id = e.tenant_id,
            .account_id = e.account_id,
            .name = name,
            .status = status,
            .created_at = e.created_at orelse 0,
            .updated_at = e.updated_at orelse 0,
        };
    }

    fn dupKeyword(self: *RuleStore, e: anytype) !RuleKeywordRow {
        const keyword = try self.allocator.dupe(u8, e.keyword);
        errdefer self.allocator.free(keyword);
        const match_type = try self.allocator.dupe(u8, e.match_type);
        errdefer self.allocator.free(match_type);
        return .{
            .id = e.id,
            .rule_id = e.rule_id,
            .keyword = keyword,
            .match_type = match_type,
        };
    }

    fn dupReply(self: *RuleStore, e: anytype) !RuleReplyRow {
        const reply_type = try self.allocator.dupe(u8, e.reply_type);
        errdefer self.allocator.free(reply_type);
        const content = try self.allocator.dupe(u8, e.content);
        errdefer self.allocator.free(content);
        const news_title = try self.allocator.dupe(u8, e.news_title);
        errdefer self.allocator.free(news_title);
        const news_description = try self.allocator.dupe(u8, e.news_description);
        errdefer self.allocator.free(news_description);
        const news_pic_url = try self.allocator.dupe(u8, e.news_pic_url);
        errdefer self.allocator.free(news_pic_url);
        const news_url = try self.allocator.dupe(u8, e.news_url);
        errdefer self.allocator.free(news_url);
        return .{
            .id = e.id,
            .rule_id = e.rule_id,
            .reply_type = reply_type,
            .content = content,
            .news_title = news_title,
            .news_description = news_description,
            .news_pic_url = news_pic_url,
            .news_url = news_url,
        };
    }

    // ── Rule ─────────────────────────────────────────────────────

    pub fn createRule(self: *RuleStore, tenant_id: i64, account_id: i64, name: []const u8, status: []const u8, now: i64) !i64 {
        var b = try self.client.rule.Create();
        defer b.deinit();
        _ = try b.setFieldValue("tenant_id", tenant_id);
        _ = try b.setFieldValue("account_id", account_id);
        _ = try b.setFieldValue("name", name);
        _ = try b.setFieldValue("status", status);
        _ = try b.setFieldValue("created_at", now);
        _ = try b.setFieldValue("updated_at", now);
        var row = try b.Save();
        defer zent.codegen.deinitEntity(infos, RuleInfo, &row, self.allocator);
        return row.id;
    }

    pub fn getRule(self: *RuleStore, id: i64) !?RuleRow {
        var q = self.client.rule.Query();
        defer q.deinit();
        const preds = self.client.rule.predicates;
        _ = try q.Where(.{preds.idEQ(.{ .int = id })});
        const entity_opt = try q.First();
        var entity = entity_opt orelse return null;
        defer zent.codegen.deinitEntity(infos, RuleInfo, &entity, self.allocator);
        return try self.dupRule(entity);
    }

    pub fn listRules(self: *RuleStore, page: usize, page_size: usize, tenant_id: i64, account_id: i64) !RuleListResult {
        var q = self.client.rule.Query();
        defer q.deinit();
        const preds = self.client.rule.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderAsc("id")});

        var paged = try q.paged(page, page_size);
        defer paged.deinit();

        var out = try self.allocator.alloc(RuleRow, paged.items.items.len);
        var n: usize = 0;
        errdefer {
            for (out[0..n]) |r| r.free(self.allocator);
            self.allocator.free(out);
        }
        for (paged.items.items) |e| {
            out[n] = try self.dupRule(e);
            n += 1;
        }
        return .{ .items = out, .total = paged.total };
    }

    pub fn updateRule(self: *RuleStore, id: i64, name: []const u8, status: []const u8, now: i64) !void {
        const preds = self.client.rule.predicates;
        var upd = self.client.rule.Update();
        defer upd.deinit();
        _ = try upd.set("name", .{ .string = name });
        _ = try upd.set("status", .{ .string = status });
        _ = try upd.setFieldValue("updated_at", now);
        _ = try upd.Where(.{preds.idEQ(.{ .int = id })});
        _ = try upd.Save();
    }

    pub fn deleteRule(self: *RuleStore, rule_id: i64) !void {
        {
            const preds = self.client.rule.predicates;
            var d = self.client.rule.Delete();
            defer d.deinit();
            _ = try d.Where(.{preds.idEQ(.{ .int = rule_id })});
            _ = try d.Exec();
        }
        try self.deleteKeywordsForRule(rule_id);
        try self.deleteRepliesForRule(rule_id);
    }

    // ── Keyword ───────────────────────────────────────────────────

    pub fn addKeyword(self: *RuleStore, tenant_id: i64, account_id: i64, rule_id: i64, keyword: []const u8, match_type: []const u8, now: i64) !i64 {
        var b = try self.client.rule_keyword.Create();
        defer b.deinit();
        _ = try b.setFieldValue("tenant_id", tenant_id);
        _ = try b.setFieldValue("account_id", account_id);
        _ = try b.setFieldValue("rule_id", rule_id);
        _ = try b.setFieldValue("keyword", keyword);
        _ = try b.setFieldValue("match_type", match_type);
        _ = try b.setFieldValue("created_at", now);
        var row = try b.Save();
        defer zent.codegen.deinitEntity(infos, RuleKeywordInfo, &row, self.allocator);
        return row.id;
    }

    pub fn listKeywordsForRule(self: *RuleStore, rule_id: i64) ![]RuleKeywordRow {
        var q = self.client.rule_keyword.Query();
        defer q.deinit();
        const preds = self.client.rule_keyword.predicates;
        _ = try q.Where(.{preds.rule_idEQ(.{ .int = rule_id })});
        var rows = try q.All();
        defer {
            for (rows.items) |*e| zent.codegen.deinitEntity(infos, RuleKeywordInfo, e, self.allocator);
            rows.deinit();
        }
        var out = try self.allocator.alloc(RuleKeywordRow, rows.items.len);
        errdefer self.allocator.free(out);
        var n: usize = 0;
        errdefer for (out[0..n]) |r| r.free(self.allocator);
        for (rows.items) |e| {
            out[n] = try self.dupKeyword(e);
            n += 1;
        }
        return out;
    }

    /// All keywords of an account (for in-memory keyword matching).
    pub fn listKeywordsForAccount(self: *RuleStore, tenant_id: i64, account_id: i64) ![]RuleKeywordRow {
        var q = self.client.rule_keyword.Query();
        defer q.deinit();
        const preds = self.client.rule_keyword.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderAsc("rule_id")});
        var rows = try q.All();
        defer {
            for (rows.items) |*e| zent.codegen.deinitEntity(infos, RuleKeywordInfo, e, self.allocator);
            rows.deinit();
        }
        var out = try self.allocator.alloc(RuleKeywordRow, rows.items.len);
        errdefer self.allocator.free(out);
        var n: usize = 0;
        errdefer for (out[0..n]) |r| r.free(self.allocator);
        for (rows.items) |e| {
            out[n] = try self.dupKeyword(e);
            n += 1;
        }
        return out;
    }

    pub fn removeKeyword(self: *RuleStore, id: i64) !void {
        const preds = self.client.rule_keyword.predicates;
        var d = self.client.rule_keyword.Delete();
        defer d.deinit();
        _ = try d.Where(.{preds.idEQ(.{ .int = id })});
        _ = try d.Exec();
    }

    fn deleteKeywordsForRule(self: *RuleStore, rule_id: i64) !void {
        const preds = self.client.rule_keyword.predicates;
        var d = self.client.rule_keyword.Delete();
        defer d.deinit();
        _ = try d.Where(.{preds.rule_idEQ(.{ .int = rule_id })});
        _ = try d.Exec();
    }

    // ── Reply ─────────────────────────────────────────────────────

    pub fn addReply(self: *RuleStore, tenant_id: i64, account_id: i64, rule_id: i64, reply_type: []const u8, content: []const u8, news_title: []const u8, news_description: []const u8, news_pic_url: []const u8, news_url: []const u8, now: i64) !i64 {
        var b = try self.client.rule_reply.Create();
        defer b.deinit();
        _ = try b.setFieldValue("tenant_id", tenant_id);
        _ = try b.setFieldValue("account_id", account_id);
        _ = try b.setFieldValue("rule_id", rule_id);
        _ = try b.setFieldValue("reply_type", reply_type);
        _ = try b.setFieldValue("content", content);
        _ = try b.setFieldValue("news_title", news_title);
        _ = try b.setFieldValue("news_description", news_description);
        _ = try b.setFieldValue("news_pic_url", news_pic_url);
        _ = try b.setFieldValue("news_url", news_url);
        _ = try b.setFieldValue("created_at", now);
        var row = try b.Save();
        defer zent.codegen.deinitEntity(infos, RuleReplyInfo, &row, self.allocator);
        return row.id;
    }

    pub fn listRepliesForRule(self: *RuleStore, rule_id: i64) ![]RuleReplyRow {
        var q = self.client.rule_reply.Query();
        defer q.deinit();
        const preds = self.client.rule_reply.predicates;
        _ = try q.Where(.{preds.rule_idEQ(.{ .int = rule_id })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderAsc("id")});
        var rows = try q.All();
        defer {
            for (rows.items) |*e| zent.codegen.deinitEntity(infos, RuleReplyInfo, e, self.allocator);
            rows.deinit();
        }
        var out = try self.allocator.alloc(RuleReplyRow, rows.items.len);
        errdefer self.allocator.free(out);
        var n: usize = 0;
        errdefer for (out[0..n]) |r| r.free(self.allocator);
        for (rows.items) |e| {
            out[n] = try self.dupReply(e);
            n += 1;
        }
        return out;
    }

    pub fn removeReply(self: *RuleStore, id: i64) !void {
        const preds = self.client.rule_reply.predicates;
        var d = self.client.rule_reply.Delete();
        defer d.deinit();
        _ = try d.Where(.{preds.idEQ(.{ .int = id })});
        _ = try d.Exec();
    }

    fn deleteRepliesForRule(self: *RuleStore, rule_id: i64) !void {
        const preds = self.client.rule_reply.predicates;
        var d = self.client.rule_reply.Delete();
        defer d.deinit();
        _ = try d.Where(.{preds.rule_idEQ(.{ .int = rule_id })});
        _ = try d.Exec();
    }
};
