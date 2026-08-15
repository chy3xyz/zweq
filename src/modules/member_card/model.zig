//! zent schema-as-code — 会员卡（member_card）场景应用。
//!
//! 经典会员体系：卡等级（MemberCardLevel）+ 会员积分账户（MemberAccount）。
//! 公众号「办卡」开卡、「查卡」查积分/等级；积分可累计（消费/签到）与消耗
//! （兑换/抵扣）。

const zent = @import("zent");
const field = zent.core.field;
const Schema = zent.core.schema.Schema;

/// 卡等级。discount 为折扣（千分比，900=9折），points_ratio 积分倍率（100=1倍）。
pub const MemberCardLevel = Schema("MemberCardLevel", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.String("name"),
        field.Int("level").Default(1), // 等级序号
        field.Int("discount").Default(1000), // 千分比折扣
        field.Int("points_ratio").Default(100), // 积分倍率
        field.Int("threshold").Default(0), // 升级所需累计积分
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});

/// 会员积分账户（openid 唯一：一粉丝一卡）。
pub const MemberAccount = Schema("MemberAccount", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.String("openid"),
        field.Int("level_id").Default(0),
        field.Int("points").Default(0), // 积分余额
        field.Int("total_points").Default(0), // 累计获得积分（升级依据）
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});
