//! Persistence over the zent Client — 公众号自定义菜单。

const std = @import("std");
const zent = @import("zent");
const crud = zent.crud_helpers;
const model = @import("model.zig");
const schema = @import("../../schema.zig");

const graph = zent.codegen.graph.buildGraph(&.{ model.WechatMenu });
pub const infos = graph.types;
/// Shared, application-wide typed client (all schemas registered in schema.zig).
pub const Client = schema.Client;
pub const WechatMenuInfo = infos[0];

pub const MenuRow = struct {
    id: i64,
    tenant_id: i64,
    account_id: i64,
    menu_json: []const u8,
    updated_at: i64,

    pub fn free(self: MenuRow, allocator: std.mem.Allocator) void {
        allocator.free(self.menu_json);
    }
};

pub const MenuStore = struct {
    allocator: std.mem.Allocator,
    client: Client,

    pub fn init(allocator: std.mem.Allocator, client: Client) MenuStore {
        return .{ .allocator = allocator, .client = client };
    }

    fn dup(self: *MenuStore, e: anytype) !MenuRow {
        const menu_json = try self.allocator.dupe(u8, e.menu_json);
        errdefer self.allocator.free(menu_json);
        return .{
            .id = e.id,
            .tenant_id = e.tenant_id,
            .account_id = e.account_id,
            .menu_json = menu_json,
            .updated_at = e.updated_at orelse 0,
        };
    }

    pub fn getByAccount(self: *MenuStore, tenant_id: i64, account_id: i64) !?MenuRow {
        const preds = self.client.wechat_menu.predicates;
        var entity = (try crud.first(self.client.wechat_menu, .{
            preds.tenant_idEQ(.{ .int = tenant_id }),
            preds.account_idEQ(.{ .int = account_id }),
        })) orelse return null;
        defer zent.codegen.deinitEntity(infos, WechatMenuInfo, &entity, self.allocator);
        return try self.dup(entity);
    }

    /// Upsert the menu JSON for an account. Returns the row id.
    pub fn upsert(self: *MenuStore, tenant_id: i64, account_id: i64, menu_json: []const u8, now: i64) !i64 {
        if (try self.getByAccount(tenant_id, account_id)) |row| {
            defer row.free(self.allocator);
            const preds = self.client.wechat_menu.predicates;
            _ = try crud.update(self.client.wechat_menu, .{
                .menu_json = menu_json,
                .updated_at = now,
            }, .{preds.idEQ(.{ .int = row.id })});
            return row.id;
        }
        var row = try crud.create(self.client.wechat_menu, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .menu_json = menu_json,
            .created_at = now,
            .updated_at = now,
        });
        defer zent.codegen.deinitEntity(infos, WechatMenuInfo, &row, self.allocator);
        return row.id;
    }
};
