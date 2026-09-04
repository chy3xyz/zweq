//! zent schema-as-code — WeChat fans (微擎 粉丝).
//!
//! One row per (account_id, openid). `subscribed` flips on 关注/取关 events.

const zent = @import("zent");
const field = zent.core.field;
const index = zent.core.index;
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
        field.Int("points").Default(0),
    },
    // UNIQUE (tenant_id, account_id, openid) — required for zent's
    // SaveOrUpdateOn atomic upsert; also prevents duplicate fan rows
    // when concurrent subscribe events race on the same openid.
    .indexes = &.{
        index.Fields(&.{ "tenant_id", "account_id", "openid" }).Unique(),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});

/// 粉丝标签（微信标签的本地镜像，wx_tag_id 为微信侧标签 id）。
pub const FanTag = Schema("FanTag", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.Int("wx_tag_id").Default(0),
        field.String("name").Default(""),
    },
    // UNIQUE (tenant_id, account_id, wx_tag_id) — required for zent's
    // SaveOrUpdateOn atomic upsert; also prevents duplicate tag rows
    // when concurrent /tags/get responses race.
    .indexes = &.{
        index.Fields(&.{ "tenant_id", "account_id", "wx_tag_id" }).Unique(),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});
