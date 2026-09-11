//! zent schema-as-code — 投票（vote）场景应用。
//!
//! 互动场景：投票主题（选项 JSON）+ 投票记录（防重：同 openid 同投票仅一票）
//! + 计票。公众号「投票」列出题目，回复「投N」投票。

const zent = @import("zent");
const field = zent.core.field;
const index = zent.core.index;
const Schema = zent.core.schema.Schema;

/// 投票主题。options_json = `["选项A","选项B",...]`。
pub const Vote = Schema("Vote", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.String("title"),
        field.String("options_json").Default("[]"),
        field.Int("end_at").Default(0), // 截止时间，0=不截止
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});

/// 投票记录（防重：openid + vote_id 唯一）。
pub const VoteRecord = Schema("VoteRecord", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.String("openid"),
        field.Int("vote_id"),
        field.Int("option_index").Default(0),
    },
    .indexes = &.{
        // 一人一票：同租户/投票/粉丝唯一；重复投票由唯一键冲突兜底为
        // AlreadyVoted（service 已做先查后插 + 冲突映射）。
        index.Fields(&.{ "tenant_id", "vote_id", "openid" }).Unique(),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});
