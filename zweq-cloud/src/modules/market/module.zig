//! ZigModu module `market` — 应用市场。
const zigmodu = @import("zigmodu");

pub const info = zigmodu.api.Module{
    .name = "market",
    .description = "应用市场（包发布/校验/产物托管）",
    .dependencies = &.{},
    .is_internal = false,
};

pub fn init() !void {}
pub fn deinit() void {}
