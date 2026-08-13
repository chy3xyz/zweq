//! ZigModu module `license` — 云服务授权码。
const zigmodu = @import("zigmodu");

pub const info = zigmodu.api.Module{
    .name = "license",
    .description = "云服务授权码（发行/校验/撤销）",
    .dependencies = &.{},
    .is_internal = false,
};

pub fn init() !void {}
pub fn deinit() void {}
