//! ZigModu module `lucky_draw` — 大转盘抽奖。
const zigmodu = @import("zigmodu");

pub const info = zigmodu.api.Module{
    .name = "lucky_draw",
    .description = "大转盘抽奖",
    .dependencies = &.{ "audit", "message", "module", "user" },
    .is_internal = false,
};

pub fn init() !void {}
pub fn deinit() void {}
