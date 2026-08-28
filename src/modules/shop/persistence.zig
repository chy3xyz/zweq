//! 商城持久层门面 —— schema graph、Client 与子域 Store 的聚合入口。
//!
//! 原单文件 ShopStore（1800+ 行）已按子域拆分，方法逐字搬运：
//!   model.zig            zent schema 定义（未动）
//!   rows.zig             行类型 Row / ListResult 及其 free()
//!   catalog_store.zig    分类 / 商品 / SKU 与库存、销量原语
//!   trade_store.zig      购物车 / 地址 / 订单 / 收藏 / 退款 / 评论
//!   marketing_store.zig  余额套餐 / 邀请有礼 / 拼团
//!   content_store.zig    webhook / 文章 / 门店
//! 本文件保持上层引用面稳定：persist.Xxx 行类型与 ShopStore.init 签名不变，
//! 方法调用从 store.xxx 迁移为 store.<domain>.xxx。

const std = @import("std");
const zent = @import("zent");
const crud = zent.crud_helpers;
const model = @import("model.zig");
const schema = @import("../../schema.zig");

const graph = zent.codegen.graph.buildGraph(&.{ model.ShopCategory, model.ShopProduct, model.ShopProductSku, model.ShopCart, model.ShopAddress, model.ShopOrder, model.ShopOrderProduct, model.ShopRefund, model.ShopComment, model.ShopFavorite, model.ShopOutlet, model.ShopBalancePlan, model.ShopGroupon, model.ShopGrouponTeam, model.ShopInviteGift, model.ShopInviteRecord, model.ShopArticle, model.ShopWebhook });
pub const infos = graph.types;
pub const Client = schema.Client;
pub const ShopCategoryInfo = infos[0];
pub const ShopProductInfo = infos[1];
pub const ShopProductSkuInfo = infos[2];
pub const ShopCartInfo = infos[3];
pub const ShopAddressInfo = infos[4];
pub const ShopOrderInfo = infos[5];
pub const ShopOrderProductInfo = infos[6];
pub const ShopRefundInfo = infos[7];
pub const ShopCommentInfo = infos[8];
pub const ShopFavoriteInfo = infos[9];
pub const ShopOutletInfo = infos[10];
pub const ShopBalancePlanInfo = infos[11];
pub const ShopGrouponInfo = infos[12];
pub const ShopGrouponTeamInfo = infos[13];
pub const ShopInviteGiftInfo = infos[14];
pub const ShopInviteRecordInfo = infos[15];
pub const ShopArticleInfo = infos[16];
pub const ShopWebhookInfo = infos[17];

pub const rows = @import("rows.zig");
pub const CatalogStore = @import("catalog_store.zig").CatalogStore;
pub const TradeStore = @import("trade_store.zig").TradeStore;
pub const MarketingStore = @import("marketing_store.zig").MarketingStore;
pub const ContentStore = @import("content_store.zig").ContentStore;

// 行类型再导出：调用方 persist.ShopXxxRow 引用保持不变。
pub const ShopCategoryRow = rows.ShopCategoryRow;
pub const ShopProductRow = rows.ShopProductRow;
pub const ShopSkuRow = rows.ShopSkuRow;
pub const CategoryListResult = rows.CategoryListResult;
pub const ProductListResult = rows.ProductListResult;
pub const ShopCartRow = rows.ShopCartRow;
pub const ShopAddressRow = rows.ShopAddressRow;
pub const ShopOrderRow = rows.ShopOrderRow;
pub const ShopOrderProductRow = rows.ShopOrderProductRow;
pub const OrderListResult = rows.OrderListResult;
pub const ShopRefundRow = rows.ShopRefundRow;
pub const ShopCommentRow = rows.ShopCommentRow;
pub const RefundListResult = rows.RefundListResult;
pub const ShopFavoriteRow = rows.ShopFavoriteRow;
pub const ShopOutletRow = rows.ShopOutletRow;
pub const ShopBalancePlanRow = rows.ShopBalancePlanRow;
pub const ShopGrouponRow = rows.ShopGrouponRow;
pub const ShopGrouponTeamRow = rows.ShopGrouponTeamRow;
pub const ShopInviteGiftRow = rows.ShopInviteGiftRow;
pub const ShopInviteRecordRow = rows.ShopInviteRecordRow;
pub const ShopArticleRow = rows.ShopArticleRow;
pub const ArticleListResult = rows.ArticleListResult;
pub const ShopWebhookRow = rows.ShopWebhookRow;

/// 聚合门面：allocator / client 字段语义与拆分前一致；子域分别挂在
/// .catalog / .trade / .marketing / .content 下。
pub const ShopStore = struct {
    allocator: std.mem.Allocator,
    client: Client,
    catalog: CatalogStore,
    trade: TradeStore,
    marketing: MarketingStore,
    content: ContentStore,

    pub fn init(allocator: std.mem.Allocator, client: Client) ShopStore {
        return .{
            .allocator = allocator,
            .client = client,
            .catalog = .{ .allocator = allocator, .client = client },
            .trade = .{ .allocator = allocator, .client = client },
            .marketing = .{ .allocator = allocator, .client = client },
            .content = .{ .allocator = allocator, .client = client },
        };
    }
};
