//! services/wire.zig — 启动后装配（post-init wiring）。
//!
//! Extracts the cross-service wiring that used to be scattered through
//! main.zig's bootstrap into one function, so `main()` stays focused on
//! construction/lifecycle while the pointer-field assignments, setter calls,
//! license injection, and WeChat module receiver registrations live in a
//! single, order-explicit place.
//!
//! Every store/service is constructed in main()'s scope and injected here as
//! a pointer — nothing here is heap-allocated and nothing outlives main().
//! The receiver `ReceiverCtx` storage also lives in main()'s frame (its
//! address is retained by the WeChat callback engine for the whole process),
//! so the helper fills those structs in place rather than boxing them.

const std = @import("std");
const zwechat = @import("zwechat");
const zent = @import("zent");

const cache = @import("cache.zig");
const account = @import("../modules/account/root.zig");
const member = @import("../modules/member/root.zig");
const setting = @import("../modules/setting/root.zig");
const appmod = @import("../modules/module/root.zig");
const cloud = @import("../modules/cloud/root.zig");
const message = @import("../modules/message/root.zig");
const ai = @import("../modules/ai/root.zig");
const checkin = @import("../modules/checkin/root.zig");
const lucky_draw = @import("../modules/lucky_draw/root.zig");
const coupon = @import("../modules/coupon/root.zig");
const vote = @import("../modules/vote/root.zig");
const seckill = @import("../modules/seckill/root.zig");
const member_card = @import("../modules/member_card/root.zig");
const distribution = @import("../modules/distribution/root.zig");

/// Aggregated pointer params for [`WireServices`]. Deliberately holds pointers
/// (and small value params) — never owned store/service values — so main()
/// keeps every store/service on its own stack frame.
pub const Env = struct {
    allocator: std.mem.Allocator,
    default_tenant_id: i64,
    account_svc: *account.service.AccountService,
    member_svc: *member.service.MemberService,
    tag_store: *member.persistence.TagStore,
    setting_svc: *setting.service.SettingService,
    module_svc: *appmod.service.ModuleService,
    cache: *cache.CacheService,
    token_cache: *zwechat.cache.Memory,
    cloud_svc: *cloud.service.CloudService,
    driver: zent.sql_driver.Driver,
    dyn_table_store: *cloud.persistence.DynamicTableStore,
    wechat_svc: *message.service.WechatService,
    ai_svc: *ai.service.AiService,
    checkin_svc: *checkin.service.CheckinService,
    checkin_ctx: *checkin.service.ReceiverCtx,
    lucky_draw_svc: *lucky_draw.service.DrawService,
    lucky_draw_ctx: *lucky_draw.service.ReceiverCtx,
    coupon_svc: *coupon.service.CouponService,
    coupon_ctx: *coupon.service.ReceiverCtx,
    vote_svc: *vote.service.VoteService,
    vote_ctx: *vote.service.ReceiverCtx,
    seckill_svc: *seckill.service.SeckillService,
    seckill_ctx: *seckill.service.ReceiverCtx,
    member_card_svc: *member_card.service.MemberCardService,
    member_card_ctx: *member_card.service.ReceiverCtx,
    distribution_svc: *distribution.service.DistributionService,
    distribution_ctx: *distribution.service.ReceiverCtx,
};

