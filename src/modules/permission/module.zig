//! ZigModu module `permission` — roles, permission grants, user-role binding.
const zigmodu = @import("zigmodu");

pub const info = zigmodu.api.Module{
    .name = "permission",
    .description = "RBAC: roles, permission grants, user-role bindings",
    .dependencies = &.{},
    .is_internal = false,
};

pub fn init() !void {}
pub fn deinit() void {}
