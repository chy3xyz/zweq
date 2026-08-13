//! Persistence over the zent Client — 积分商品 + 兑换记录。

const std = @import("std");
const zent = @import("zent");
const model = @import("model.zig");
const schema = @import("../../schema.zig");

const graph = zent.codegen.graph.buildGraph(&.{ model.PointsProduct, model.PointsOrder });
pub const infos = graph.types;
/// Shared, application-wide typed client (all schemas registered in schema.zig).
pub const Client = schema.Client;
pub const PointsProductInfo = infos[0];
pub const PointsOrderInfo = infos[1];

pub const PointsProductRow = struct {
    id: i64,
    tenant_id: i64,
    account_id: i64,
    name: []const u8,
    points: i64,
    stock: i64,

    pub fn free(self: PointsProductRow, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }
};

pub const PointsOrderRow = struct {
    id: i64,
    tenant_id: i64,
    account_id: i64,
    openid: []const u8,
    product_id: i64,
    product_name: []const u8,
    points_spent: i64,
    status: []const u8,

    pub fn free(self: PointsOrderRow, allocator: std.mem.Allocator) void {
        allocator.free(self.openid);
        allocator.free(self.product_name);
        allocator.free(self.status);
    }
};

pub const ProductListResult = struct {
    items: []PointsProductRow,
    total: i64,

    pub fn free(self: *ProductListResult, allocator: std.mem.Allocator) void {
        for (self.items) |r| r.free(allocator);
        allocator.free(self.items);
    }
};

