//! zent schema-as-code — 微擎 模块/应用 注册表 + 账号绑定。
//!
//! `AppModule` is the compile-time module registry (each business domain is a
//! built-in module). `ModuleBinding` enables/disables a module per account —
//! the Zig equivalent of WeEngine's runtime addon install.

const zent = @import("zent");
const field = zent.core.field;
const Schema = zent.core.schema.Schema;

pub const AppModule = Schema("AppModule", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.String("name"),
        field.String("title").Default(""),
        field.String("version").Default("1.0.0"),
        field.String("status").Default("active"),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});

pub const ModuleBinding = Schema("ModuleBinding", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.String("module"),
        field.String("status").Default("active"),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});
