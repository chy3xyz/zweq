//! zent schema-as-code — 分销（distribution）场景应用。
//!
//! 三级分销：分销员（Distributor）+ 佣金记录（CommissionRecord）。
//! 购买者消费 → 沿上级链最多 3 级按比例分佣。公众号「分销」查佣金、
//! 「加盟」注册分销员。

const zent = @import("zent");
const field = zent.core.field;
const Schema = zent.core.schema.Schema;

/// 分销员。parent_openid 为上级分销员（空 = 无上级）。
pub const Distributor = Schema("Distributor", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.String("openid"),
        field.String("parent_openid").Default(""),
        field.Int("commission_balance").Default(0), // 佣金余额（分）
        field.Int("total_commission").Default(0), // 累计佣金（分）
        field.Int("status").Default(1), // 1=active
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});

/// 佣金记录。level = 1/2/3 级；source_openid 为消费购买者。
pub const CommissionRecord = Schema("CommissionRecord", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.String("openid"), // 受益分销员
        field.String("source_openid"), // 购买者
        field.Int("level").Default(1),
        field.Int("amount").Default(0), // 佣金（分）
        field.Int("status").Default(0), // 0=pending 1=settled
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});
