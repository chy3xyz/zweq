//! Member service — WeChat fans. No HTTP/SQL leakage.

const std = @import("std");
const zigmodu = @import("zigmodu");
const persist = @import("persistence.zig");

pub const FanRow = persist.FanRow;
pub const FanListResult = persist.FanListResult;

pub const MemberError = error{
    InvalidOpenid,
    NotFound,
    Unexpected,
};

pub const MemberService = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    store: *persist.FanStore,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, store: *persist.FanStore) MemberService {
        return .{ .allocator = allocator, .io = io, .store = store };
    }

    fn now(self: *MemberService) i64 {
        return zigmodu.time.wallClockSeconds(self.io);
    }

    /// Record a 关注 event (upsert fan). Returns the fan id.
    pub fn onSubscribe(self: *MemberService, tenant_id: i64, account_id: i64, openid: []const u8, unionid: []const u8) MemberError!i64 {
        if (openid.len == 0) return error.InvalidOpenid;
        return self.store.upsert(tenant_id, account_id, openid, unionid, "", "", true, self.now(), self.now()) catch error.Unexpected;
    }

    /// Record a 取关 event.
    pub fn onUnsubscribe(self: *MemberService, tenant_id: i64, account_id: i64, openid: []const u8) !void {
        if (openid.len == 0) return error.InvalidOpenid;
        const row_opt = self.store.getByOpenid(tenant_id, account_id, openid) catch return error.Unexpected;
        if (row_opt) |row| {
            defer row.free(self.allocator);
            const preds = self.store.client.fan.predicates;
            var upd = self.store.client.fan.Update();
            defer upd.deinit();
            _ = try upd.set("subscribed", .{ .bool = false });
            _ = try upd.setFieldValue("updated_at", self.now());
            _ = try upd.Where(.{preds.idEQ(.{ .int = row.id })});
            _ = try upd.Save();
            return;
        }
    }

    pub fn get(self: *MemberService, id: i64) MemberError!?FanRow {
        return self.store.getById(id) catch error.Unexpected;
    }

    pub fn list(self: *MemberService, page: usize, page_size: usize, tenant_id: i64, account_id: i64, keyword: ?[]const u8, subscribed_only: bool) MemberError!FanListResult {
        return self.store.list(page, page_size, tenant_id, account_id, keyword, subscribed_only) catch error.Unexpected;
    }
};
