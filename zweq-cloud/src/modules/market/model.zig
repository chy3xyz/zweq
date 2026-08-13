//! zent schema-as-code — 应用市场包。

const zent = @import("zent");
const field = zent.core.field;
const Schema = zent.core.schema.Schema;

pub const MarketPackage = Schema("MarketPackage", .{
    .fields = &.{
        field.String("name"),
        field.String("title").Default(""),
        field.String("version").Default("1.0.0"),
        field.String("description").Default(""),
        field.String("download_url").Default(""),
        // 产物 sha256 hex（发布时可选；下载后校验，防止篡改）。
        field.String("checksum").Default(""),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});
