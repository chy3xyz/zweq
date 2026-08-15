//! ZigModu module `member_card` — 会员卡。
const zigmodu = @import("zigmodu");

pub const info = zigmodu.api.Module{
    .name = "member_card",
    .description = "会员卡（卡等级 + 积分账户）",
    .dependencies = &.{},
    .is_internal = false,
};

pub fn init() !void {}
pub fn deinit() void {}
