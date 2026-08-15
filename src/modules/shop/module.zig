//! ZigModu module `shop` — 商城。
const zigmodu = @import("zigmodu");

pub const info = zigmodu.api.Module{
    .name = "shop",
    .description = "商城（商品/购物车/订单/退款）",
    .dependencies = &.{},
    .is_internal = false,
};

pub fn init() !void {}
pub fn deinit() void {}
