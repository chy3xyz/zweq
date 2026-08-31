//! Compile-time admin sidebar catalog (WeQ-style module grouping).
//! Filtered at runtime by RBAC + optional per-account module bindings.

pub const NavItem = struct {
    /// Owning module name; empty = platform/core (always available when permitted).
    module: []const u8,
    /// Top-level sidebar group, e.g. 系统 / 公众号 / 应用.
    group: []const u8,
    /// Optional second level under group (基础配置 / 业务功能).
    subgroup: []const u8,
    href: []const u8,
    label: []const u8,
    permission: []const u8,
    order: u16,
    /// When true, item is hidden unless `module` is active on the selected account.
    account_scoped: bool,
};

pub const items = [_]NavItem{
    // ── 系统 ─────────────────────────────────────────────
    .{ .module = "system", .group = "系统", .subgroup = "概览", .href = "/dashboard", .label = "控制台", .permission = "system:read", .order = 10, .account_scoped = false },
    .{ .module = "user", .group = "系统", .subgroup = "基础配置", .href = "/users", .label = "用户管理", .permission = "user:read", .order = 20, .account_scoped = false },
    .{ .module = "permission", .group = "系统", .subgroup = "基础配置", .href = "/roles", .label = "角色权限", .permission = "permission:read", .order = 30, .account_scoped = false },
    .{ .module = "tenant", .group = "系统", .subgroup = "基础配置", .href = "/tenants", .label = "租户管理", .permission = "tenant:read", .order = 40, .account_scoped = false },
    .{ .module = "task", .group = "系统", .subgroup = "运维", .href = "/tasks", .label = "任务中心", .permission = "task:read", .order = 50, .account_scoped = false },
    .{ .module = "audit", .group = "系统", .subgroup = "运维", .href = "/audit-logs", .label = "审计日志", .permission = "audit:read", .order = 60, .account_scoped = false },
    .{ .module = "mail_template", .group = "系统", .subgroup = "运维", .href = "/mail-templates", .label = "邮件模板", .permission = "mail_template:read", .order = 70, .account_scoped = false },
    .{ .module = "ai", .group = "系统", .subgroup = "工具", .href = "/ai-admin", .label = "AI 管理", .permission = "ai:read", .order = 80, .account_scoped = false },
    .{ .module = "ai", .group = "系统", .subgroup = "工具", .href = "/ai-chat", .label = "AI 助手", .permission = "ai:read", .order = 90, .account_scoped = false },
    .{ .module = "user", .group = "系统", .subgroup = "工具", .href = "/files", .label = "文件管理", .permission = "user:read", .order = 100, .account_scoped = false },

    // ── 平台 ─────────────────────────────────────────────
    .{ .module = "account", .group = "平台", .subgroup = "基础配置", .href = "/accounts", .label = "账号管理", .permission = "account:read", .order = 110, .account_scoped = false },
    .{ .module = "module", .group = "平台", .subgroup = "基础配置", .href = "/modules", .label = "模块管理", .permission = "module:read", .order = 120, .account_scoped = false },
    .{ .module = "cloud", .group = "平台", .subgroup = "云服务", .href = "/cloud", .label = "授权与市场", .permission = "cloud:read", .order = 130, .account_scoped = false },
    .{ .module = "payment", .group = "平台", .subgroup = "资金", .href = "/payments", .label = "充值支付", .permission = "payment:read", .order = 140, .account_scoped = false },

    // ── 公众号（按当前账号）──────────────────────────────
    .{ .module = "rule", .group = "公众号", .subgroup = "基础配置", .href = "/rules", .label = "自动回复", .permission = "rule:read", .order = 210, .account_scoped = true },
    .{ .module = "member", .group = "公众号", .subgroup = "粉丝", .href = "/fans", .label = "粉丝管理", .permission = "member:read", .order = 220, .account_scoped = true },
    .{ .module = "message", .group = "公众号", .subgroup = "消息", .href = "/logs", .label = "消息日志", .permission = "message:read", .order = 230, .account_scoped = true },
    .{ .module = "material", .group = "公众号", .subgroup = "内容", .href = "/materials", .label = "素材库", .permission = "material:read", .order = 240, .account_scoped = true },
    .{ .module = "menu", .group = "公众号", .subgroup = "内容", .href = "/menu", .label = "自定义菜单", .permission = "menu:read", .order = 250, .account_scoped = true },

    // ── 应用模块（按账号绑定）────────────────────────────
    .{ .module = "checkin", .group = "应用", .subgroup = "营销", .href = "/checkin", .label = "签到", .permission = "checkin:read", .order = 310, .account_scoped = true },
    .{ .module = "lucky_draw", .group = "应用", .subgroup = "营销", .href = "/lucky-draw", .label = "大转盘", .permission = "lucky_draw:read", .order = 320, .account_scoped = true },
    .{ .module = "coupon", .group = "应用", .subgroup = "营销", .href = "/coupon", .label = "优惠券", .permission = "coupon:read", .order = 330, .account_scoped = true },
    .{ .module = "vote", .group = "应用", .subgroup = "营销", .href = "/vote", .label = "投票", .permission = "vote:read", .order = 340, .account_scoped = true },
    .{ .module = "seckill", .group = "应用", .subgroup = "营销", .href = "/seckill", .label = "秒杀", .permission = "seckill:read", .order = 350, .account_scoped = true },
    .{ .module = "member_card", .group = "应用", .subgroup = "会员", .href = "/member-card", .label = "会员卡", .permission = "member_card:read", .order = 360, .account_scoped = true },
    .{ .module = "distribution", .group = "应用", .subgroup = "会员", .href = "/distribution", .label = "分销", .permission = "distribution:read", .order = 370, .account_scoped = true },
    .{ .module = "points", .group = "应用", .subgroup = "积分", .href = "/points", .label = "积分商城", .permission = "points:read", .order = 380, .account_scoped = true },

    // ── 商城 ─────────────────────────────────────────────
    .{ .module = "shop", .group = "商城", .subgroup = "商品", .href = "/shop", .label = "商品管理", .permission = "shop:read", .order = 410, .account_scoped = true },
    .{ .module = "shop", .group = "商城", .subgroup = "交易", .href = "/shop/orders", .label = "订单管理", .permission = "shop:read", .order = 420, .account_scoped = true },
    .{ .module = "shop", .group = "商城", .subgroup = "运营", .href = "/shop/admin", .label = "商城运营", .permission = "shop:write", .order = 430, .account_scoped = true },
};
