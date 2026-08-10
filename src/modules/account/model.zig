//! zent schema-as-code — WeEngine account domain for zweq.
//!
//! A site (tenant) hosts many platform accounts: 公众号 (wechat), 小程序
//! (wxapp), APP. `Account` is the generic row; `AccountWechat` carries the
//! 1:1 WeChat credential/config for 公众号/小程序 accounts.

const zent = @import("zent");
const field = zent.core.field;
const Schema = zent.core.schema.Schema;

pub const Account = Schema("Account", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.String("name"),
        // kind: wechat | wxapp | app
        field.String("kind").Default("wechat"),
        field.String("status").Default("active"),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});

pub const AccountWechat = Schema("AccountWechat", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.String("appid"),
        field.String("secret").Sensitive(),
        field.String("token"),
        field.String("encoding_aes_key").Sensitive(),
        field.Bool("verified").Default(false),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});
