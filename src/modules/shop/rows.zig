//! 商城持久层行类型（Row / ListResult）——每个查询返回的 owned 数据，
//! 字符串字段由 allocator dupe，调用方负责 free()。

const std = @import("std");

// ── 行类型 ────────────────────────────────────────────────

pub const ShopCategoryRow = struct {
    id: i64,
    account_id: i64,
    name: []const u8,
    parent_id: i64,
    sort: i64,
    created_at: i64,

    pub fn free(self: ShopCategoryRow, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }
};

pub const ShopProductRow = struct {
    id: i64,
    account_id: i64,
    category_id: i64,
    name: []const u8,
    image: []const u8,
    content: []const u8,
    price: []const u8,
    original_price: []const u8,
    stock: i64,
    sales: i64,
    status: i64,
    created_at: i64,

    pub fn free(self: ShopProductRow, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.image);
        allocator.free(self.content);
        allocator.free(self.price);
        allocator.free(self.original_price);
    }
};

pub const ShopSkuRow = struct {
    id: i64,
    account_id: i64,
    product_id: i64,
    spec_json: []const u8,
    image: []const u8,
    price: []const u8,
    stock: i64,

    pub fn free(self: ShopSkuRow, allocator: std.mem.Allocator) void {
        allocator.free(self.spec_json);
        allocator.free(self.image);
        allocator.free(self.price);
    }
};

pub const CategoryListResult = struct {
    items: []ShopCategoryRow,
    total: i64,

    pub fn free(self: *CategoryListResult, allocator: std.mem.Allocator) void {
        for (self.items) |r| r.free(allocator);
        allocator.free(self.items);
    }
};

pub const ProductListResult = struct {
    items: []ShopProductRow,
    total: i64,

    pub fn free(self: *ProductListResult, allocator: std.mem.Allocator) void {
        for (self.items) |r| r.free(allocator);
        allocator.free(self.items);
    }
};

// ── Store ─────────────────────────────────────────────────

// ── 交易行类型 ────────────────────────────────────────────

pub const ShopCartRow = struct {
    id: i64,
    account_id: i64,
    openid: []const u8,
    product_id: i64,
    sku_id: i64,
    quantity: i64,
    created_at: i64,

    pub fn free(self: ShopCartRow, allocator: std.mem.Allocator) void {
        allocator.free(self.openid);
    }
};

pub const ShopAddressRow = struct {
    id: i64,
    account_id: i64,
    openid: []const u8,
    name: []const u8,
    mobile: []const u8,
    region: []const u8,
    detail: []const u8,
    is_default: i64,
    created_at: i64,

    pub fn free(self: ShopAddressRow, allocator: std.mem.Allocator) void {
        allocator.free(self.openid);
        allocator.free(self.name);
        allocator.free(self.mobile);
        allocator.free(self.region);
        allocator.free(self.detail);
    }
};

pub const ShopOrderRow = struct {
    id: i64,
    account_id: i64,
    order_no: []const u8,
    client_trade_no: []const u8,
    openid: []const u8,
    total_amount: []const u8,
    pay_amount: []const u8,
    status: i64,
    address_json: []const u8,
    express_company: []const u8,
    express_no: []const u8,
    paid_at: i64,
    pickup_type: []const u8,
    pickup_code: []const u8,
    store_id: i64,
    groupon_team_id: i64,
    created_at: i64,

    pub fn free(self: ShopOrderRow, allocator: std.mem.Allocator) void {
        allocator.free(self.order_no);
        allocator.free(self.client_trade_no);
        allocator.free(self.openid);
        allocator.free(self.total_amount);
        allocator.free(self.pay_amount);
        allocator.free(self.address_json);
        allocator.free(self.express_company);
        allocator.free(self.express_no);
        allocator.free(self.pickup_type);
        allocator.free(self.pickup_code);
    }
};

pub const ShopOrderProductRow = struct {
    id: i64,
    order_id: i64,
    product_id: i64,
    sku_id: i64,
    name: []const u8,
    image: []const u8,
    spec_json: []const u8,
    price: []const u8,
    quantity: i64,
    created_at: i64,

    pub fn free(self: ShopOrderProductRow, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.image);
        allocator.free(self.spec_json);
        allocator.free(self.price);
    }
};

pub const OrderListResult = struct {
    items: []ShopOrderRow,
    total: i64,

    pub fn free(self: *OrderListResult, allocator: std.mem.Allocator) void {
        for (self.items) |r| r.free(allocator);
        allocator.free(self.items);
    }
};

