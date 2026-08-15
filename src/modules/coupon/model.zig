//! zent schema-as-code — 优惠券（coupon）场景应用。
//!
//! 电商核心营销能力：券模板（面额/门槛/总量/每人限领/有效期）+ 用户券
//! （领券生成券码，未用/已用/过期状态流转，核销幂等）。公众号消息「领券」
//! 经 Receiver 钩子领取。

const zent = @import("zent");
const field = zent.core.field;
const Schema = zent.core.schema.Schema;

/// 券模板：一次性配置，总量/每人限领控制发放节奏。
pub const Coupon = Schema("Coupon", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.String("title"),
        field.Int("amount").Default(0), // 面额（分）
        field.Int("min_amount").Default(0), // 使用门槛（分），0=无门槛
        field.Int("total").Default(0), // 发放总量，0=不限
        field.Int("per_user").Default(1), // 每人限领
        field.Int("start_at").Default(0), // 生效时间（秒）
        field.Int("end_at").Default(0), // 失效时间（秒），0=永不过期
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});

/// 用户券：领取后生成，券码唯一，核销幂等。
pub const CouponUser = Schema("CouponUser", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.String("openid"),
        field.Int("coupon_id"),
        field.String("code"), // 券码 CP-XXXXXXXX
        // status: unused | used | expired
        field.String("status").Default("unused"),
        field.Int("used_at").Default(0),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});
