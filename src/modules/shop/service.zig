//! Shop service — 商城商品域业务（分类/商品/SKU）。
//!
//! Phase 1：商品域。管理端（admin JWT）维护分类/商品；C 端（粉丝）只读浏览。

const std = @import("std");
const zigmodu = @import("zigmodu");
const zent = @import("zent");
const persist = @import("persistence.zig");
const schema = @import("../../schema.zig");
const crud = zent.crud_helpers;
const coupon_service = @import("../coupon/service.zig");
const member_persist = @import("../member/persistence.zig");
const task_service = @import("../task/service.zig");
const db_mod = @import("../../db.zig");

pub const ShopCategoryRow = persist.ShopCategoryRow;
pub const ShopProductRow = persist.ShopProductRow;
pub const ShopSkuRow = persist.ShopSkuRow;
pub const CategoryListResult = persist.CategoryListResult;
pub const ProductListResult = persist.ProductListResult;
pub const ShopCartRow = persist.ShopCartRow;
pub const ShopAddressRow = persist.ShopAddressRow;
pub const ShopOrderRow = persist.ShopOrderRow;
pub const ShopOrderProductRow = persist.ShopOrderProductRow;
pub const OrderListResult = persist.OrderListResult;
pub const ShopRefundRow = persist.ShopRefundRow;
pub const ShopCommentRow = persist.ShopCommentRow;
pub const RefundListResult = persist.RefundListResult;
pub const ShopFavoriteRow = persist.ShopFavoriteRow;
pub const ShopOutletRow = persist.ShopOutletRow;
pub const ShopBalancePlanRow = persist.ShopBalancePlanRow;
pub const ShopGrouponRow = persist.ShopGrouponRow;
pub const ShopGrouponTeamRow = persist.ShopGrouponTeamRow;
pub const ShopInviteGiftRow = persist.ShopInviteGiftRow;
pub const ShopArticleRow = persist.ShopArticleRow;
pub const ArticleListResult = persist.ArticleListResult;
pub const ShopWebhookRow = persist.ShopWebhookRow;

pub const ShopError = error{
    InvalidInput,
    NotFound,
    Duplicate,
    OutOfStock,
    InsufficientBalance,
    OrderStateConflict,
    /// 核销码连续试错超限，订单进入冷却锁定（见 PickupGuard）。
    PickupLocked,
    /// 请求预算耗尽（zent PoolWaitTimeout/QueryTimeout，见 request_budget 闸门）。
    RequestTimeout,
    Unexpected,
};

pub const ProductInput = struct {
    category_id: i64,
    name: []const u8,
    image: []const u8,
    images: []const u8,
    content: []const u8,
    price: i64,
    original_price: i64,
    stock: i64,
    status: i64 = 1,
    skus: []const SkuInput,
};

pub const SkuInput = struct {
    spec_json: []const u8,
    image: []const u8,
    price: i64,
    stock: i64,
};

// ── 事件（Phase B：事件驱动解耦）──────────────────────────

/// 订单支付成功事件（支付 → 分销分佣/积分累计/通知等消费者处理）。
pub const OrderPaidEvent = struct {
    tenant_id: i64,
    account_id: i64,
    order_id: i64,
};

pub const OrderPaidBus = zigmodu.TypedEventBus(OrderPaidEvent);

