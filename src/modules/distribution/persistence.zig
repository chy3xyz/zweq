//! Persistence over the zent Client — 分销员 + 佣金记录。

const std = @import("std");
const zent = @import("zent");
const crud = zent.crud_helpers;
const model = @import("model.zig");
const schema = @import("../../schema.zig");

const graph = zent.codegen.graph.buildGraph(&.{ model.Distributor, model.CommissionRecord });
pub const infos = graph.types;
pub const Client = schema.Client;
pub const DistributorInfo = infos[0];
pub const CommissionRecordInfo = infos[1];

pub const DistributorRow = struct {
    id: i64,
    account_id: i64,
    openid: []const u8,
    parent_openid: []const u8,
    commission_balance: []const u8,
    total_commission: []const u8,
    status: i64,
    created_at: i64,

    pub fn free(self: DistributorRow, allocator: std.mem.Allocator) void {
        allocator.free(self.openid);
        allocator.free(self.parent_openid);
        allocator.free(self.commission_balance);
        allocator.free(self.total_commission);
    }
};

pub const CommissionRow = struct {
    id: i64,
    account_id: i64,
    openid: []const u8,
    source_openid: []const u8,
    level: i64,
    amount: []const u8,
    status: i64,
    created_at: i64,

    pub fn free(self: CommissionRow, allocator: std.mem.Allocator) void {
        allocator.free(self.openid);
        allocator.free(self.source_openid);
        allocator.free(self.amount);
    }
};

pub const DistributorListResult = struct {
    items: []DistributorRow,
    total: i64,

    pub fn free(self: *DistributorListResult, allocator: std.mem.Allocator) void {
        for (self.items) |r| r.free(allocator);
        allocator.free(self.items);
    }
};

pub const CommissionListResult = struct {
    items: []CommissionRow,
    total: i64,

    pub fn free(self: *CommissionListResult, allocator: std.mem.Allocator) void {
        for (self.items) |r| r.free(allocator);
        allocator.free(self.items);
    }
};

