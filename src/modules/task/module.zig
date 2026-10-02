//! ZigModu module `task` — durable background task queue.
const zigmodu = @import("zigmodu");

pub const info = zigmodu.api.Module{
    .name = "task",
    .description = "durable background task queue (enqueue/claim/retry)",
    .dependencies = &.{ "audit", "user" },
    .is_internal = false,
};

pub fn init() !void {}
pub fn deinit() void {}
