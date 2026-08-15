//! ZigModu module `seckill` — 秒杀。
const zigmodu = @import("zigmodu");

pub const info = zigmodu.api.Module{
    .name = "seckill",
    .description = "秒杀（限时低价 + 限量抢购）",
    .dependencies = &.{},
    .is_internal = false,
};

pub fn init() !void {}
pub fn deinit() void {}
