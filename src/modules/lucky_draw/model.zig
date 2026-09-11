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
        // 天序号（Unix 秒 / 86400），与 checkin_day 同口径；由落库方写入。
        field.Int("draw_day").Default(0),
        field.String("prize_name").Default(""),
        field.Int("points").Default(0),
    },
    // 注意：此处刻意不加 (tenant_id, account_id, openid, draw_day) 唯一索引。
    // daily_limit 是租户可配字段（0=不限,可配 3 等 >1 值,见 LuckyDraw.tsx），
    // 行级唯一会把 daily_limit>1 的合法配置退化为每天 1 次。并发超限窗口由
    // service 层 count-then-create + 注释说明承接（见 service.zig draw）。
    .mixins = &.{zent.core.mixin.TimeMixin},
});
