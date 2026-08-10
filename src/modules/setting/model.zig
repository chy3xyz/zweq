//! zent schema-as-code — site settings (key-value, per tenant).

const zent = @import("zent");
const field = zent.core.field;
const Schema = zent.core.schema.Schema;

pub const SiteSetting = Schema("SiteSetting", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.String("key"),
        field.String("value").Default(""),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});
