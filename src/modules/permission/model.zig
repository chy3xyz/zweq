//! zent schema-as-code — RBAC for zweq.
//!
//! WeEngine roles: founder (创始人) / admin (管理员) / operator (操作员).
//! `Permission` grants a module+action on a site account (account_id 0 =
//! platform-wide). `UserRole` binds a user to a role within a site.

const zent = @import("zent");
const field = zent.core.field;
const Schema = zent.core.schema.Schema;

pub const Role = Schema("Role", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.String("name"),
        // code: founder | admin | operator
        field.String("code").Default("operator"),
        field.String("description").Default(""),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});

pub const Permission = Schema("Permission", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id").Default(0),
        field.String("module"),
        field.String("action"),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});

pub const UserRole = Schema("UserRole", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("user_id"),
        field.Int("role_id"),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});
