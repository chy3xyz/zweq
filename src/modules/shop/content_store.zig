//! 内容与门店域存储：webhook 订阅 / 商城文章 / 自提门店。拆分自原 ShopStore，方法逐字保留。
const std = @import("std");
const zent = @import("zent");
const crud = zent.crud_helpers;
const persist = @import("persistence.zig");
const Client = persist.Client;

// 行类型经 rows.zig 引用（沿用原名，正文逐字搬运）。
const rows_mod = @import("rows.zig");
const infos = persist.infos;
const ShopCategoryInfo = persist.ShopCategoryInfo;
const ShopProductInfo = persist.ShopProductInfo;
const ShopProductSkuInfo = persist.ShopProductSkuInfo;
const ShopCartInfo = persist.ShopCartInfo;
const ShopAddressInfo = persist.ShopAddressInfo;
const ShopOrderInfo = persist.ShopOrderInfo;
const ShopOrderProductInfo = persist.ShopOrderProductInfo;
const ShopRefundInfo = persist.ShopRefundInfo;
const ShopCommentInfo = persist.ShopCommentInfo;
const ShopFavoriteInfo = persist.ShopFavoriteInfo;
const ShopOutletInfo = persist.ShopOutletInfo;
const ShopBalancePlanInfo = persist.ShopBalancePlanInfo;
const ShopGrouponInfo = persist.ShopGrouponInfo;
const ShopGrouponTeamInfo = persist.ShopGrouponTeamInfo;
const ShopInviteGiftInfo = persist.ShopInviteGiftInfo;
const ShopInviteRecordInfo = persist.ShopInviteRecordInfo;
const ShopArticleInfo = persist.ShopArticleInfo;
const ShopWebhookInfo = persist.ShopWebhookInfo;
const ShopCategoryRow = rows_mod.ShopCategoryRow;
const ShopProductRow = rows_mod.ShopProductRow;
const ShopSkuRow = rows_mod.ShopSkuRow;
const CategoryListResult = rows_mod.CategoryListResult;
const ProductListResult = rows_mod.ProductListResult;
const ShopCartRow = rows_mod.ShopCartRow;
const ShopAddressRow = rows_mod.ShopAddressRow;
const ShopOrderRow = rows_mod.ShopOrderRow;
const ShopOrderProductRow = rows_mod.ShopOrderProductRow;
const OrderListResult = rows_mod.OrderListResult;
const ShopRefundRow = rows_mod.ShopRefundRow;
const ShopCommentRow = rows_mod.ShopCommentRow;
const RefundListResult = rows_mod.RefundListResult;
const ShopFavoriteRow = rows_mod.ShopFavoriteRow;
const ShopOutletRow = rows_mod.ShopOutletRow;
const ShopBalancePlanRow = rows_mod.ShopBalancePlanRow;
const ShopGrouponRow = rows_mod.ShopGrouponRow;
const ShopGrouponTeamRow = rows_mod.ShopGrouponTeamRow;
const ShopInviteGiftRow = rows_mod.ShopInviteGiftRow;
const ShopInviteRecordRow = rows_mod.ShopInviteRecordRow;
const ShopArticleRow = rows_mod.ShopArticleRow;
const ArticleListResult = rows_mod.ArticleListResult;
const ShopWebhookRow = rows_mod.ShopWebhookRow;

