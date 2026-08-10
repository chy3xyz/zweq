//! ZigModu module `app_bff` — H5 mobile BFF (thin routing, no own tables).
const zigmodu = @import("zigmodu");

pub const info = zigmodu.api.Module{
    .name = "app_bff",
    .description = "H5 mobile BFF — account/module entry points",
    .dependencies = &.{ "account", "module" },
    .is_internal = false,
};

pub fn init() !void {}
pub fn deinit() void {}
