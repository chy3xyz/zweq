//! zent schema-as-code — 积分商城（营销域，对齐微擎积分玩法）。
//!
//! `PointsProduct` 积分商品；`PointsOrder` 兑换记录（粉丝用会员积分兑换）。
//! 积分余额存在 `member.Fan.points`（adjustPoints 调整）。

const zent = @import("zent");
const field = zent.core.field;
const Schema = zent.core.schema.Schema;

pub const PointsProduct = Schema("PointsProduct", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.String("name").Default(""),
        field.Int("points").Default(0),
        field.Int("stock").Default(0),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});

pub const PointsOrder = Schema("PointsOrder", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.String("openid").Default(""),
        field.Int("product_id").Default(0),
        field.String("product_name").Default(""),
        field.Int("points_spent").Default(0),
        field.String("status").Default("completed"),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});
