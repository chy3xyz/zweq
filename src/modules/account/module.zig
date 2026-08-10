//! ZigModu module `account` — site accounts (公众号/小程序/APP) + WeChat config.
const zigmodu = @import("zigmodu");

pub const info = zigmodu.api.Module{
    .name = "account",
    .description = "site account management (wechat/wxapp/app) and WeChat credentials",
    .dependencies = &.{},
    .is_internal = false,
};

pub fn init() !void {}
pub fn deinit() void {}
