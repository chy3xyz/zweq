//! 营销域存储：余额套餐 / 邀请有礼 / 拼团与参团。拆分自原 ShopStore，方法逐字保留。
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

/// MarketingStore 持有独立的 allocator/client 拷贝（Client 内部 driver 为共享句柄，
/// 多份值拷贝指向同一连接与 PreparedCache，与拆分前行为一致）。
pub const MarketingStore = struct {
    allocator: std.mem.Allocator,
    client: Client,

    pub fn createBalancePlan(self: *MarketingStore, tenant_id: i64, account_id: i64, name: []const u8, amount: i64, bonus: i64, now: i64) !i64 {
        const amount_str = try std.fmt.allocPrint(self.allocator, "{d}", .{amount});
        defer self.allocator.free(amount_str);
        const bonus_str = try std.fmt.allocPrint(self.allocator, "{d}", .{bonus});
        defer self.allocator.free(bonus_str);
        var row = try crud.create(self.client.shop_balance_plan, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .name = name,
            .amount = amount_str,
            .bonus = bonus_str,
            .status = 1,
            .created_at = now,
            .updated_at = now,
        });
        defer self.client.shop_balance_plan.deinitRow(&row);
        return row.id;
    }

    pub fn listBalancePlans(self: *MarketingStore, tenant_id: i64, account_id: i64) ![]ShopBalancePlanRow {
        var q = self.client.shop_balance_plan.Query();
        defer q.deinit();
        const preds = self.client.shop_balance_plan.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        if (account_id > 0) _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.Where(.{preds.statusEQ(.{ .int = 1 })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderAsc("amount")});
        var rows = try q.All();
        defer self.client.shop_balance_plan.deinitRows(&rows);
        var out = try self.allocator.alloc(ShopBalancePlanRow, rows.items.len);
        errdefer self.allocator.free(out);
        var n: usize = 0;
        errdefer for (out[0..n]) |r| r.free(self.allocator);
        for (rows.items) |e| {
            out[n] = .{
                .id = e.id,
                .account_id = e.account_id,
                .name = try self.allocator.dupe(u8, e.name),
                .amount = try self.allocator.dupe(u8, e.amount),
                .bonus = try self.allocator.dupe(u8, e.bonus),
                .status = e.status,
                .created_at = e.created_at orelse 0,
            };
            n += 1;
        }
        return out;
    }

    pub fn getBalancePlan(self: *MarketingStore, id: i64) !?ShopBalancePlanRow {
        const preds = self.client.shop_balance_plan.predicates;
        var entity = (try crud.first(self.client.shop_balance_plan, .{preds.idEQ(.{ .int = id })})) orelse return null;
        defer self.client.shop_balance_plan.deinitRow(&entity);
        return .{
            .id = entity.id,
            .account_id = entity.account_id,
            .name = try self.allocator.dupe(u8, entity.name),
            .amount = try self.allocator.dupe(u8, entity.amount),
            .bonus = try self.allocator.dupe(u8, entity.bonus),
            .status = entity.status,
            .created_at = entity.created_at orelse 0,
        };
    }

    pub fn deleteBalancePlan(self: *MarketingStore, id: i64) !bool {
        const preds = self.client.shop_balance_plan.predicates;
        var d = self.client.shop_balance_plan.Delete();
        defer d.deinit();
        _ = try d.Where(.{preds.idEQ(.{ .int = id })});
        return (try d.Exec()) > 0;
    }

    // ── Webhook ───────────────────────────────────────────

    pub fn createInviteGift(self: *MarketingStore, tenant_id: i64, account_id: i64, target_count: i64, reward_type: []const u8, reward_value: i64, now: i64) !i64 {
        var row = try crud.create(self.client.shop_invite_gift, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .target_count = target_count,
            .reward_type = reward_type,
            .reward_value = reward_value,
            .status = 1,
            .created_at = now,
            .updated_at = now,
        });
        defer self.client.shop_invite_gift.deinitRow(&row);
        return row.id;
    }

    pub fn listInviteGifts(self: *MarketingStore, tenant_id: i64, account_id: i64) ![]ShopInviteGiftRow {
        var q = self.client.shop_invite_gift.Query();
        defer q.deinit();
        const preds = self.client.shop_invite_gift.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        if (account_id > 0) _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.Where(.{preds.statusEQ(.{ .int = 1 })});
        var rows = try q.All();
        defer self.client.shop_invite_gift.deinitRows(&rows);
        var out = try self.allocator.alloc(ShopInviteGiftRow, rows.items.len);
        errdefer self.allocator.free(out);
        var n: usize = 0;
        errdefer for (out[0..n]) |r| r.free(self.allocator);
        for (rows.items) |e| {
            out[n] = .{
                .id = e.id,
                .account_id = e.account_id,
                .target_count = e.target_count,
                .reward_type = try self.allocator.dupe(u8, e.reward_type),
                .reward_value = e.reward_value,
                .status = e.status,
                .created_at = e.created_at orelse 0,
            };
            n += 1;
        }
        return out;
    }

    pub fn deleteInviteGift(self: *MarketingStore, id: i64) !bool {
        const preds = self.client.shop_invite_gift.predicates;
        var d = self.client.shop_invite_gift.Delete();
        defer d.deinit();
        _ = try d.Where(.{preds.idEQ(.{ .int = id })});
        return (try d.Exec()) > 0;
    }

    /// 绑定邀请关系（幂等：同 invitee 只记一次）。
    /// 依赖 shop_invite_record 的 UNIQUE(tenant_id, invitee_openid) 索引 +
    /// INSERT OR IGNORE 原子去重：count-then-insert 在并发下会产生重复邀请
    /// 记录（且重复计数让达标发奖超额），唯一键冲突映射是跨方言的最小修法。
    /// 返回 true=新绑定（调用方发奖），false=已绑定（冲突被忽略）。
    pub fn bindInvite(self: *MarketingStore, tenant_id: i64, account_id: i64, inviter_openid: []const u8, invitee_openid: []const u8, now: i64) !bool {
        var cb = try self.client.shop_invite_record.Create();
        defer cb.deinit();
        _ = try cb.setFieldValue("tenant_id", tenant_id);
        _ = try cb.setFieldValue("account_id", account_id);
        _ = try cb.setFieldValue("inviter_openid", inviter_openid);
        _ = try cb.setFieldValue("invitee_openid", invitee_openid);
        _ = try cb.setFieldValue("created_at", now);
        _ = try cb.setFieldValue("updated_at", now);
        var row = try cb.SaveIgnore();
        defer self.client.shop_invite_record.deinitRow(&row);
        // 唯一键冲突被忽略时 id 为 0（SQLite/PG 无 RETURNING 行，MySQL last_insert_id=0）。
        return row.id != 0;
    }

    /// 邀请人已邀请人数。
    pub fn countInvites(self: *MarketingStore, tenant_id: i64, inviter_openid: []const u8) !i64 {
        var q = self.client.shop_invite_record.Query();
        defer q.deinit();
        const preds = self.client.shop_invite_record.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.inviter_openidEQ(.{ .string = inviter_openid })});
        return q.Count();
    }

    // ── 拼团 ──────────────────────────────────────────────

    pub fn createGroupon(self: *MarketingStore, tenant_id: i64, account_id: i64, product_id: i64, group_price: i64, group_size: i64, start_at: i64, end_at: i64, now: i64) !i64 {
        const group_price_str = try std.fmt.allocPrint(self.allocator, "{d}", .{group_price});
        defer self.allocator.free(group_price_str);
        var row = try crud.create(self.client.shop_groupon, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .product_id = product_id,
            .group_price = group_price_str,
            .group_size = group_size,
            .start_at = start_at,
            .end_at = end_at,
            .status = 1,
            .created_at = now,
            .updated_at = now,
        });
        defer self.client.shop_groupon.deinitRow(&row);
        return row.id;
    }

    /// 按 id + tenant_id 读活动，防跨租户参团/开团（IDOR）。
    pub fn getGroupon(self: *MarketingStore, tenant_id: i64, id: i64) !?ShopGrouponRow {
        const preds = self.client.shop_groupon.predicates;
        var entity = (try crud.first(self.client.shop_groupon, .{ preds.idEQ(.{ .int = id }), preds.tenant_idEQ(.{ .int = tenant_id }) })) orelse return null;
        defer self.client.shop_groupon.deinitRow(&entity);
        return .{
            .id = entity.id,
            .account_id = entity.account_id,
            .product_id = entity.product_id,
            .group_price = try self.allocator.dupe(u8, entity.group_price),
            .group_size = entity.group_size,
            .start_at = entity.start_at,
            .end_at = entity.end_at,
            .status = entity.status,
            .created_at = entity.created_at orelse 0,
        };
    }

    pub fn listGroupons(self: *MarketingStore, tenant_id: i64, account_id: i64) ![]ShopGrouponRow {
        var q = self.client.shop_groupon.Query();
        defer q.deinit();
        const preds = self.client.shop_groupon.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        if (account_id > 0) _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.Where(.{preds.statusEQ(.{ .int = 1 })});
        var rows = try q.All();
        defer self.client.shop_groupon.deinitRows(&rows);
        var out = try self.allocator.alloc(ShopGrouponRow, rows.items.len);
        errdefer self.allocator.free(out);
        var n: usize = 0;
        for (rows.items) |e| {
            out[n] = .{
                .id = e.id,
                .account_id = e.account_id,
                .product_id = e.product_id,
                .group_price = try self.allocator.dupe(u8, e.group_price),
                .group_size = e.group_size,
                .start_at = e.start_at,
                .end_at = e.end_at,
                .status = e.status,
                .created_at = e.created_at orelse 0,
            };
            n += 1;
        }
        return out;
    }

    pub fn createTeam(self: *MarketingStore, tenant_id: i64, account_id: i64, activity_id: i64, leader_openid: []const u8, now: i64) !i64 {
        var row = try crud.create(self.client.shop_groupon_team, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .activity_id = activity_id,
            .leader_openid = leader_openid,
            .current = 1,
            .status = 0,
            .created_at = now,
            .updated_at = now,
        });
        defer self.client.shop_groupon_team.deinitRow(&row);
        return row.id;
    }

    /// 按 id + tenant_id 读团，防跨租户参团（IDOR）。
    pub fn getTeam(self: *MarketingStore, tenant_id: i64, id: i64) !?ShopGrouponTeamRow {
        const preds = self.client.shop_groupon_team.predicates;
        var entity = (try crud.first(self.client.shop_groupon_team, .{ preds.idEQ(.{ .int = id }), preds.tenant_idEQ(.{ .int = tenant_id }) })) orelse return null;
        defer self.client.shop_groupon_team.deinitRow(&entity);
        return .{
            .id = entity.id,
            .account_id = entity.account_id,
            .activity_id = entity.activity_id,
            .leader_openid = try self.allocator.dupe(u8, entity.leader_openid),
            .current = entity.current,
            .status = entity.status,
            .created_at = entity.created_at orelse 0,
        };
    }

    /// 参团计数 +1，返回是否成团（current >= group_size）。
    pub fn joinTeam(self: *MarketingStore, allocator: std.mem.Allocator, tenant_id: i64, team_id: i64, group_size: i64) !bool {
        const preds = self.client.shop_groupon_team.predicates;
        _ = crud.increment(self.client.shop_groupon_team, "current", 1, &.{
            preds.idEQ(.{ .int = team_id }),
        }) catch return false;
        const team_opt = self.getTeam(tenant_id, team_id) catch return false;
        const team = team_opt orelse return false;
        defer team.free(allocator);
        if (team.current >= group_size) {
            var upd = self.client.shop_groupon_team.Update();
            defer upd.deinit();
            _ = try upd.set("status", .{ .int = 1 });
            _ = try upd.Where(.{preds.idEQ(.{ .int = team_id })});
            _ = try upd.Save();
            return true;
        }
        return false;
    }

    /// 按团查订单（成团后批量标记支付）。
    pub fn listOrdersByTeam(self: *MarketingStore, team_id: i64) ![]ShopOrderRow {
        var q = self.client.shop_order.Query();
        defer q.deinit();
        const preds = self.client.shop_order.predicates;
        _ = try q.Where(.{preds.groupon_team_idEQ(.{ .int = team_id })});
        var rows = try q.All();
        defer self.client.shop_order.deinitRows(&rows);
        var out = try self.allocator.alloc(ShopOrderRow, rows.items.len);
        errdefer self.allocator.free(out);
        var n: usize = 0;
        errdefer for (out[0..n]) |r| r.free(self.allocator);
        for (rows.items) |e| {
            out[n] = .{
                .id = e.id,
                .account_id = e.account_id,
                .order_no = try self.allocator.dupe(u8, e.order_no),
                .client_trade_no = try self.allocator.dupe(u8, e.client_trade_no),
                .openid = try self.allocator.dupe(u8, e.openid),
                .total_amount = try self.allocator.dupe(u8, e.total_amount),
                .pay_amount = try self.allocator.dupe(u8, e.pay_amount),
                .status = e.status,
                .address_json = try self.allocator.dupe(u8, e.address_json),
                .express_company = try self.allocator.dupe(u8, e.express_company),
                .express_no = try self.allocator.dupe(u8, e.express_no),
                .paid_at = e.paid_at,
                .pickup_type = try self.allocator.dupe(u8, e.pickup_type),
                .pickup_code = try self.allocator.dupe(u8, e.pickup_code),
                .store_id = e.store_id,
                .groupon_team_id = e.groupon_team_id,
                .created_at = e.created_at orelse 0,
            };
            n += 1;
        }
        return out;
    }

    // ── 门店 ──────────────────────────────────────────────
};