pub const DistributionStore = struct {
    allocator: std.mem.Allocator,
    client: Client,

    pub fn init(allocator: std.mem.Allocator, client: Client) DistributionStore {
        return .{ .allocator = allocator, .client = client };
    }

    fn dupDistributor(self: *DistributionStore, e: anytype) !DistributorRow {
        const openid = try self.allocator.dupe(u8, e.openid);
        errdefer self.allocator.free(openid);
        const parent = try self.allocator.dupe(u8, e.parent_openid);
        errdefer self.allocator.free(parent);
        const commission_balance = try self.allocator.dupe(u8, e.commission_balance);
        errdefer self.allocator.free(commission_balance);
        const total_commission = try self.allocator.dupe(u8, e.total_commission);
        errdefer self.allocator.free(total_commission);
        return .{
            .id = e.id,
            .account_id = e.account_id,
            .openid = openid,
            .parent_openid = parent,
            .commission_balance = commission_balance,
            .total_commission = total_commission,
            .status = e.status,
            .created_at = e.created_at orelse 0,
        };
    }

    fn dupCommission(self: *DistributionStore, e: anytype) !CommissionRow {
        const openid = try self.allocator.dupe(u8, e.openid);
        errdefer self.allocator.free(openid);
        const source = try self.allocator.dupe(u8, e.source_openid);
        errdefer self.allocator.free(source);
        const amount = try self.allocator.dupe(u8, e.amount);
        errdefer self.allocator.free(amount);
        return .{
            .id = e.id,
            .account_id = e.account_id,
            .openid = openid,
            .source_openid = source,
            .level = e.level,
            .amount = amount,
            .status = e.status,
            .created_at = e.created_at orelse 0,
        };
    }

    pub fn getByOpenid(self: *DistributionStore, tenant_id: i64, account_id: i64, openid: []const u8) !?DistributorRow {
        var q = self.client.distributor.Query();
        defer q.deinit();
        const preds = self.client.distributor.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.Where(.{preds.openidEQ(.{ .string = openid })});
        const entity_opt = try q.First();
        var entity = entity_opt orelse return null;
        defer self.client.distributor.deinitRow(&entity);
        return try self.dupDistributor(entity);
    }

    pub fn createDistributor(self: *DistributionStore, tenant_id: i64, account_id: i64, openid: []const u8, parent_openid: []const u8, now: i64) !i64 {
        var row = try crud.create(self.client.distributor, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .openid = openid,
            .parent_openid = parent_openid,
            .commission_balance = "0",
            .total_commission = "0",
            .status = 1,
            .created_at = now,
            .updated_at = now,
        });
        defer self.client.distributor.deinitRow(&row);
        return row.id;
    }

    /// 原子佣金入账：commission_balance += amount, total_commission += amount。
    pub fn addCommission(self: *DistributionStore, allocator: std.mem.Allocator, distributor_id: i64, amount: i64) !bool {
        _ = allocator;
        const amount_str = try std.fmt.allocPrint(self.allocator, "{d}", .{amount});
        defer self.allocator.free(amount_str);
        const preds = self.client.distributor.predicates;
        var upd = self.client.distributor.Update();
        defer upd.deinit();
        _ = try upd.setExprArgs("commission_balance", "commission_balance + ?", &.{.{ .string = amount_str }});
        _ = try upd.Where(.{preds.idEQ(.{ .int = distributor_id })});
        _ = try upd.Save();
        var upd2 = self.client.distributor.Update();
        defer upd2.deinit();
        _ = try upd2.setExprArgs("total_commission", "total_commission + ?", &.{.{ .string = amount_str }});
        _ = try upd2.Where(.{preds.idEQ(.{ .int = distributor_id })});
        _ = upd2.Save() catch {};
        return true;
    }

    /// 原子佣金扣减（提现）：commission_balance -= amount，余额不足返回 false。
    pub fn deductCommission(self: *DistributionStore, allocator: std.mem.Allocator, distributor_id: i64, amount: i64) !bool {
        const amount_str = try std.fmt.allocPrint(allocator, "{d}", .{amount});
        defer allocator.free(amount_str);
        const preds = self.client.distributor.predicates;
        const guard = try std.fmt.allocPrint(allocator, "CAST(commission_balance AS INTEGER) >= {d}", .{amount});
        defer allocator.free(guard);
        var upd = self.client.distributor.Update();
        defer upd.deinit();
        _ = try upd.setExprArgs("commission_balance", "commission_balance - ?", &.{.{ .string = amount_str }});
        _ = try upd.Where(.{ preds.idEQ(.{ .int = distributor_id }), zent.sql.Predicate{ .raw = guard } });
        const affected = try upd.Save();
        return affected > 0;
    }

    pub fn createCommission(self: *DistributionStore, tenant_id: i64, account_id: i64, openid: []const u8, source_openid: []const u8, level: i64, amount: i64, now: i64) !i64 {
        const amount_str = try std.fmt.allocPrint(self.allocator, "{d}", .{amount});
        defer self.allocator.free(amount_str);
        var row = try crud.create(self.client.commission_record, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .openid = openid,
            .source_openid = source_openid,
            .level = level,
            .amount = amount_str,
            .status = 1,
            .created_at = now,
            .updated_at = now,
        });
        defer self.client.commission_record.deinitRow(&row);
        return row.id;
    }

    /// `keyword` 匹配分销员 openid；`status` 为 -1 表示不过滤（1=启用）。
    pub fn listDistributors(self: *DistributionStore, page: usize, page_size: usize, tenant_id: i64, account_id: i64, keyword: []const u8, status: i64) !DistributorListResult {
        var q = self.client.distributor.Query();
        defer q.deinit();
        const preds = self.client.distributor.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        if (keyword.len > 0) _ = try q.Where(.{preds.openidContainsEscaped(keyword)});
        if (status >= 0) _ = try q.Where(.{preds.statusEQ(.{ .int = status })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderDesc("created_at")});
        var paged = try q.paged(page, page_size);
        defer paged.deinit();
        var out = try self.allocator.alloc(DistributorRow, paged.items.items.len);
        var n: usize = 0;
        errdefer {
            for (out[0..n]) |r| r.free(self.allocator);
            self.allocator.free(out);
        }
        for (paged.items.items) |e| {
            out[n] = try self.dupDistributor(e);
            n += 1;
        }
        return .{ .items = out, .total = paged.total };
    }

    /// `keyword` 同时匹配受益分销员与购买者 openid；`level` 为 -1 表示不过滤。
    pub fn listCommissions(self: *DistributionStore, page: usize, page_size: usize, tenant_id: i64, account_id: i64, keyword: []const u8, level: i64) !CommissionListResult {
        var q = self.client.commission_record.Query();
        defer q.deinit();
        const preds = self.client.commission_record.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        if (keyword.len > 0) {
            const p1 = preds.openidContainsEscaped(keyword);
            const p2 = preds.source_openidContainsEscaped(keyword);
            _ = try q.Where(.{zent.sql.Or(&p1, &p2)});
        }
        if (level >= 0) _ = try q.Where(.{preds.levelEQ(.{ .int = level })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderDesc("created_at")});
        var paged = try q.paged(page, page_size);
        defer paged.deinit();
        var out = try self.allocator.alloc(CommissionRow, paged.items.items.len);
        var n: usize = 0;
        errdefer {
            for (out[0..n]) |r| r.free(self.allocator);
            self.allocator.free(out);
        }
        for (paged.items.items) |e| {
            out[n] = try self.dupCommission(e);
            n += 1;
        }
        return .{ .items = out, .total = paged.total };
    }
};
