//! zent schema-as-code — 大转盘抽奖（lucky_draw）场景应用。
//!
//! 演示比 checkin 更完整的「场景应用」：奖品加权随机 + 每日次数限制 +
//! 积分消耗 + message 模块 Receiver 接入 + 前端管理。奖品配置存模块
//! config（JSON），中奖记录落 DrawRecord 表。

const zent = @import("zent");
const field = zent.core.field;
const Schema = zent.core.schema.Schema;

pub const DrawRecord = Schema("DrawRecord", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.String("openid"),
        field.String("prize_name").Default(""),
        field.Int("points").Default(0),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});
