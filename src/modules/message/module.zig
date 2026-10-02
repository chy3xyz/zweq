//! ZigModu module `message` — WeChat server callback engine.
const zigmodu = @import("zigmodu");

pub const info = zigmodu.api.Module{
    .name = "message",
    .description = "WeChat server callback (signature/AES, fan sync, rule dispatch)",
    .dependencies = &.{ "account", "ai", "audit", "member", "module", "rule", "setting", "user" },
    .is_internal = false,
};

pub fn init() !void {}
pub fn deinit() void {}
