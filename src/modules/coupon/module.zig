//! ZigModu module `coupon` — 优惠券。
const zigmodu = @import("zigmodu");

pub const info = zigmodu.api.Module{
    .name = "coupon",
    .description = "优惠券（模板/领券/核销）",
    .dependencies = &.{},
    .is_internal = false,
};

pub fn init() !void {}
pub fn deinit() void {}
