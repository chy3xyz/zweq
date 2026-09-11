//! zent schema-as-code — 签到（checkin）示例场景应用。
//!
//! 演示一个「场景应用」如何以编译期内置模块的形式接入 zweq：
//! 通过 module 注册表 + 账号绑定启用，通过 message 模块的 Receiver 钩子
//! 处理公众号消息。`checkin_day` 为「天序号」（Unix 秒 / 86400），避免
//! 时区/日期字符串差异，便于「当天仅一次」的幂等判断。

const zent = @import("zent");
const field = zent.core.field;
const index = zent.core.index;
const Schema = zent.core.schema.Schema;

pub const CheckinRecord = Schema("CheckinRecord", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.String("openid"),
        field.Int("checkin_day").Default(0),
        field.Int("points").Default(0),
    },
    .indexes = &.{
        // 当天仅一次签到：同租户/公众号/粉丝/天序号唯一；并发双写由唯一
        // 键冲突兜底为「今日已签」（service 将 UniqueViolation 映射为已签分支）。
        index.Fields(&.{ "tenant_id", "account_id", "openid", "checkin_day" }).Unique(),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});
