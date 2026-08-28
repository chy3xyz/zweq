//! 共享测试夹具：全量 schema 图 + 内存 SQLite / 真 PG 打开器。
//! 各域测试文件通过 `t.xxx` 引用这里导出的名称。

pub const std = @import("std");
pub const zigmodu = @import("zigmodu");
pub const zent = @import("zent");
pub const zwechat = @import("zwechat");
pub const db_mod = @import("../db.zig");
pub const schema = @import("../schema.zig");
pub const user = @import("../modules/user/root.zig");
pub const auth = @import("../modules/auth/root.zig");
pub const task = @import("../modules/task/root.zig");
pub const file = @import("../modules/file/root.zig");
pub const notify = @import("../modules/notify/root.zig");
pub const tenant = @import("../modules/tenant/root.zig");
pub const audit = @import("../modules/audit/root.zig");
pub const mail_template = @import("../modules/mail_template/root.zig");
pub const ai = @import("../modules/ai/root.zig");
pub const account = @import("../modules/account/root.zig");
pub const permission = @import("../modules/permission/root.zig");
pub const setting = @import("../modules/setting/root.zig");
pub const rule = @import("../modules/rule/root.zig");
pub const member = @import("../modules/member/root.zig");
pub const message = @import("../modules/message/root.zig");
pub const appmod = @import("../modules/module/root.zig");
pub const payment = @import("../modules/payment/root.zig");
pub const cloud = @import("../modules/cloud/root.zig");
pub const material = @import("../modules/material/root.zig");
pub const checkin = @import("../modules/checkin/root.zig");
pub const lucky_draw = @import("../modules/lucky_draw/root.zig");
pub const coupon = @import("../modules/coupon/root.zig");
pub const vote = @import("../modules/vote/root.zig");
pub const seckill = @import("../modules/seckill/root.zig");
pub const member_card = @import("../modules/member_card/root.zig");
pub const distribution = @import("../modules/distribution/root.zig");
pub const shop = @import("../modules/shop/root.zig");
pub const menu = @import("../modules/menu/root.zig");
pub const points = @import("../modules/points/root.zig");
pub const cache_svc = @import("../services/cache.zig");
pub const mail = @import("../services/mail.zig");
pub const mw_rate = @import("../middleware/rate_limit.zig");

/// 全部 schema group（openMemory / openPostgres 共用）。
/// 注意：tuple 顺序即迁移顺序，新增模块时保持追加在末尾附近原有节奏。
pub const all_infos = .{
    tenant.persistence.infos,
    user.persistence.infos,
    task.persistence.infos,
    file.persistence.infos,
    notify.persistence.infos,
    audit.persistence.infos,
    mail_template.persistence.infos,
    ai.persistence.provider_infos,
    ai.persistence.session_infos,
    ai.persistence.message_infos,
    ai.persistence.approval_infos,
    ai.persistence.run_infos,
    account.persistence.infos,
    permission.persistence.infos,
    setting.persistence.infos,
    rule.persistence.infos,
    member.persistence.infos,
    message.persistence.infos,
    appmod.persistence.infos,
    payment.persistence.infos,
    cloud.persistence.infos,
    material.persistence.infos,
    checkin.persistence.infos,
    lucky_draw.persistence.infos,
    coupon.persistence.infos,
    vote.persistence.infos,
    seckill.persistence.infos,
    member_card.persistence.infos,
    distribution.persistence.infos,
    shop.persistence.infos,
    menu.persistence.infos,
    points.persistence.infos,
};

/// In-memory SQLite store with every schema group migrated.
pub fn openMemory(allocator: std.mem.Allocator) !db_mod.StoreEnv(schema.infos, all_infos) {
    return db_mod.StoreEnv(schema.infos, all_infos).open(allocator, .sqlite, ":memory:");
}

/// Real Postgres store（测试用，需 `ZWEQ_TEST_PG_CONNINFO` 环境变量）。
pub fn openPostgres(allocator: std.mem.Allocator, conninfo: []const u8) !db_mod.StoreEnv(schema.infos, all_infos) {
    return db_mod.StoreEnv(schema.infos, all_infos).open(allocator, .postgres, conninfo);
}
