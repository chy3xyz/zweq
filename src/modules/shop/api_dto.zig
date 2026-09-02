//! api 层请求/响应 DTO 与行→DTO 映射器（拆分自原 api.zig 尾部簇）。

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const mw = @import("../../middleware/auth.zig");
const mw_rate = @import("../../middleware/rate_limit.zig");
const user_svc = @import("../user/service.zig");
const audit_svc = @import("../audit/service.zig");
const member_persist = @import("../member/persistence.zig");
const setting_store_mod = @import("../setting/persistence.zig");
const payment_service = @import("../payment/service.zig");
const service = @import("service.zig");

// 全部 decl 均 pub，宿主与各 handler 片段按名引用（原作用域不变）。

pub const RefundApplyReq = struct {
    account_id: i64,
    order_id: i64,
    openid: []const u8,
    reason: []const u8,
};

pub const CommentReq = struct {
    account_id: i64,
    order_product_id: i64,
    product_id: i64,
    openid: []const u8,
    star: i64 = 5,
    content: []const u8 = "",
};

pub const RefundAuditReq = struct {
    order_id: i64,
    approve: bool,
};

pub const RefundDto = struct {
    id: i64,
    account_id: i64,
    order_id: i64,
    openid: []const u8,
    reason: []const u8,
    amount: i64,
    status: i64,
    created_at: i64,
};

pub fn toRefundDto(row: service.ShopRefundRow) RefundDto {
    return .{
        .id = row.id,
        .account_id = row.account_id,
        .order_id = row.order_id,
        .openid = row.openid,
        .reason = row.reason,
        .amount = std.fmt.parseInt(i64, row.amount, 10) catch 0,
        .status = row.status,
        .created_at = row.created_at,
    };
}

pub const CommentDto = struct {
    id: i64,
    product_id: i64,
    openid: []const u8,
    star: i64,
    content: []const u8,
    created_at: i64,
};

pub fn toCommentDto(row: service.ShopCommentRow) CommentDto {
    return .{ .id = row.id, .product_id = row.product_id, .openid = row.openid, .star = row.star, .content = row.content, .created_at = row.created_at };
}

pub const FavoriteReq = struct {
    account_id: i64,
    openid: []const u8,
    product_id: i64,
};

pub const FavoriteDto = struct {
    id: i64,
    openid: []const u8,
    product_id: i64,
    created_at: i64,
};

pub fn toFavoriteDto(row: service.ShopFavoriteRow) FavoriteDto {
    return .{ .id = row.id, .openid = row.openid, .product_id = row.product_id, .created_at = row.created_at };
}

pub const OutletReq = struct {
    account_id: i64,
    name: []const u8,
    address: []const u8 = "",
    mobile: []const u8 = "",
};

pub const PickupReq = struct {
    code: []const u8,
};

pub const OutletDto = struct {
    id: i64,
    account_id: i64,
    name: []const u8,
    address: []const u8,
    mobile: []const u8,
    status: i64,
};

pub fn toOutletDto(row: service.ShopOutletRow) OutletDto {
    return .{ .id = row.id, .account_id = row.account_id, .name = row.name, .address = row.address, .mobile = row.mobile, .status = row.status };
}

pub const PlanReq = struct {
    account_id: i64,
    name: []const u8,
    amount: i64,
    bonus: i64 = 0,
};

pub const RechargeReq = struct {
    account_id: i64,
    openid: []const u8,
};

pub const PlanDto = struct {
    id: i64,
    account_id: i64,
    name: []const u8,
    amount: i64,
    bonus: i64,
    status: i64,
};

pub fn toPlanDto(row: service.ShopBalancePlanRow) PlanDto {
    return .{
        .id = row.id,
        .account_id = row.account_id,
        .name = row.name,
        .amount = std.fmt.parseInt(i64, row.amount, 10) catch 0,
        .bonus = std.fmt.parseInt(i64, row.bonus, 10) catch 0,
        .status = row.status,
    };
}

pub const GrouponReq = struct {
    account_id: i64,
    product_id: i64,
    group_price: i64,
    group_size: i64 = 2,
    start_at: i64 = 0,
    end_at: i64 = 0,
};

pub const GrouponOpenReq = struct {
    account_id: i64,
    openid: []const u8,
    address_id: i64,
    sku_id: i64,
};

