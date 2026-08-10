//! Persistence over the zent Client — WeChat server callback logs.

const std = @import("std");
const zent = @import("zent");
const model = @import("model.zig");
const schema = @import("../../schema.zig");

const graph = zent.codegen.graph.buildGraph(&.{model.MessageLog});
pub const infos = graph.types;
/// Shared, application-wide typed client (all schemas registered in schema.zig).
pub const Client = schema.Client;
pub const MessageLogInfo = infos[0];

pub const MessageLogRow = struct {
    id: i64,
    tenant_id: i64,
    account_id: i64,
    msg_id: []const u8,
    openid: []const u8,
    msg_type: []const u8,
    event: []const u8,
    content: []const u8,
    reply_type: []const u8,
    reply_content: []const u8,
    created_at: i64,

    pub fn free(self: MessageLogRow, allocator: std.mem.Allocator) void {
        allocator.free(self.msg_id);
        allocator.free(self.openid);
        allocator.free(self.msg_type);
        allocator.free(self.event);
        allocator.free(self.content);
        allocator.free(self.reply_type);
        allocator.free(self.reply_content);
    }
};

pub const MessageLogListResult = struct {
    items: []MessageLogRow,
    total: i64,

    pub fn free(self: *MessageLogListResult, allocator: std.mem.Allocator) void {
        for (self.items) |r| r.free(allocator);
        allocator.free(self.items);
    }
};

pub const MessageStore = struct {
    allocator: std.mem.Allocator,
    client: Client,

    pub fn init(allocator: std.mem.Allocator, client: Client) MessageStore {
        return .{ .allocator = allocator, .client = client };
    }

    fn dup(self: *MessageStore, e: anytype) !MessageLogRow {
        const msg_id = try self.allocator.dupe(u8, e.msg_id);
        errdefer self.allocator.free(msg_id);
        const openid = try self.allocator.dupe(u8, e.openid);
        errdefer self.allocator.free(openid);
        const msg_type = try self.allocator.dupe(u8, e.msg_type);
        errdefer self.allocator.free(msg_type);
        const event = try self.allocator.dupe(u8, e.event);
        errdefer self.allocator.free(event);
        const content = try self.allocator.dupe(u8, e.content);
        errdefer self.allocator.free(content);
        const reply_type = try self.allocator.dupe(u8, e.reply_type);
        errdefer self.allocator.free(reply_type);
        const reply_content = try self.allocator.dupe(u8, e.reply_content);
        errdefer self.allocator.free(reply_content);
        return .{
            .id = e.id,
            .tenant_id = e.tenant_id,
            .account_id = e.account_id,
            .msg_id = msg_id,
            .openid = openid,
            .msg_type = msg_type,
            .event = event,
            .content = content,
            .reply_type = reply_type,
            .reply_content = reply_content,
            .created_at = e.created_at orelse 0,
        };
    }

    pub fn create(self: *MessageStore, tenant_id: i64, account_id: i64, msg_id: []const u8, openid: []const u8, msg_type: []const u8, event: []const u8, content: []const u8, reply_type: []const u8, reply_content: []const u8, now: i64) !i64 {
        var b = try self.client.message_log.Create();
        defer b.deinit();
        _ = try b.setFieldValue("tenant_id", tenant_id);
        _ = try b.setFieldValue("account_id", account_id);
        _ = try b.setFieldValue("msg_id", msg_id);
        _ = try b.setFieldValue("openid", openid);
        _ = try b.setFieldValue("msg_type", msg_type);
        _ = try b.setFieldValue("event", event);
        _ = try b.setFieldValue("content", content);
        _ = try b.setFieldValue("reply_type", reply_type);
        _ = try b.setFieldValue("reply_content", reply_content);
        _ = try b.setFieldValue("created_at", now);
        var row = try b.Save();
        defer zent.codegen.deinitEntity(infos, MessageLogInfo, &row, self.allocator);
        return row.id;
    }

    pub fn list(self: *MessageStore, page: usize, page_size: usize, tenant_id: i64, account_id: i64) !MessageLogListResult {
        var q = self.client.message_log.Query();
        defer q.deinit();
        const preds = self.client.message_log.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderDesc("id")});

        var paged = try q.paged(page, page_size);
        defer paged.deinit();

        var out = try self.allocator.alloc(MessageLogRow, paged.items.items.len);
        var n: usize = 0;
        errdefer {
            for (out[0..n]) |r| r.free(self.allocator);
            self.allocator.free(out);
        }
        for (paged.items.items) |e| {
            out[n] = try self.dup(e);
            n += 1;
        }
        return .{ .items = out, .total = paged.total };
    }
};
