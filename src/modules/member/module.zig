//! ZigModu module `member` — WeChat fans (粉丝).
const zigmodu = @import("zigmodu");

pub const info = zigmodu.api.Module{
    .name = "member",
    .description = "WeChat fans (openid/unionid, subscribe state)",
    .dependencies = &.{},
    .is_internal = false,
};

pub fn init() !void {}
pub fn deinit() void {}
