//! ZigModu module `vote` — 投票。
const zigmodu = @import("zigmodu");

pub const info = zigmodu.api.Module{
    .name = "vote",
    .description = "投票",
    .dependencies = &.{ "audit", "message", "module", "user" },
    .is_internal = false,
};

pub fn init() !void {}
pub fn deinit() void {}