pub const GrouponJoinReq = struct {
    account_id: i64,
    openid: []const u8,
    address_id: i64,
    sku_id: i64,
};

pub const GrouponDto = struct {
    id: i64,
    account_id: i64,
    product_id: i64,
    group_price: i64,
    group_size: i64,
    status: i64,
};

pub fn toGrouponDto(row: service.ShopGrouponRow) GrouponDto {
    return .{
        .id = row.id,
        .account_id = row.account_id,
        .product_id = row.product_id,
        .group_price = std.fmt.parseInt(i64, row.group_price, 10) catch 0,
        .group_size = row.group_size,
        .status = row.status,
    };
}

pub const InviteGiftReq = struct {
    account_id: i64,
    target_count: i64,
    reward_type: []const u8,
    reward_value: i64,
};

pub const InviteBindReq = struct {
    account_id: i64,
    inviter_openid: []const u8,
    invitee_openid: []const u8,
};

pub const InviteGiftDto = struct {
    id: i64,
    account_id: i64,
    target_count: i64,
    reward_type: []const u8,
    reward_value: i64,
};

pub fn toInviteGiftDto(row: service.ShopInviteGiftRow) InviteGiftDto {
    return .{ .id = row.id, .account_id = row.account_id, .target_count = row.target_count, .reward_type = row.reward_type, .reward_value = row.reward_value };
}

pub const ArticleReq = struct {
    account_id: i64,
    title: []const u8,
    content: []const u8 = "",
};

pub const ArticleDto = struct {
    id: i64,
    account_id: i64,
    title: []const u8,
    content: []const u8,
    status: i64,
    created_at: i64,
};

pub fn toArticleDto(row: service.ShopArticleRow) ArticleDto {
    return .{ .id = row.id, .account_id = row.account_id, .title = row.title, .content = row.content, .status = row.status, .created_at = row.created_at };
}

pub const AssistantReq = struct {
    account_id: i64,
    openid: []const u8,
    question: []const u8,
};

pub const WebhookReq = struct {
    account_id: i64,
    url: []const u8,
    events: []const u8 = "order.paid",
};

pub const WebhookDto = struct {
    id: i64,
    account_id: i64,
    url: []const u8,
    events: []const u8,
    status: i64,
};

pub fn toWebhookDto(row: service.ShopWebhookRow) WebhookDto {
    return .{ .id = row.id, .account_id = row.account_id, .url = row.url, .events = row.events, .status = row.status };
}

pub const CLoginReq = struct {
    account_id: i64,
    openid: []const u8,
};

pub const CartAddReq = struct {
    openid: []const u8,
    product_id: i64,
    sku_id: i64,
    quantity: i64 = 1,
};

pub const AddressReq = struct {
    openid: []const u8,
    name: []const u8,
    mobile: []const u8,
    region: []const u8,
    detail: []const u8,
    is_default: i64 = 0,
};

pub const OrderItemReq = service.OrderItemInput;

pub const OrderCreateReq = struct {
    account_id: i64,
    openid: []const u8,
    address_id: i64,
    items: []const OrderItemReq,
    coupon_code: []const u8 = "",
    client_trade_no: []const u8 = "",
    pay_type: []const u8 = "",
    pickup_store_id: i64 = 0,
    remark: []const u8 = "",
};

pub const ShipReq = struct {
    company: []const u8,
    no: []const u8,
};

pub const CartDto = struct {
    id: i64,
    openid: []const u8,
    product_id: i64,
    sku_id: i64,
    quantity: i64,
    created_at: i64,
};

pub fn toCartDto(row: service.ShopCartRow) CartDto {
    return .{ .id = row.id, .openid = row.openid, .product_id = row.product_id, .sku_id = row.sku_id, .quantity = row.quantity, .created_at = row.created_at };
}

pub const AddressDto = struct {
    id: i64,
    openid: []const u8,
    name: []const u8,
    mobile: []const u8,
    region: []const u8,
    detail: []const u8,
    is_default: i64,
};

pub fn toAddressDto(row: service.ShopAddressRow) AddressDto {
    return .{ .id = row.id, .openid = row.openid, .name = row.name, .mobile = row.mobile, .region = row.region, .detail = row.detail, .is_default = row.is_default };
}

pub const OrderSummaryDto = struct {
    order_id: i64,
    cover_image: []const u8,
    item_count: i64,
    summary: []const u8,
};

