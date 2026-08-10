//! ZigModu module `module` — built-in module registry + account bindings.
const zigmodu = @import("zigmodu");

pub const info = zigmodu.api.Module{
    .name = "module",
    .description = "built-in module registry and per-account bindings",
    .dependencies = &.{},
    .is_internal = false,
};

pub fn init() !void {}
pub fn deinit() void {}