pub const ShopRefundRow = struct {
    id: i64,
    account_id: i64,
    order_id: i64,
    openid: []const u8,
    reason: []const u8,
    amount: []const u8,
    status: i64,
    created_at: i64,

    pub fn free(self: ShopRefundRow, allocator: std.mem.Allocator) void {
        allocator.free(self.openid);
        allocator.free(self.reason);
        allocator.free(self.amount);
    }
};

pub const ShopCommentRow = struct {
    id: i64,
    account_id: i64,
    order_product_id: i64,
    product_id: i64,
    openid: []const u8,
    star: i64,
    content: []const u8,
    created_at: i64,

    pub fn free(self: ShopCommentRow, allocator: std.mem.Allocator) void {
        allocator.free(self.openid);
        allocator.free(self.content);
    }
};

pub const RefundListResult = struct {
    items: []ShopRefundRow,
    total: i64,

    pub fn free(self: *RefundListResult, allocator: std.mem.Allocator) void {
        for (self.items) |r| r.free(allocator);
        allocator.free(self.items);
    }
};

pub const ShopFavoriteRow = struct {
    id: i64,
    account_id: i64,
    openid: []const u8,
    product_id: i64,
    created_at: i64,

    pub fn free(self: ShopFavoriteRow, allocator: std.mem.Allocator) void {
        allocator.free(self.openid);
    }
};

pub const ShopOutletRow = struct {
    id: i64,
    account_id: i64,
    name: []const u8,
    address: []const u8,
    mobile: []const u8,
    status: i64,
    created_at: i64,

    pub fn free(self: ShopOutletRow, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.address);
        allocator.free(self.mobile);
    }
};

pub const ShopBalancePlanRow = struct {
    id: i64,
    account_id: i64,
    name: []const u8,
    amount: []const u8,
    bonus: []const u8,
    status: i64,
    created_at: i64,

    pub fn free(self: ShopBalancePlanRow, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.amount);
        allocator.free(self.bonus);
    }
};

pub const ShopGrouponRow = struct {
    id: i64,
    account_id: i64,
    product_id: i64,
    group_price: []const u8,
    group_size: i64,
    start_at: i64,
    end_at: i64,
    status: i64,
    created_at: i64,

    pub fn free(self: ShopGrouponRow, allocator: std.mem.Allocator) void {
        allocator.free(self.group_price);
    }
};

pub const ShopGrouponTeamRow = struct {
    id: i64,
    account_id: i64,
    activity_id: i64,
    leader_openid: []const u8,
    current: i64,
    status: i64,
    created_at: i64,

    pub fn free(self: ShopGrouponTeamRow, allocator: std.mem.Allocator) void {
        allocator.free(self.leader_openid);
    }
};

pub const ShopInviteGiftRow = struct {
    id: i64,
    account_id: i64,
    target_count: i64,
    reward_type: []const u8,
    reward_value: i64,
    status: i64,
    created_at: i64,

    pub fn free(self: ShopInviteGiftRow, allocator: std.mem.Allocator) void {
        allocator.free(self.reward_type);
    }
};

pub const ShopInviteRecordRow = struct {
    id: i64,
    account_id: i64,
    inviter_openid: []const u8,
    invitee_openid: []const u8,
    created_at: i64,

    pub fn free(self: ShopInviteRecordRow, allocator: std.mem.Allocator) void {
        allocator.free(self.inviter_openid);
        allocator.free(self.invitee_openid);
    }
};

pub const ShopArticleRow = struct {
    id: i64,
    account_id: i64,
    title: []const u8,
    content: []const u8,
    status: i64,
    created_at: i64,

    pub fn free(self: ShopArticleRow, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
        allocator.free(self.content);
    }
};

pub const ArticleListResult = struct {
    items: []ShopArticleRow,
    total: i64,

    pub fn free(self: *ArticleListResult, allocator: std.mem.Allocator) void {
        for (self.items) |r| r.free(allocator);
        allocator.free(self.items);
    }
};

pub const ShopWebhookRow = struct {
    id: i64,
    account_id: i64,
    url: []const u8,
    events: []const u8,
    status: i64,
    created_at: i64,

    pub fn free(self: ShopWebhookRow, allocator: std.mem.Allocator) void {
        allocator.free(self.url);
        allocator.free(self.events);
    }
};
