//! zent schema-as-code — 站点云服务：授权码 + 应用市场。
//!
//! `License` = a site license key (微擎授权码), verified before module
//! installs. `MarketPackage` = a marketplace module package; installing it
//! registers the module in the app registry and optionally binds an account.

const zent = @import("zent");
const field = zent.core.field;
const Schema = zent.core.schema.Schema;

pub const License = Schema("License", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.String("license_key"),
        // status: active | expired | revoked
        field.String("status").Default("active"),
        field.Int("expires_at").Default(0),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});

pub const MarketPackage = Schema("MarketPackage", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.String("name"),
        field.String("title").Default(""),
        field.String("version").Default("1.0.0"),
        field.String("description").Default(""),
        field.String("download_url").Default(""),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});
