//! ZigModu module `rule` — keyword auto-reply engine.
const zigmodu = @import("zigmodu");

pub const info = zigmodu.api.Module{
    .name = "rule",
    .description = "keyword auto-reply rules (rule/keyword/reply)",
    .dependencies = &.{},
    .is_internal = false,
};

pub fn init() !void {}
pub fn deinit() void {}
