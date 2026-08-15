//! Persistence over the zent Client — 秒杀活动 + 抢购记录（原子库存扣减）。

const std = @import("std");
const zent = @import("zent");
const crud = zent.crud_helpers;
const model = @import("model.zig");
const schema = @import("../../schema.zig");

const graph = zent.codegen.graph.buildGraph(&.{ model.SeckillActivity, model.SeckillOrder });
pub const infos = graph.types;
pub const Client = schema.Client;
pub const SeckillActivityInfo = infos[0];
pub const SeckillOrderInfo = infos[1];

pub const SeckillActivityRow = struct {
    id: i64,
    account_id: i64,
    title: []const u8,
    price: i64,
    original_price: i64,
    stock: i64,
    sold: i64,
    per_user: i64,
    start_at: i64,
    end_at: i64,
    created_at: i64,

    pub fn free(self: SeckillActivityRow, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
    }
};

pub const SeckillListResult = struct {
    items: []SeckillActivityRow,
    total: i64,

    pub fn free(self: *SeckillListResult, allocator: std.mem.Allocator) void {
        for (self.items) |r| r.free(allocator);
        allocator.free(self.items);
    }
};

pub const SeckillOrderRow = struct {
    id: i64,
    account_id: i64,
    openid: []const u8,
    activity_id: i64,
    quantity: i64,
    created_at: i64,

    pub fn free(self: SeckillOrderRow, allocator: std.mem.Allocator) void {
        allocator.free(self.openid);
    }
};

pub const SeckillOrderListResult = struct {
    items: []SeckillOrderRow,
    total: i64,

    pub fn free(self: *SeckillOrderListResult, allocator: std.mem.Allocator) void {
        for (self.items) |r| r.free(allocator);
        allocator.free(self.items);
    }
};