/// Perform the cross-service post-init wiring. Called exactly once from
/// main()'s bootstrap after every store/service is constructed.
///
/// Order matters and is preserved from the original bootstrap:
/// 1. member ↔ account/tag wiring
/// 2. WeChat callback engine: module registry + nonce-lookup cache
/// 3. cloud: raw-SQL driver + dynamic-table metadata store
/// 4. site license: key/grace injected BEFORE `checkSiteLicense()`
/// 5. shared access_token cache wired into wechat + member
/// 6. module receivers registered in fixed order
/// 7. AI assistant wired into the callback engine
pub fn WireServices(io: std.Io, env: Env) !void {
    // ── member ↔ account/tag wiring ──
    env.member_svc.tag_store = env.tag_store;
    env.member_svc.account_svc = env.account_svc;

    // ── WeChat callback engine: module registry + nonce replay cache ──
    env.wechat_svc.module_svc = env.module_svc;
    env.wechat_svc.cache = env.cache;

    // ── cloud: raw-SQL executor + dynamic-table metadata (market manifest) ──
    env.cloud_svc.setDriver(env.driver);
    env.cloud_svc.setDynamicTableStore(env.dyn_table_store);

    // ── site license 注入 + 启动即校验（远端 fail-closed + 宽限期）──
    if (env.setting_svc.get(env.default_tenant_id, "cloud_license_key") catch null) |row| {
        defer row.free(env.allocator);
        try env.cloud_svc.setSiteLicenseKey(row.value);
    }
    if (env.setting_svc.get(env.default_tenant_id, "cloud_license_grace_days") catch null) |grow| {
        defer grow.free(env.allocator);
        env.cloud_svc.setGraceDays(std.fmt.parseInt(i64, grow.value, 10) catch 7);
    }
    env.cloud_svc.checkSiteLicense();

    // ── shared access_token cache（主动微信能力地基：菜单 + 素材同步共用）──
    env.wechat_svc.token_cache = env.token_cache;
    env.member_svc.token_cache = env.token_cache;

    // ── bind WeChat module receivers（固定顺序，与原始 bootstrap 一致）──
    env.checkin_ctx.* = .{
        .module_svc = env.module_svc,
        .checkin_svc = env.checkin_svc,
        .io = io,
    };
    try env.wechat_svc.registerReceiver(.{
        .module_name = "checkin",
        .ctx = env.checkin_ctx,
        .handle = checkin.service.receiverHandle,
    });

    env.lucky_draw_ctx.* = .{
        .module_svc = env.module_svc,
        .draw_svc = env.lucky_draw_svc,
        .io = io,
    };
    try env.wechat_svc.registerReceiver(.{
        .module_name = "lucky_draw",
        .ctx = env.lucky_draw_ctx,
        .handle = lucky_draw.service.receiverHandle,
    });

    env.coupon_ctx.* = .{
        .module_svc = env.module_svc,
        .coupon_svc = env.coupon_svc,
        .io = io,
    };
    try env.wechat_svc.registerReceiver(.{
        .module_name = "coupon",
        .ctx = env.coupon_ctx,
        .handle = coupon.service.receiverHandle,
    });

    env.vote_ctx.* = .{
        .module_svc = env.module_svc,
        .vote_svc = env.vote_svc,
        .io = io,
    };
    try env.wechat_svc.registerReceiver(.{
        .module_name = "vote",
        .ctx = env.vote_ctx,
        .handle = vote.service.receiverHandle,
    });

    env.seckill_ctx.* = .{
        .io = io,
        .seckill_svc = env.seckill_svc,
    };
    try env.wechat_svc.registerReceiver(.{
        .module_name = "seckill",
        .ctx = env.seckill_ctx,
        .handle = seckill.service.receiverHandle,
    });

    env.member_card_ctx.* = .{
        .io = io,
        .member_svc = env.member_card_svc,
    };
    try env.wechat_svc.registerReceiver(.{
        .module_name = "member_card",
        .ctx = env.member_card_ctx,
        .handle = member_card.service.receiverHandle,
    });

    env.distribution_ctx.* = .{
        .io = io,
        .dist_svc = env.distribution_svc,
    };
    try env.wechat_svc.registerReceiver(.{
        .module_name = "distribution",
        .ctx = env.distribution_ctx,
        .handle = distribution.service.receiverHandle,
    });

    // ── wire AI assistant into the WeChat callback engine (AI auto-reply) ──
    env.wechat_svc.ai_svc = env.ai_svc;
}