/// ContentStore 持有独立的 allocator/client 拷贝（Client 内部 driver 为共享句柄，
/// 多份值拷贝指向同一连接与 PreparedCache，与拆分前行为一致）。
pub const ContentStore = struct {
    allocator: std.mem.Allocator,
    client: Client,

    pub fn createWebhook(self: *ContentStore, tenant_id: i64, account_id: i64, url: []const u8, events: []const u8, now: i64) !i64 {
        var row = try crud.create(self.client.shop_webhook, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .url = url,
            .events = events,
            .status = 1,
            .created_at = now,
            .updated_at = now,
        });
        defer zent.codegen.deinitEntity(infos, ShopWebhookInfo, &row, self.allocator);
        return row.id;
    }

    pub fn listWebhooks(self: *ContentStore, tenant_id: i64, account_id: i64) ![]ShopWebhookRow {
        var q = self.client.shop_webhook.Query();
        defer q.deinit();
        const preds = self.client.shop_webhook.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        if (account_id > 0) _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.Where(.{preds.statusEQ(.{ .int = 1 })});
        var rows = try q.All();
        defer {
            for (rows.items) |*e| zent.codegen.deinitEntity(infos, ShopWebhookInfo, e, self.allocator);
            rows.deinit();
        }
        var out = try self.allocator.alloc(ShopWebhookRow, rows.items.len);
        errdefer self.allocator.free(out);
        var n: usize = 0;
        errdefer for (out[0..n]) |r| r.free(self.allocator);
        for (rows.items) |e| {
            out[n] = .{
                .id = e.id,
                .account_id = e.account_id,
                .url = try self.allocator.dupe(u8, e.url),
                .events = try self.allocator.dupe(u8, e.events),
                .status = e.status,
                .created_at = e.created_at orelse 0,
            };
            n += 1;
        }
        return out;
    }

    pub fn deleteWebhook(self: *ContentStore, id: i64) !bool {
        const preds = self.client.shop_webhook.predicates;
        var d = self.client.shop_webhook.Delete();
        defer d.deinit();
        _ = try d.Where(.{preds.idEQ(.{ .int = id })});
        return (try d.Exec()) > 0;
    }

    // ── 文章 ──────────────────────────────────────────────

    pub fn createArticle(self: *ContentStore, tenant_id: i64, account_id: i64, title: []const u8, content: []const u8, now: i64) !i64 {
        var row = try crud.create(self.client.shop_article, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .title = title,
            .content = content,
            .status = 1,
            .created_at = now,
            .updated_at = now,
        });
        defer zent.codegen.deinitEntity(infos, ShopArticleInfo, &row, self.allocator);
        return row.id;
    }

    pub fn getArticle(self: *ContentStore, id: i64) !?ShopArticleRow {
        const preds = self.client.shop_article.predicates;
        var entity = (try crud.first(self.client.shop_article, .{preds.idEQ(.{ .int = id })})) orelse return null;
        defer zent.codegen.deinitEntity(infos, ShopArticleInfo, &entity, self.allocator);
        return .{
            .id = entity.id,
            .account_id = entity.account_id,
            .title = try self.allocator.dupe(u8, entity.title),
            .content = try self.allocator.dupe(u8, entity.content),
            .status = entity.status,
            .created_at = entity.created_at orelse 0,
        };
    }

    pub fn listArticles(self: *ContentStore, page: usize, page_size: usize, tenant_id: i64, account_id: i64, on_sale: bool) !ArticleListResult {
        var q = self.client.shop_article.Query();
        defer q.deinit();
        const preds = self.client.shop_article.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        if (account_id > 0) _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        if (on_sale) _ = try q.Where(.{preds.statusEQ(.{ .int = 1 })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderDesc("created_at")});
        var paged = try q.paged(page, page_size);
        defer paged.deinit();
        var out = try self.allocator.alloc(ShopArticleRow, paged.items.items.len);
        var n: usize = 0;
        errdefer {
            for (out[0..n]) |r| r.free(self.allocator);
            self.allocator.free(out);
        }
        for (paged.items.items) |e| {
            out[n] = .{
                .id = e.id,
                .account_id = e.account_id,
                .title = try self.allocator.dupe(u8, e.title),
                .content = try self.allocator.dupe(u8, e.content),
                .status = e.status,
                .created_at = e.created_at orelse 0,
            };
            n += 1;
        }
        return .{ .items = out, .total = paged.total };
    }

    pub fn deleteArticle(self: *ContentStore, id: i64) !bool {
        const preds = self.client.shop_article.predicates;
        var d = self.client.shop_article.Delete();
        defer d.deinit();
        _ = try d.Where(.{preds.idEQ(.{ .int = id })});
        return (try d.Exec()) > 0;
    }

    // ── 邀请有礼 ─────────────────────────────────────────

    pub fn createOutlet(self: *ContentStore, tenant_id: i64, account_id: i64, name: []const u8, address: []const u8, mobile: []const u8, now: i64) !i64 {
        var row = try crud.create(self.client.shop_outlet, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .name = name,
            .address = address,
            .mobile = mobile,
            .status = 1,
            .created_at = now,
            .updated_at = now,
        });
        defer zent.codegen.deinitEntity(infos, ShopOutletInfo, &row, self.allocator);
        return row.id;
    }

    pub fn listOutlets(self: *ContentStore, tenant_id: i64, account_id: i64) ![]ShopOutletRow {
        var q = self.client.shop_outlet.Query();
        defer q.deinit();
        const preds = self.client.shop_outlet.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        if (account_id > 0) _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        var rows = try q.All();
        defer {
            for (rows.items) |*e| zent.codegen.deinitEntity(infos, ShopOutletInfo, e, self.allocator);
            rows.deinit();
        }
        var out = try self.allocator.alloc(ShopOutletRow, rows.items.len);
        errdefer self.allocator.free(out);
        var n: usize = 0;
        errdefer for (out[0..n]) |r| r.free(self.allocator);
        for (rows.items) |e| {
            out[n] = .{
                .id = e.id,
                .account_id = e.account_id,
                .name = try self.allocator.dupe(u8, e.name),
                .address = try self.allocator.dupe(u8, e.address),
                .mobile = try self.allocator.dupe(u8, e.mobile),
                .status = e.status,
                .created_at = e.created_at orelse 0,
            };
            n += 1;
        }
        return out;
    }

    pub fn deleteOutlet(self: *ContentStore, id: i64) !bool {
        const preds = self.client.shop_outlet.predicates;
        var d = self.client.shop_outlet.Delete();
        defer d.deinit();
        _ = try d.Where(.{preds.idEQ(.{ .int = id })});
        return (try d.Exec()) > 0;
    }
};
