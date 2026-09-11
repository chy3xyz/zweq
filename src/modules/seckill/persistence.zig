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
    price: []const u8,
    original_price: []const u8,
    stock: i64,
    sold: i64,
    per_user: i64,
    start_at: i64,
    end_at: i64,
    status: i64,
    created_at: i64,

    pub fn free(self: SeckillActivityRow, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
        allocator.free(self.price);
        allocator.free(self.original_price);
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
        const price = try self.allocator.dupe(u8, e.price);
        errdefer self.allocator.free(price);
        const original_price = try self.allocator.dupe(u8, e.original_price);
        errdefer self.allocator.free(original_price);
        return .{
            .id = e.id,
            .account_id = e.account_id,
            .title = title,
            .price = price,
            .original_price = original_price,
            .stock = e.stock,
            .sold = e.sold,
            .per_user = e.per_user,
            .start_at = e.start_at,
            .end_at = e.end_at,
            .status = e.status,
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

    pub fn createActivity(self: *SeckillStore, tenant_id: i64, account_id: i64, title: []const u8, price: i64, original_price: i64, stock: i64, per_user: i64, start_at: i64, end_at: i64, status: i64, now: i64) !i64 {
        const price_str = try std.fmt.allocPrint(self.allocator, "{d}", .{price});
        defer self.allocator.free(price_str);
        const original_price_str = try std.fmt.allocPrint(self.allocator, "{d}", .{original_price});
        defer self.allocator.free(original_price_str);
        var b = try self.client.seckill_activity.Create();
        defer b.deinit();
        _ = try b.setFieldValue("tenant_id", tenant_id);
        _ = try b.setFieldValue("account_id", account_id);
        _ = try b.setFieldValue("title", title);
        _ = try b.setFieldValue("price", price_str);
        _ = try b.setFieldValue("original_price", original_price_str);
        _ = try b.setFieldValue("stock", stock);
        _ = try b.setFieldValue("sold", 0);
        _ = try b.setFieldValue("per_user", per_user);
        _ = try b.setFieldValue("start_at", start_at);
        _ = try b.setFieldValue("end_at", end_at);
        // 显式写入，不依赖 DB 默认值（迁移加的列在老库上是 nullable）。
        _ = try b.setFieldValue("status", status);
        _ = try b.setFieldValue("created_at", now);
        _ = try b.setFieldValue("updated_at", now);
        var row = try b.Save();
        defer zent.codegen.deinitEntity(infos, SeckillActivityInfo, &row, self.allocator);
        return row.id;
    }

    /// 上下架：1 上架 / 0 下架。
    pub fn setActivityStatus(self: *SeckillStore, id: i64, status: i64, now: i64) !bool {
        const preds = self.client.seckill_activity.predicates;
        const affected = try crud.update(self.client.seckill_activity, .{
            .status = status,
            .updated_at = now,
        }, .{preds.idEQ(.{ .int = id })});
        return affected > 0;
    }

    /// 整体更新秒杀活动（account 作用域不变：account_id 不参与更新）。
    /// 返回受影响行数（调用方已先经 `getById` 校验存在性，0 行视为幂等成功）。
    pub fn update(self: *SeckillStore, id: i64, title: []const u8, price: i64, original_price: i64, stock: i64, per_user: i64, start_at: i64, end_at: i64, status: i64, now: i64) !usize {
        const price_str = try std.fmt.allocPrint(self.allocator, "{d}", .{price});
        defer self.allocator.free(price_str);
        const original_price_str = try std.fmt.allocPrint(self.allocator, "{d}", .{original_price});
        defer self.allocator.free(original_price_str);
        const preds = self.client.seckill_activity.predicates;
        return crud.update(self.client.seckill_activity, .{
            .title = title,
            .price = price_str,
            .original_price = original_price_str,
            .stock = stock,
            .per_user = per_user,
            .start_at = start_at,
            .end_at = end_at,
            // 显式写入，不依赖 DB 默认值（迁移加的列在老库上是 nullable）。
            .status = status,
            .updated_at = now,
        }, .{preds.idEQ(.{ .int = id })});
    }

    /// 删除秒杀活动（调用方应先删抢购记录 `deleteOrdersByActivityId`）。
    pub fn deleteById(self: *SeckillStore, id: i64) !void {
        const preds = self.client.seckill_activity.predicates;
        _ = try crud.delete(self.client.seckill_activity, .{preds.idEQ(.{ .int = id })});
    }

    /// 删除某活动全部抢购记录（删除活动前调用，避免孤儿记录）。
    pub fn deleteOrdersByActivityId(self: *SeckillStore, activity_id: i64) !void {
        const preds = self.client.seckill_order.predicates;
        _ = try crud.delete(self.client.seckill_order, .{preds.activity_idEQ(.{ .int = activity_id })});
    }

    /// 按 id 取单条（tenant 过滤），供 C 端 rush 读取活动：跨租户活动不可见
    /// （效果同 NotFound），杜绝越权抢别租户活动。
    pub fn getActivity(self: *SeckillStore, tenant_id: i64, id: i64) !?SeckillActivityRow {
        const preds = self.client.seckill_activity.predicates;
        var entity = (try crud.first(self.client.seckill_activity, .{ preds.tenant_idEQ(.{ .int = tenant_id }), preds.idEQ(.{ .int = id }) })) orelse return null;
        defer zent.codegen.deinitEntity(infos, SeckillActivityInfo, &entity, self.allocator);
        return try self.dupActivity(entity);
    }

    /// 按 id 取单条（tenant 过滤），供 service 校验存在性与管理端详情读取/标题富化。
    pub fn getById(self: *SeckillStore, tenant_id: i64, id: i64) !?SeckillActivityRow {
        const preds = self.client.seckill_activity.predicates;
        var entity = (try crud.first(self.client.seckill_activity, .{ preds.tenant_idEQ(.{ .int = tenant_id }), preds.idEQ(.{ .int = id }) })) orelse return null;
        defer zent.codegen.deinitEntity(infos, SeckillActivityInfo, &entity, self.allocator);
        return try self.dupActivity(entity);
    }

    /// 该账号最新一个活动（receiver 用）。
    /// 最新活动（C 端公众号关键词回复用）：只取上架的。
    pub fn latestActivity(self: *SeckillStore, tenant_id: i64, account_id: i64) !?SeckillActivityRow {
        var q = self.client.seckill_activity.Query();
        defer q.deinit();
        const preds = self.client.seckill_activity.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.Where(.{preds.statusEQ(.{ .int = 1 })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderDesc("created_at")});
        _ = q.Limit(1);
        const entity_opt = try q.First();
        var entity = entity_opt orelse return null;
        defer zent.codegen.deinitEntity(infos, SeckillActivityInfo, &entity, self.allocator);
        return try self.dupActivity(entity);
    }

    /// `status` 为 -1 表示不过滤；0 下架 / 1 上架（C 端固定传 1）。
    pub fn listActivities(self: *SeckillStore, page: usize, page_size: usize, tenant_id: i64, account_id: i64, keyword: []const u8, status: i64) !SeckillListResult {
        var q = self.client.seckill_activity.Query();
        defer q.deinit();
        const preds = self.client.seckill_activity.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        if (keyword.len > 0) _ = try q.Where(.{preds.titleContainsEscaped(keyword)});
        if (status >= 0) _ = try q.Where(.{preds.statusEQ(.{ .int = status })});
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

    /// `openid` 为精确匹配；`keyword` 为 openid 模糊匹配（管理端搜索用）。
    pub fn listOrders(self: *SeckillStore, page: usize, page_size: usize, tenant_id: i64, account_id: i64, openid: []const u8, keyword: []const u8) !SeckillOrderListResult {
        var q = self.client.seckill_order.Query();
        defer q.deinit();
        const preds = self.client.seckill_order.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        if (openid.len > 0) {
            _ = try q.Where(.{preds.openidEQ(.{ .string = openid })});
        }
        if (keyword.len > 0) _ = try q.Where(.{preds.openidContainsEscaped(keyword)});
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

    /// 库存回补：下单失败/限购复核失败时回滚已扣库存（`sold -= n`，increment 反操作）。
    /// 失败必须上抛给调用方记日志——静默吞错会造成库存永久流失。
    pub fn restoreStock(self: *SeckillStore, activity_id: i64, n: i64) !void {
        const preds = self.client.seckill_activity.predicates;
        _ = try crud.increment(self.client.seckill_activity, "sold", -n, &.{preds.idEQ(.{ .int = activity_id })});
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
