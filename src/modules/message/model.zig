//! zent schema-as-code — WeChat server callback log.

const zent = @import("zent");
const field = zent.core.field;
const Schema = zent.core.schema.Schema;

pub const MessageLog = Schema("MessageLog", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.String("msg_id").Default(""),
        field.String("openid").Default(""),
        field.String("msg_type").Default(""),
        field.String("event").Default(""),
        field.String("content").Default(""),
        field.String("reply_type").Default(""),
        field.String("reply_content").Default(""),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});