pub const SeckillStore = struct {
    allocator: std.mem.Allocator,
    client: Client,

    pub fn init(allocator: std.mem.Allocator, client: Client) SeckillStore {
        return .{ .allocator = allocator, .client = client };
    }

    fn dupActivity(self: *SeckillStore, e: anytype) !SeckillActivityRow {
        const title = try self.allocator.dupe(u8, e.title);
        errdefer self.allocator.free(title);
        return .{
            .id = e.id,
            .account_id = e.account_id,
            .title = title,
            .price = e.price,
            .original_price = e.original_price,
            .stock = e.stock,
            .sold = e.sold,
            .per_user = e.per_user,
            .start_at = e.start_at,
            .end_at = e.end_at,
            .created_at = e.created_at orelse 0,
        };
    }

    fn dupOrder(self: *SeckillStore, e: anytype) !SeckillOrderRow {
        const openid = try self.allocator.dupe(u8, e.openid);
        errdefer self.allocator.free(openid);
        return .{
            .id = e.id,
            .account_id = e.account_id,
            .openid = openid,
            .activity_id = e.activity_id,
            .quantity = e.quantity,
            .created_at = e.created_at orelse 0,
        };
    }

    pub fn createActivity(self: *SeckillStore, tenant_id: i64, account_id: i64, title: []const u8, price: i64, original_price: i64, stock: i64, per_user: i64, start_at: i64, end_at: i64, now: i64) !i64 {
        var row = try crud.create(self.client.seckill_activity, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .title = title,
            .price = price,
            .original_price = original_price,
            .stock = stock,
            .sold = 0,
            .per_user = per_user,
            .start_at = start_at,
            .end_at = end_at,
            .created_at = now,
            .updated_at = now,
        });
        defer zent.codegen.deinitEntity(infos, SeckillActivityInfo, &row, self.allocator);
        return row.id;
    }

    pub fn getActivity(self: *SeckillStore, id: i64) !?SeckillActivityRow {
        const preds = self.client.seckill_activity.predicates;
        var entity = (try crud.first(self.client.seckill_activity, .{preds.idEQ(.{ .int = id })})) orelse return null;
        defer zent.codegen.deinitEntity(infos, SeckillActivityInfo, &entity, self.allocator);
        return try self.dupActivity(entity);
    }

    /// 该账号最新一个活动（receiver 用）。
    pub fn latestActivity(self: *SeckillStore, tenant_id: i64, account_id: i64) !?SeckillActivityRow {
        var q = self.client.seckill_activity.Query();
        defer q.deinit();
        const preds = self.client.seckill_activity.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderDesc("created_at")});
        _ = q.Limit(1);
        const entity_opt = try q.First();
        var entity = entity_opt orelse return null;
        defer zent.codegen.deinitEntity(infos, SeckillActivityInfo, &entity, self.allocator);
        return try self.dupActivity(entity);
    }

    pub fn listActivities(self: *SeckillStore, page: usize, page_size: usize, tenant_id: i64, account_id: i64) !SeckillListResult {
        var q = self.client.seckill_activity.Query();
        defer q.deinit();
        const preds = self.client.seckill_activity.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderDesc("created_at")});
        var paged = try q.paged(page, page_size);
        defer paged.deinit();
        var out = try self.allocator.alloc(SeckillActivityRow, paged.items.items.len);
        var n: usize = 0;
        errdefer {
            for (out[0..n]) |r| r.free(self.allocator);
            self.allocator.free(out);
        }
        for (paged.items.items) |e| {
            out[n] = try self.dupActivity(e);
            n += 1;
        }
        return .{ .items = out, .total = paged.total };
    }

    pub fn listOrders(self: *SeckillStore, page: usize, page_size: usize, tenant_id: i64, account_id: i64) !SeckillOrderListResult {
        var q = self.client.seckill_order.Query();
        defer q.deinit();
        const preds = self.client.seckill_order.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderDesc("created_at")});
        var paged = try q.paged(page, page_size);
        defer paged.deinit();
        var out = try self.allocator.alloc(SeckillOrderRow, paged.items.items.len);
        var n: usize = 0;
        errdefer {
            for (out[0..n]) |r| r.free(self.allocator);
            self.allocator.free(out);
        }
        for (paged.items.items) |e| {
            out[n] = try self.dupOrder(e);
            n += 1;
        }
        return .{ .items = out, .total = paged.total };
    }

    /// 该 openid 已抢数量（限购校验）。
    pub fn countOrdered(self: *SeckillStore, tenant_id: i64, activity_id: i64, openid: []const u8) !i64 {
        var q = self.client.seckill_order.Query();
        defer q.deinit();
        const preds = self.client.seckill_order.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.activity_idEQ(.{ .int = activity_id })});
        _ = try q.Where(.{preds.openidEQ(.{ .string = openid })});
        _ = q.Limit(1);
        return q.Count();
    }

    /// 原子扣库存：`sold = sold + n WHERE id=? AND sold + n <= stock`（乐观锁防超卖）。
    /// 返回是否扣减成功（库存不足返回 false）。
    pub fn tryConsumeStock(self: *SeckillStore, allocator: std.mem.Allocator, activity_id: i64, n: i64) !bool {
        const preds = self.client.seckill_activity.predicates;
        const guard = try std.fmt.allocPrint(allocator, "sold + {d} <= stock", .{n});
        defer allocator.free(guard);
        const affected = crud.increment(self.client.seckill_activity, "sold", n, &.{
            preds.idEQ(.{ .int = activity_id }),
            zent.sql.Predicate{ .raw = guard },
        }) catch return false;
        return affected > 0;
    }

    pub fn createOrder(self: *SeckillStore, tenant_id: i64, account_id: i64, openid: []const u8, activity_id: i64, quantity: i64, now: i64) !i64 {
        var row = try crud.create(self.client.seckill_order, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .openid = openid,
            .activity_id = activity_id,
            .quantity = quantity,
            .created_at = now,
            .updated_at = now,
        });
        defer zent.codegen.deinitEntity(infos, SeckillOrderInfo, &row, self.allocator);
        return row.id;
    }
};
