//! zent schema-as-code — 素材库（图文 news + 图片/语音/视频 file）。
//!
//! `MaterialNews` mirrors a WeChat permanent news article; `MaterialFile`
//! tracks permanent media (image/voice/video) with its WeChat media_id.

const zent = @import("zent");
const field = zent.core.field;
const Schema = zent.core.schema.Schema;

pub const MaterialNews = Schema("MaterialNews", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.String("media_id").Default(""),
        field.String("title").Default(""),
        field.String("author").Default(""),
        field.String("digest").Default(""),
        field.String("content").Default(""),
        field.String("thumb_media_id").Default(""),
        field.String("thumb_url").Default(""),
        field.String("url").Default(""),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});

pub const MaterialFile = Schema("MaterialFile", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        // kind: image | voice | video
        field.String("kind").Default("image"),
        field.String("media_id").Default(""),
        field.String("url").Default(""),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});