/// 核销防暴力守卫：按订单维度记连续失败次数，达到阈值进入冷却锁定。
/// 取货码仅 6 位数字（1e6 空间），无限速即可被遍历——本守卫把成本抬到
/// 「每订单每冷却窗至多 max_fails 次试错」。定长槽位、零分配（ShopService
/// 无 deinit，测试泄漏门禁零负担），进程重启清零可接受：内存态锁定的意义
/// 是限速而非封禁名单。路由层另有 per-IP 限流双保险（api.zig 注册处）。
pub const PickupGuard = struct {
    pub const capacity = 64;
    pub const max_fails = 5;
    pub const lockout_secs: i64 = 900;

    pub const Entry = struct {
        /// 0 表示空槽（订单 id 从 1 起自增，不会为 0）。
        order_id: i64 = 0,
        fails: u32 = 0,
        locked_until: i64 = 0,
    };

    pub const Decision = enum { allowed, locked };

    /// 极短临界区（64 槽线性扫）用原子自旋锁即可；std.Io.Mutex 需要
    /// io 实例才能解锁，守卫方法不便携带 io。
    guard_locked: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    slots: [capacity]Entry = @splat(.{}),
    /// 环形覆盖指针：槽满时新订单覆盖最旧一条（约 64 个在途核销订单，够用）。
    clock: usize = 0,

    /// 本次尝试是否放行（冷却窗口未过 → locked）。
    fn acquire(self: *PickupGuard) void {
        while (self.guard_locked.swap(true, .acquire)) {}
    }

    fn release(self: *PickupGuard) void {
        self.guard_locked.store(false, .release);
    }

    pub fn allow(self: *PickupGuard, order_id: i64, now: i64) Decision {
        self.acquire();
        defer self.release();
        const s = self.find(order_id) orelse return .allowed;
        if (s.locked_until > now) return .locked;
        return .allowed;
    }

    /// 记一次失败；累计到阈值即进入冷却并清零计数（冷却后重新计满 5 次）。
    pub fn fail(self: *PickupGuard, order_id: i64, now: i64) void {
        self.acquire();
        defer self.release();
        if (self.find(order_id)) |s| {
            s.fails += 1;
            if (s.fails >= max_fails) {
                s.locked_until = now + lockout_secs;
                s.fails = 0;
            }
            return;
        }
        self.slots[self.clock % capacity] = .{ .order_id = order_id, .fails = 1 };
        self.clock +%= 1;
    }

    /// 核销成功，清除该订单的失败记录。
    pub fn reset(self: *PickupGuard, order_id: i64) void {
        self.acquire();
        defer self.release();
        if (self.find(order_id)) |s| {
            s.* = .{};
        }
    }

    fn find(self: *PickupGuard, order_id: i64) ?*Entry {
        for (&self.slots) |*s| {
            if (s.order_id == order_id) return s;
        }
        return null;
    }
};

// ── 交易业务（Phase 2）────────────────────────────────────

pub const OrderItemInput = struct {
    product_id: i64,
    sku_id: i64,
    quantity: i64,
};

pub const AddressInput = struct {
    openid: []const u8,
    name: []const u8,
    mobile: []const u8,
    region: []const u8,
    detail: []const u8,
    is_default: i64 = 0,
};

// ── 聚合 DTO（原为 ShopService 嵌套声明，拆分时提升到文件级，片段与宿主同名引用）──
pub const OrderSummary = struct {
    order_id: i64,
    cover_image: []const u8,
    item_count: i64,
    summary: []const u8,

    pub fn free(self: OrderSummary, allocator: std.mem.Allocator) void {
        allocator.free(self.cover_image);
        allocator.free(self.summary);
    }
};

pub const OrderStats = struct {
    pending_pay: i64,
    pending_ship: i64,
    completed: i64,
    total_sales: i64,
};

pub const FanOrderOverview = struct {
    pending_pay: i64,
    pending_ship: i64,
    shipped: i64,
    completed: i64,
    order_timeout_secs: i64,
};

const parts_catalog = @import("service/catalog.zig");
const parts_trade = @import("service/trade.zig");
const parts_marketing = @import("service/marketing.zig");
const parts_content = @import("service/content.zig");

