//! Unit tests for zweq. DB-backed tests use an in-memory zent store;
//! HTTP-layer tests dispatch through zigmodu's Testkit without a socket.
//! Tenant tests cover default bootstrap, JWT aud binding and row isolation.
//!
//! 测试按域拆分在 src/tests/ 下；本文件只是聚合入口（Zig 会收集
//! 从这里可达的所有 test 块）。共享夹具见 tests/common.zig。

test {
    _ = @import("tests/core_test.zig");
    _ = @import("tests/user_test.zig");
    _ = @import("tests/platform_test.zig");
    _ = @import("tests/ai_test.zig");
    _ = @import("tests/wechat_test.zig");
    _ = @import("tests/marketing_test.zig");
    _ = @import("tests/payment_test.zig");
    _ = @import("tests/cloud_test.zig");
    _ = @import("tests/shop_core_test.zig");
    _ = @import("tests/shop_ops_test.zig");
}
