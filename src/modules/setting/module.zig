//! ZigModu module `setting` — tenant-scoped site settings (key-value).
const zigmodu = @import("zigmodu");

pub const info = zigmodu.api.Module{
    .name = "setting",
    .description = "site settings (tenant-scoped key-value)",
    .dependencies = &.{},
    .is_internal = false,
};

pub fn init() !void {}
pub fn deinit() void {}
