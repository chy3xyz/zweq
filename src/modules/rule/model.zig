//! zent schema-as-code — keyword auto-reply rules (微擎 自动回复).
//!
//! A Rule groups one or more keywords; matching a keyword returns the
//! rule's first reply (text or news). Mirrors WeEngine `ims_rule` +
//! `ims_rule_keyword` + `ims_rule_reply`.

const zent = @import("zent");
const field = zent.core.field;
const Schema = zent.core.schema.Schema;

pub const Rule = Schema("Rule", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.String("name"),
        field.String("status").Default("active"),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});

pub const RuleKeyword = Schema("RuleKeyword", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.Int("rule_id"),
        // match: full | contain
        field.String("keyword"),
        field.String("match_type").Default("contain"),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});

pub const RuleReply = Schema("RuleReply", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.Int("rule_id"),
        // type: text | news
        field.String("reply_type").Default("text"),
        field.String("content").Default(""),
        field.String("news_title").Default(""),
        field.String("news_description").Default(""),
        field.String("news_pic_url").Default(""),
        field.String("news_url").Default(""),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});
