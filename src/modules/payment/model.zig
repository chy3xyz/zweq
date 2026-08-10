//! zent schema-as-code — member wallet + recharge orders + withdraws.
//!
//! Amounts are integer cents. A recharge order moves `pending` → `paid`
//! (credit wallet, idempotent) or `closed`. The payment gateway (WeChat Pay
//! v3 via zwechat) plugs into `completeRecharge` on notify.

const zent = @import("zent");
const field = zent.core.field;
const Schema = zent.core.schema.Schema;

pub const Wallet = Schema("Wallet", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.Int("fan_id"),
        field.Int("balance").Default(0),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});

pub const RechargeOrder = Schema("RechargeOrder", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.String("order_no"),
        field.Int("fan_id").Default(0),
        field.Int("amount").Default(0),
        // channel: mock | wxpay_v3
        field.String("channel").Default("mock"),
        // status: pending | paid | closed
        field.String("status").Default("pending"),
        field.Int("paid_at").Default(0),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});

pub const Withdraw = Schema("Withdraw", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.Int("fan_id"),
        field.Int("amount").Default(0),
        // status: pending | approved | rejected | paid
        field.String("status").Default("pending"),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});
