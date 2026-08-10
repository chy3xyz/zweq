//! zent schema-as-code — WeChat fans (微擎 粉丝).
//!
//! One row per (account_id, openid). `subscribed` flips on 关注/取关 events.

const zent = @import("zent");
const field = zent.core.field;
const Schema = zent.core.schema.Schema;

pub const Fan = Schema("Fan", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.String("openid"),
        field.String("unionid").Default(""),
        field.String("nickname").Default(""),
        field.String("avatar").Default(""),
        field.Bool("subscribed").Default(true),
        field.Int("subscribe_time").Default(0),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});
