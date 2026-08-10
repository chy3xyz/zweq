//! ZigModu module `payment` — recharge orders, wallet, withdraws.
const zigmodu = @import("zigmodu");

pub const info = zigmodu.api.Module{
    .name = "payment",
    .description = "recharge orders, member wallet, withdraws",
    .dependencies = &.{},
    .is_internal = false,
};

pub fn init() !void {}
pub fn deinit() void {}