/// 商品 + 兑换记录存储（同一 Client）。
pub const PointsStore = struct {
    allocator: std.mem.Allocator,
    client: Client,

    pub fn init(allocator: std.mem.Allocator, client: Client) PointsStore {
        return .{ .allocator = allocator, .client = client };
    }

    fn dupProduct(self: *PointsStore, e: anytype) !PointsProductRow {
        const name = try self.allocator.dupe(u8, e.name);
        errdefer self.allocator.free(name);
        return .{
            .id = e.id,
            .tenant_id = e.tenant_id,
            .account_id = e.account_id,
            .name = name,
            .points = e.points,
            .stock = e.stock,
        };
    }

    fn dupOrder(self: *PointsStore, e: anytype) !PointsOrderRow {
        const openid = try self.allocator.dupe(u8, e.openid);
        errdefer self.allocator.free(openid);
        const product_name = try self.allocator.dupe(u8, e.product_name);
        errdefer self.allocator.free(product_name);
        const status = try self.allocator.dupe(u8, e.status);
        errdefer self.allocator.free(status);
        return .{
            .id = e.id,
            .tenant_id = e.tenant_id,
            .account_id = e.account_id,
            .openid = openid,
            .product_id = e.product_id,
            .product_name = product_name,
            .points_spent = e.points_spent,
            .status = status,
        };
    }

    // ── 商品 ─────────────────────────────────────────────────────

    pub fn createProduct(self: *PointsStore, tenant_id: i64, account_id: i64, name: []const u8, points: i64, stock: i64, now: i64) !i64 {
        var b = try self.client.points_product.Create();
        defer b.deinit();
        _ = try b.setFieldValue("tenant_id", tenant_id);
        _ = try b.setFieldValue("account_id", account_id);
        _ = try b.setFieldValue("name", name);
        _ = try b.setFieldValue("points", points);
        _ = try b.setFieldValue("stock", stock);
        _ = try b.setFieldValue("created_at", now);
        _ = try b.setFieldValue("updated_at", now);
        var row = try b.Save();
        defer zent.codegen.deinitEntity(infos, PointsProductInfo, &row, self.allocator);
        return row.id;
    }

    pub fn getProduct(self: *PointsStore, id: i64) !?PointsProductRow {
        const preds = self.client.points_product.predicates;
        var q = self.client.points_product.Query();
        defer q.deinit();
        _ = try q.Where(.{preds.idEQ(.{ .int = id })});
        var entity = (try q.First()) orelse return null;
        defer zent.codegen.deinitEntity(infos, PointsProductInfo, &entity, self.allocator);
        return try self.dupProduct(entity);
    }

    pub fn listProducts(self: *PointsStore, page: usize, page_size: usize, tenant_id: i64, account_id: i64) !ProductListResult {
        var q = self.client.points_product.Query();
        defer q.deinit();
        const preds = self.client.points_product.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderDesc("id")});
        var paged = try q.paged(page, page_size);
        defer paged.deinit();
        var out = try self.allocator.alloc(PointsProductRow, paged.items.items.len);
        var n: usize = 0;
        errdefer {
            for (out[0..n]) |r| r.free(self.allocator);
            self.allocator.free(out);
        }
        for (paged.items.items) |e| {
            out[n] = try self.dupProduct(e);
            n += 1;
        }
        return .{ .items = out, .total = paged.total };
    }

    pub fn updateProduct(self: *PointsStore, id: i64, name: []const u8, points: i64, stock: i64, now: i64) !void {
        const preds = self.client.points_product.predicates;
        var upd = self.client.points_product.Update();
        defer upd.deinit();
        _ = try upd.set("name", .{ .string = name });
        _ = try upd.setFieldValue("points", points);
        _ = try upd.setFieldValue("stock", stock);
        _ = try upd.setFieldValue("updated_at", now);
        _ = try upd.Where(.{preds.idEQ(.{ .int = id })});
        _ = try upd.Save();
    }

    /// 减库存（兑换用）。返回剩余库存。
    pub fn decrementStock(self: *PointsStore, id: i64, amount: i64, now: i64) !i64 {
        const row_opt = try self.getProduct(id);
        const row = row_opt orelse return error.ProductNotFound;
        defer row.free(self.allocator);
        const new_stock = row.stock - amount;
        if (new_stock < 0) return error.OutOfStock;
        const preds = self.client.points_product.predicates;
        var upd = self.client.points_product.Update();
        defer upd.deinit();
        _ = try upd.setFieldValue("stock", new_stock);
        _ = try upd.setFieldValue("updated_at", now);
        _ = try upd.Where(.{preds.idEQ(.{ .int = id })});
        _ = try upd.Save();
        return new_stock;
    }

    pub fn deleteProduct(self: *PointsStore, id: i64) !void {
        const preds = self.client.points_product.predicates;
        var d = self.client.points_product.Delete();
        defer d.deinit();
        _ = try d.Where(.{preds.idEQ(.{ .int = id })});
        _ = try d.Exec();
    }

    // ── 兑换记录 ─────────────────────────────────────────────────

    pub fn createOrder(self: *PointsStore, tenant_id: i64, account_id: i64, openid: []const u8, product_id: i64, product_name: []const u8, points_spent: i64, now: i64) !i64 {
        var b = try self.client.points_order.Create();
        defer b.deinit();
        _ = try b.setFieldValue("tenant_id", tenant_id);
        _ = try b.setFieldValue("account_id", account_id);
        _ = try b.setFieldValue("openid", openid);
        _ = try b.setFieldValue("product_id", product_id);
        _ = try b.setFieldValue("product_name", product_name);
        _ = try b.setFieldValue("points_spent", points_spent);
        _ = try b.setFieldValue("status", "completed");
        _ = try b.setFieldValue("created_at", now);
        _ = try b.setFieldValue("updated_at", now);
        var row = try b.Save();
        defer zent.codegen.deinitEntity(infos, PointsOrderInfo, &row, self.allocator);
        return row.id;
    }

    pub fn listOrders(self: *PointsStore, tenant_id: i64, account_id: i64, openid: ?[]const u8) ![]PointsOrderRow {
        var q = self.client.points_order.Query();
        defer q.deinit();
        const preds = self.client.points_order.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        if (openid) |oid| {
            if (oid.len > 0) _ = try q.Where(.{preds.openidEQ(.{ .string = oid })});
        }
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderDesc("id")});
        var rows = try q.All();
        defer {
            for (rows.items) |*e| zent.codegen.deinitEntity(infos, PointsOrderInfo, e, self.allocator);
            rows.deinit();
        }
        var out = try self.allocator.alloc(PointsOrderRow, rows.items.len);
        errdefer self.allocator.free(out);
        var n: usize = 0;
        errdefer for (out[0..n]) |r| r.free(self.allocator);
        for (rows.items) |e| {
            out[n] = try self.dupOrder(e);
            n += 1;
        }
        return out;
    }
};
