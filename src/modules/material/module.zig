//! ZigModu module `material` — 素材库（图文 + 图片/语音/视频）。
const zigmodu = @import("zigmodu");

pub const info = zigmodu.api.Module{
    .name = "material",
    .description = "material library (news + image/voice/video)",
    .dependencies = &.{},
    .is_internal = false,
};

pub fn init() !void {}
pub fn deinit() void {}