pub const OrderDto = struct {
    id: i64,
    account_id: i64,
    order_no: []const u8,
    openid: []const u8,
    total_amount: i64,
    pay_amount: i64,
    status: i64,
    address_json: []const u8,
    express_company: []const u8,
    express_no: []const u8,
    pickup_type: []const u8,
    pickup_code: []const u8,
    store_id: i64,
    paid_at: i64,
    created_at: i64,
};

pub fn toOrderDto(row: service.ShopOrderRow) OrderDto {
    return .{
        .id = row.id,
        .account_id = row.account_id,
        .order_no = row.order_no,
        .openid = row.openid,
        .total_amount = std.fmt.parseInt(i64, row.total_amount, 10) catch 0,
        .pay_amount = std.fmt.parseInt(i64, row.pay_amount, 10) catch 0,
        .status = row.status,
        .address_json = row.address_json,
        .express_company = row.express_company,
        .express_no = row.express_no,
        .pickup_type = row.pickup_type,
        .pickup_code = row.pickup_code,
        .store_id = row.store_id,
        .paid_at = row.paid_at,
        .created_at = row.created_at,
    };
}

pub const OrderProductDto = struct {
    id: i64,
    order_id: i64,
    product_id: i64,
    sku_id: i64,
    name: []const u8,
    image: []const u8,
    spec_json: []const u8,
    price: i64,
    quantity: i64,
    created_at: i64,
};

pub fn toOrderProductDto(row: service.ShopOrderProductRow) OrderProductDto {
    return .{
        .id = row.id,
        .order_id = row.order_id,
        .product_id = row.product_id,
        .sku_id = row.sku_id,
        .name = row.name,
        .image = row.image,
        .spec_json = row.spec_json,
        .price = std.fmt.parseInt(i64, row.price, 10) catch 0,
        .quantity = row.quantity,
        .created_at = row.created_at,
    };
}

// —— 原文件顶部簇（Catalog/Product/SKU）——
pub const CategoryDto = struct {
    id: i64,
    account_id: i64,
    name: []const u8,
    parent_id: i64,
    sort: i64,
};

pub fn toCategoryDto(row: service.ShopCategoryRow) CategoryDto {
    return .{
        .id = row.id,
        .account_id = row.account_id,
        .name = row.name,
        .parent_id = row.parent_id,
        .sort = row.sort,
    };
}

pub const ProductDto = struct {
    id: i64,
    account_id: i64,
    category_id: i64,
    name: []const u8,
    image: []const u8,
    images: []const u8,
    content: []const u8,
    price: i64,
    original_price: i64,
    stock: i64,
    sales: i64,
    status: i64,
    created_at: i64,
};

pub fn toProductDto(row: service.ShopProductRow) ProductDto {
    return .{
        .id = row.id,
        .account_id = row.account_id,
        .category_id = row.category_id,
        .name = row.name,
        .image = row.image,
        .images = row.images,
        .content = row.content,
        .price = std.fmt.parseInt(i64, row.price, 10) catch 0,
        .original_price = std.fmt.parseInt(i64, row.original_price, 10) catch 0,
        .stock = row.stock,
        .sales = row.sales,
        .status = row.status,
        .created_at = row.created_at,
    };
}

pub const SkuDto = struct {
    id: i64,
    product_id: i64,
    spec_json: []const u8,
    image: []const u8,
    price: i64,
    stock: i64,
};

pub fn toSkuDto(row: service.ShopSkuRow) SkuDto {
    return .{
        .id = row.id,
        .product_id = row.product_id,
        .spec_json = row.spec_json,
        .image = row.image,
        .price = std.fmt.parseInt(i64, row.price, 10) catch 0,
        .stock = row.stock,
    };
}

pub const CreateCategoryReq = struct {
    account_id: i64,
    name: []const u8,
    parent_id: i64 = 0,
    sort: i64 = 0,
};

pub const SkuReq = service.SkuInput;

pub const ProductReq = struct {
    account_id: i64,
    category_id: i64 = 0,
    name: []const u8,
    image: []const u8 = "",
    images: []const u8 = "[]",
    content: []const u8 = "",
    price: i64,
    original_price: i64 = 0,
    stock: i64,
    status: i64 = 1,
    skus: []const SkuReq = &.{},
};
