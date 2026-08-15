//! zent schema-as-code — 商城（shop）核心域。
//!
//! 商品分类（ShopCategory）+ 商品（ShopProduct）+ 商品 SKU（ShopProductSku）
//! Phase 1：商品域。Phase 2/3 追加 购物车/地址/订单/退款/评价。

const zent = @import("zent");
const field = zent.core.field;
const Schema = zent.core.schema.Schema;

/// 商品分类（支持二级：parent_id=0 为一级）。
pub const ShopCategory = Schema("ShopCategory", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.String("name"),
        field.Int("parent_id").Default(0),
        field.Int("sort").Default(0),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});

/// 商品。价格单位「分」；status=1 上架 0 下架；stock 为总库存（默认 SKU 口径）。
pub const ShopProduct = Schema("ShopProduct", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.Int("category_id").Default(0),
        field.String("name"),
        field.String("image").Default(""),
        field.String("content").Default(""),
        field.Int("price").Default(0),
        field.Int("original_price").Default(0),
        field.Int("stock").Default(0),
        field.Int("sales").Default(0),
        field.Int("status").Default(1),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});

/// 商品 SKU（单规格也建默认行；多规格 spec_json 存 `[{"k":"颜色","v":"红色"}]`）。
pub const ShopProductSku = Schema("ShopProductSku", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.Int("product_id"),
        field.String("spec_json").Default("[]"),
        field.String("image").Default(""),
        field.Int("price").Default(0),
        field.Int("stock").Default(0),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});

/// 购物车（openid + sku 唯一，数量累加）。
pub const ShopCart = Schema("ShopCart", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.String("openid"),
        field.Int("product_id"),
        field.Int("sku_id"),
        field.Int("quantity").Default(1),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});

/// 收货地址。
pub const ShopAddress = Schema("ShopAddress", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.String("openid"),
        field.String("name"),
        field.String("mobile"),
        field.String("region"),
        field.String("detail"),
        field.Int("is_default").Default(0),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});

/// 订单。status: 0=待支付 1=已支付 2=已发货 3=已完成 4=已取消。
/// 支付走 payment 模块（mock 渠道即时入账 / v3 微信支付）。
pub const ShopOrder = Schema("ShopOrder", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.String("order_no"),
        field.String("client_trade_no").Default(""), // 幂等键（调用方幂等单号）
        field.String("openid"),
        field.Int("total_amount").Default(0), // 商品总额（分）
        field.Int("pay_amount").Default(0), // 实付（分）
        field.Int("status").Default(0),
        field.String("address_json").Default("{}"),
        field.String("express_company").Default(""),
        field.String("express_no").Default(""),
        field.Int("paid_at").Default(0),
        // 自提：pickup_type: delivery|self；pickup_code 核销码；store_id 门店
        field.String("pickup_type").Default("delivery"),
        field.String("pickup_code").Default(""),
        field.Int("store_id").Default(0),
        // 拼团：groupon_team_id>0 表示拼团订单
        field.Int("groupon_team_id").Default(0),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});

/// 订单商品快照（下单时固化名称/图/价）。
pub const ShopOrderProduct = Schema("ShopOrderProduct", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.Int("order_id"),
        field.Int("product_id"),
        field.Int("sku_id"),
        field.String("name"),
        field.String("image").Default(""),
        field.String("spec_json").Default("[]"),
        field.Int("price").Default(0),
        field.Int("quantity").Default(1),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});

/// 退款申请。status: 0=待审核 1=已同意 2=已拒绝。
pub const ShopRefund = Schema("ShopRefund", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.Int("order_id"),
        field.String("openid"),
        field.String("reason"),
        field.Int("amount").Default(0),
        field.Int("status").Default(0),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});

/// 商品评价（订单商品维度，一单一件一条）。
pub const ShopComment = Schema("ShopComment", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.Int("order_product_id"),
        field.Int("product_id"),
        field.String("openid"),
        field.Int("star").Default(5),
        field.String("content").Default(""),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});

/// 商品收藏（openid + product 唯一）。
pub const ShopFavorite = Schema("ShopFavorite", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.String("openid"),
        field.Int("product_id"),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});

/// 门店（自提点）。status=1 营业。
pub const ShopOutlet = Schema("ShopOutlet", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.String("name"),
        field.String("address").Default(""),
        field.String("mobile").Default(""),
        field.Int("status").Default(1),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});

/// 储值卡套餐（充 amount 送 bonus，钱包入账 amount+bonus）。
pub const ShopBalancePlan = Schema("ShopBalancePlan", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.String("name"),
        field.Int("amount").Default(0),
        field.Int("bonus").Default(0),
        field.Int("status").Default(1),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});

/// 拼团活动（团价 < 售价，N 人成团）。
pub const ShopGroupon = Schema("ShopGroupon", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.Int("product_id"),
        field.Int("group_price").Default(0),
        field.Int("group_size").Default(2),
        field.Int("start_at").Default(0),
        field.Int("end_at").Default(0),
        field.Int("status").Default(1),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});

/// 拼团（team）：leader 开团，current 参团数；status 0=拼团中 1=成功 2=失败。
pub const ShopGrouponTeam = Schema("ShopGrouponTeam", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.Int("activity_id"),
        field.String("leader_openid"),
        field.Int("current").Default(1),
        field.Int("status").Default(0),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});

/// 邀请奖励配置（邀请 target_count 人 → 发 points 或 coupon）。
pub const ShopInviteGift = Schema("ShopInviteGift", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.Int("target_count").Default(1),
        field.String("reward_type").Default("points"), // points | coupon
        field.Int("reward_value").Default(0),
        field.Int("status").Default(1),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});

/// 邀请关系（invitee 唯一）。
pub const ShopInviteRecord = Schema("ShopInviteRecord", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.String("inviter_openid"),
        field.String("invitee_openid"),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});

/// 文章（内容营销/公告）。status=1 发布。
pub const ShopArticle = Schema("ShopArticle", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.String("title"),
        field.String("content").Default(""),
        field.Int("status").Default(1),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});

/// 订单事件 Webhook（支付/发货事件推送商家 URL）。
pub const ShopWebhook = Schema("ShopWebhook", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.String("url"),
        field.String("events").Default("order.paid"), // 逗号分隔
        field.Int("status").Default(1),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});
