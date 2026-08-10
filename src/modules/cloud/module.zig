//! ZigModu module `cloud` — site licenses + marketplace.
const zigmodu = @import("zigmodu");

pub const info = zigmodu.api.Module{
    .name = "cloud",
    .description = "site licenses (授权码) and module marketplace",
    .dependencies = &.{ "module" },
    .is_internal = false,
};

pub fn init() !void {}
pub fn deinit() void {}
