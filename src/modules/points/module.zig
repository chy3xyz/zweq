//! ZigModu module `points` — 积分商城（营销域）。
const zigmodu = @import("zigmodu");

pub const info = zigmodu.api.Module{
    .name = "points",
    .description = "积分商城（商品 + 兑换 + 积分）",
    .dependencies = &.{},
    .is_internal = false,
};

pub fn init() !void {}
pub fn deinit() void {}
