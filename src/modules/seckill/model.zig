//! zent schema-as-code — 秒杀（seckill）场景应用。
//!
//! 电商营销核心：限时低价 + 限量抢购。活动（SeckillActivity）+ 抢购记录
//! （SeckillOrder）。公众号「秒杀」列进行中活动，「抢N」抢购。

const zent = @import("zent");
const field = zent.core.field;
const Schema = zent.core.schema.Schema;

/// 秒杀活动。stock 为可抢总量（原子扣减），per_user 每人限购。
pub const SeckillActivity = Schema("SeckillActivity", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.String("title"),
        field.Int("price").Default(0), // 秒杀价（分）
        field.Int("original_price").Default(0), // 原价（分）
        field.Int("stock").Default(0), // 总库存
        field.Int("sold").Default(0), // 已售
        field.Int("per_user").Default(1), // 每人限购
        field.Int("start_at").Default(0),
        field.Int("end_at").Default(0),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});

/// 抢购记录（幂等：openid + activity_id 唯一，即每人一单）。
pub const SeckillOrder = Schema("SeckillOrder", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.String("openid"),
        field.Int("activity_id"),
        field.Int("quantity").Default(1),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});
