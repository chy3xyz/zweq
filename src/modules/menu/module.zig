//! ZigModu module `menu` — 公众号自定义菜单。
const zigmodu = @import("zigmodu");

pub const info = zigmodu.api.Module{
    .name = "menu",
    .description = "公众号自定义菜单（保存/发布/删除）",
    .dependencies = &.{},
    .is_internal = false,
};

pub fn init() !void {}
pub fn deinit() void {}
