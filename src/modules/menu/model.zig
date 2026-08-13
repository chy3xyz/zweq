//! zent schema-as-code — 公众号自定义菜单。
//!
//! 每个公众号账号存一份菜单定义（按钮数组的 JSON blob），`publish` 时
//! 由 service 转换为 zwechat 的 Button 并调微信 `menu/create` 发布。

const zent = @import("zent");
const field = zent.core.field;
const Schema = zent.core.schema.Schema;

pub const WechatMenu = Schema("WechatMenu", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.String("menu_json").Default(""),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});
