//! Barrel re-exports for module `app_bff` (BFF: no model/persistence).
pub const api = @import("api.zig");
pub const fan_api = @import("fan_api.zig");
pub const fan_scene_api = @import("fan_scene_api.zig");
pub const module = @import("module.zig");
