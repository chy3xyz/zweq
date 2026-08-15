//! ZigModu module `distribution` — 分销。
const zigmodu = @import("zigmodu");

pub const info = zigmodu.api.Module{
    .name = "distribution",
    .description = "分销（三级分佣体系）",
    .dependencies = &.{},
    .is_internal = false,
};

pub fn init() !void {}
pub fn deinit() void {}