pub const ShopService = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    store: *persist.ShopStore,
    /// 分销服务（可选注入，支付成功后触发三级分佣）
    dist_svc: ?*anyopaque = null,
    /// 会员卡服务（可选注入，支付后累计积分）
    member_svc: ?*anyopaque = null,
    /// 支付服务（可选注入，余额支付扣钱包）
    payment_svc: ?*anyopaque = null,
    /// 粉丝存储（可选注入，openid → fan_id）。
    /// 边界例外（理由见 docs/ARCHITECTURE.md「模块依赖与边界」）：装配契约在
    /// main.zig 注入的是 FanStore 指针而非 MemberService，两处只读单查
    /// （余额支付/储值充值前取 fan_id）保留直读 member persistence。
    fan_store: ?*member_persist.FanStore = null,
    /// 优惠券服务（可选注入，邀请达标发券）
    coupon_svc: ?*anyopaque = null,
    /// 支付事件总线（可选注入；存在则支付走事件分发，否则同步回退）
    order_paid_bus: ?*OrderPaidBus = null,
    /// 任务队列服务（可选注入；webhook 投递经它入队 webhook.deliver，
    /// 由 Dispatcher worker 异步 POST + 退避重试，不在事件监听里同步阻塞）
    task_svc: ?*task_service.TaskService = null,
    /// 核销防暴力守卫（见 PickupGuard）。
    pickup_guard: PickupGuard = .{},

    pub fn init(allocator: std.mem.Allocator, io: std.Io, store: *persist.ShopStore) ShopService {
        return .{ .allocator = allocator, .io = io, .store = store };
    }

    pub fn now(self: *ShopService) i64 {
        return zigmodu.time.wallClockSeconds(self.io);
    }

    // ── 分类 ───────────────────────────────────────────────

    // ── 方法按子域分文件（正文见 service/*.zig），此处按原名桥接 ──
    pub const createCategory = parts_catalog.createCategory;
    pub const listCategories = parts_catalog.listCategories;
    pub const deleteCategory = parts_catalog.deleteCategory;
    pub const createProduct = parts_catalog.createProduct;
    pub const getProduct = parts_catalog.getProduct;
    pub const updateProduct = parts_catalog.updateProduct;
    pub const deleteProduct = parts_catalog.deleteProduct;
    pub const listProducts = parts_catalog.listProducts;
    pub const listSkus = parts_catalog.listSkus;
    pub const getSku = parts_catalog.getSku;
    pub const addCart = parts_trade.addCart;
    pub const listCarts = parts_trade.listCarts;
    pub const updateCart = parts_trade.updateCart;
    pub const deleteCart = parts_trade.deleteCart;
    pub const createAddress = parts_trade.createAddress;
    pub const listAddresses = parts_trade.listAddresses;
    pub const deleteAddress = parts_trade.deleteAddress;
    pub const setAddressDefault = parts_trade.setAddressDefault;
    pub const updateAddress = parts_trade.updateAddress;
    pub const genPickupCode = parts_trade.genPickupCode;
    pub const genOrderNo = parts_trade.genOrderNo;
    pub const createOrder = parts_trade.createOrder;
    pub const createOrderBudget = parts_trade.createOrderBudget;
    pub const getOrder = parts_trade.getOrder;
    pub const listOrders = parts_trade.listOrders;
    pub const listOrdersBudget = parts_trade.listOrdersBudget;
    pub const listOrderProducts = parts_trade.listOrderProducts;
    pub const getOrderProduct = parts_trade.getOrderProduct;
    pub const markPaid = parts_trade.markPaid;
    pub const cancelOrder = parts_trade.cancelOrder;
    pub const confirmOrder = parts_trade.confirmOrder;
    pub const shipOrder = parts_trade.shipOrder;
    pub const applyRefund = parts_trade.applyRefund;
    pub const listRefunds = parts_trade.listRefunds;
    pub const listRefundsByOpenid = parts_trade.listRefundsByOpenid;
    pub const orderSummaries = parts_trade.orderSummaries;
    pub const getRefundByOrder = parts_trade.getRefundByOrder;
    pub const auditRefund = parts_trade.auditRefund;
    pub const auditRefundBudget = parts_trade.auditRefundBudget;
    pub const createComment = parts_trade.createComment;
    pub const listCommentedOrderProductIds = parts_trade.listCommentedOrderProductIds;
    pub const listComments = parts_trade.listComments;
    pub const favorite = parts_trade.favorite;
    pub const isFavorite = parts_trade.isFavorite;
    pub const unfavorite = parts_trade.unfavorite;
    pub const listFavorites = parts_trade.listFavorites;
    pub const fanOrderOverview = parts_trade.fanOrderOverview;
    pub const orderStats = parts_trade.orderStats;
    pub const autoCancelExpired = parts_trade.autoCancelExpired;
    pub const createBalancePlan = parts_marketing.createBalancePlan;
    pub const listBalancePlans = parts_marketing.listBalancePlans;
    pub const deleteBalancePlan = parts_marketing.deleteBalancePlan;
    pub const rechargePlan = parts_marketing.rechargePlan;
    pub const createInviteGift = parts_marketing.createInviteGift;
    pub const listInviteGifts = parts_marketing.listInviteGifts;
    pub const deleteInviteGift = parts_marketing.deleteInviteGift;
    pub const bindInvite = parts_marketing.bindInvite;
    pub const grantInviteReward = parts_marketing.grantInviteReward;
    pub const createGroupon = parts_marketing.createGroupon;
    pub const listGroupons = parts_marketing.listGroupons;
    pub const grouponOrder = parts_marketing.grouponOrder;
    pub const openGroupon = parts_marketing.openGroupon;
    pub const joinGroupon = parts_marketing.joinGroupon;
    pub const assistant = parts_content.assistant;
    pub const createWebhook = parts_content.createWebhook;
    pub const listWebhooks = parts_content.listWebhooks;
    pub const deleteWebhook = parts_content.deleteWebhook;
    pub const dispatchWebhooks = parts_content.dispatchWebhooks;
    pub const createArticle = parts_content.createArticle;
    pub const listArticles = parts_content.listArticles;
    pub const getArticle = parts_content.getArticle;
    pub const deleteArticle = parts_content.deleteArticle;
    pub const createOutlet = parts_content.createOutlet;
    pub const listOutlets = parts_content.listOutlets;
    pub const deleteOutlet = parts_content.deleteOutlet;
    pub const pickupOrder = parts_content.pickupOrder;
};
