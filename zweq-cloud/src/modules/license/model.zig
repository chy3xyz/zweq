//! zent schema-as-code — 云服务授权码（微擎 license）。

const zent = @import("zent");
const field = zent.core.field;
const Schema = zent.core.schema.Schema;

pub const License = Schema("License", .{
    .fields = &.{
        field.String("license_key"),
        // status: active | expired | revoked
        field.String("status").Default("active"),
        field.Int("expires_at").Default(0),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});
