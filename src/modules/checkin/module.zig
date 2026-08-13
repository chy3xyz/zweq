//! ZigModu module `checkin` — 签到示例场景应用。
const zigmodu = @import("zigmodu");

pub const info = zigmodu.api.Module{
    .name = "checkin",
    .description = "签到场景应用（示例：消息接收器 + 模块配置）",
    .dependencies = &.{},
    .is_internal = false,
};

pub fn init() !void {}
pub fn deinit() void {}
