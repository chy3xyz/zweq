//! Shop service — 商城商品域业务（分类/商品/SKU）。
//!
//! Phase 1：商品域。管理端（admin JWT）维护分类/商品；C 端（粉丝）只读浏览。

const std = @import("std");
const zigmodu = @import("zigmodu");
const zent = @import("zent");
const persist = @import("persistence.zig");
const schema = @import("../../schema.zig");
const crud = zent.crud_helpers;
const coupon_persist = @import("../coupon/persistence.zig");
const member_persist = @import("../member/persistence.zig");

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
    Unexpected,
};

pub const ProductInput = struct {
    category_id: i64,
    name: []const u8,
    image: []const u8,
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

pub const ShopService = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    store: *persist.ShopStore,
    /// 分销服务（可选注入，支付成功后触发三级分佣）
    dist_svc: ?*anyopaque = null,
    /// 优惠券存储（可选注入，下单校验/核销券）
    coupon_store: ?*coupon_persist.CouponStore = null,
    /// 会员卡服务（可选注入，支付后累计积分）
    member_svc: ?*anyopaque = null,
    /// 支付服务（可选注入，余额支付扣钱包）
    payment_svc: ?*anyopaque = null,
    /// 粉丝存储（可选注入，openid → fan_id）
    fan_store: ?*member_persist.FanStore = null,
    /// 优惠券服务（可选注入，邀请达标发券）
    coupon_svc: ?*anyopaque = null,
    /// 支付事件总线（可选注入；存在则支付走事件分发，否则同步回退）
    order_paid_bus: ?*OrderPaidBus = null,
    /// Webhook HTTP 传输（测试注入 mock；生产用真实 HTTP）
    webhook_transport: ?*anyopaque = null,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, store: *persist.ShopStore) ShopService {
        return .{ .allocator = allocator, .io = io, .store = store };
    }

    fn now(self: *ShopService) i64 {
        return zigmodu.time.wallClockSeconds(self.io);
    }

    // ── 分类 ───────────────────────────────────────────────

    pub fn createCategory(self: *ShopService, tenant_id: i64, account_id: i64, name: []const u8, parent_id: i64, sort: i64) ShopError!i64 {
        if (std.mem.trim(u8, name, " \t").len == 0) return error.InvalidInput;
        return self.store.createCategory(tenant_id, account_id, name, parent_id, sort, self.now()) catch error.Unexpected;
    }

    pub fn listCategories(self: *ShopService, tenant_id: i64, account_id: i64) ShopError!CategoryListResult {
        return self.store.listCategories(tenant_id, account_id) catch error.Unexpected;
    }

    pub fn deleteCategory(self: *ShopService, id: i64) ShopError!void {
        _ = self.store.deleteCategory(id) catch return error.Unexpected;
    }

    // ── 商品 ───────────────────────────────────────────────

    pub fn createProduct(self: *ShopService, tenant_id: i64, account_id: i64, p: ProductInput) ShopError!i64 {
        if (std.mem.trim(u8, p.name, " \t").len == 0 or p.price < 0 or p.stock < 0) return error.InvalidInput;
        const id = self.store.createProduct(tenant_id, account_id, p, self.now()) catch return error.Unexpected;
        errdefer _ = self.store.deleteProduct(id) catch {};

        // 默认 SKU：未传 skus 时按商品主数据建一行（spec_json="[]"）。
        if (p.skus.len == 0) {
            _ = self.store.createSku(tenant_id, account_id, id, "[]", p.image, p.price, p.stock, self.now()) catch return error.Unexpected;
        } else {
            for (p.skus) |s| {
                _ = self.store.createSku(tenant_id, account_id, id, s.spec_json, s.image, s.price, s.stock, self.now()) catch return error.Unexpected;
            }
        }
        return id;
    }

    pub fn getProduct(self: *ShopService, id: i64) ShopError!?ShopProductRow {
        return self.store.getProduct(id) catch error.Unexpected;
    }

    pub fn updateProduct(self: *ShopService, tenant_id: i64, account_id: i64, id: i64, p: ProductInput) ShopError!void {
        if (std.mem.trim(u8, p.name, " \t").len == 0 or p.price < 0 or p.stock < 0) return error.InvalidInput;
        if (!(self.store.updateProduct(id, p, self.now()) catch return error.Unexpected)) return error.NotFound;
        // 重建 SKU（幂等：删旧建新）。
        self.store.deleteSkusByProduct(id) catch {};
        if (p.skus.len == 0) {
            _ = self.store.createSku(tenant_id, account_id, id, "[]", p.image, p.price, p.stock, self.now()) catch {};
        } else {
            for (p.skus) |s| {
                _ = self.store.createSku(tenant_id, account_id, id, s.spec_json, s.image, s.price, s.stock, self.now()) catch {};
            }
        }
    }

    pub fn deleteProduct(self: *ShopService, id: i64) ShopError!void {
        _ = self.store.deleteProduct(id) catch return error.Unexpected;
        self.store.deleteSkusByProduct(id) catch {};
    }

    pub fn listProducts(self: *ShopService, page: usize, page_size: usize, tenant_id: i64, account_id: i64, category_id: i64, keyword: []const u8, on_sale: bool) ShopError!ProductListResult {
        return self.store.listProducts(page, page_size, tenant_id, account_id, category_id, keyword, on_sale) catch error.Unexpected;
    }

    // ── SKU ───────────────────────────────────────────────

    pub fn listSkus(self: *ShopService, product_id: i64) ShopError![]ShopSkuRow {
        return self.store.listSkus(product_id) catch error.Unexpected;
    }

    pub fn getSku(self: *ShopService, id: i64) ShopError!?ShopSkuRow {
        return self.store.getSku(id) catch error.Unexpected;
    }
    // ── 购物车 ───────────────────────────────────────────

    pub fn addCart(self: *ShopService, tenant_id: i64, account_id: i64, openid: []const u8, product_id: i64, sku_id: i64, quantity: i64) ShopError!i64 {
        if (quantity <= 0) return error.InvalidInput;
        const sku_opt = self.store.getSku(sku_id) catch return error.Unexpected;
        const sku = sku_opt orelse return error.NotFound;
        sku.free(self.allocator);
        return self.store.upsertCart(tenant_id, account_id, openid, product_id, sku_id, quantity, self.now()) catch error.Unexpected;
    }

    pub fn listCarts(self: *ShopService, tenant_id: i64, openid: []const u8) ShopError![]ShopCartRow {
        return self.store.listCarts(tenant_id, openid) catch error.Unexpected;
    }

    pub fn updateCart(self: *ShopService, id: i64, quantity: i64) ShopError!void {
        if (quantity <= 0) return error.InvalidInput;
        _ = self.store.updateCartQuantity(id, quantity) catch return error.Unexpected;
    }

    pub fn deleteCart(self: *ShopService, id: i64) ShopError!void {
        _ = self.store.deleteCart(id) catch return error.Unexpected;
    }

    // ── 地址 ─────────────────────────────────────────────

    pub fn createAddress(self: *ShopService, tenant_id: i64, account_id: i64, a: AddressInput) ShopError!i64 {
        if (std.mem.trim(u8, a.name, " \t").len == 0 or std.mem.trim(u8, a.mobile, " \t").len == 0) return error.InvalidInput;
        return self.store.createAddress(tenant_id, account_id, a, self.now()) catch error.Unexpected;
    }

    pub fn listAddresses(self: *ShopService, tenant_id: i64, openid: []const u8) ShopError![]ShopAddressRow {
        return self.store.listAddresses(tenant_id, openid) catch error.Unexpected;
    }

    pub fn deleteAddress(self: *ShopService, id: i64) ShopError!void {
        _ = self.store.deleteAddress(id) catch return error.Unexpected;
    }

    // ── 下单引擎 ─────────────────────────────────────────

    /// 自提核销码：6 位数字（PK 前缀展示用）。
    fn genPickupCode(self: *ShopService) ![]const u8 {
        var buf: [4]u8 = undefined;
        var file = try std.Io.Dir.cwd().openFile(self.io, "/dev/urandom", .{});
        defer file.close(self.io);
        const read = try file.readPositionalAll(self.io, &buf, 0);
        if (read != buf.len) return error.Unexpected;
        const n = std.mem.readInt(u32, &buf, .little) % 1000000;
        return std.fmt.allocPrint(self.allocator, "{d:0>6}", .{n});
    }

    /// 唯一订单号：SO + 秒级时间戳 + 8 字节随机 hex（防撞号）。
    fn genOrderNo(self: *ShopService) ![]const u8 {
        var buf: [8]u8 = undefined;
        var file = try std.Io.Dir.cwd().openFile(self.io, "/dev/urandom", .{});
        defer file.close(self.io);
        const read = try file.readPositionalAll(self.io, &buf, 0);
        if (read != buf.len) return error.Unexpected;
        return std.fmt.allocPrint(self.allocator, "SO{d}{x:0>16}", .{ self.now(), std.mem.readInt(u64, &buf, .little) });
    }

    /// 下单：校验商品/SKU/库存 → 原子扣库存 → 生成订单号 → 写订单+明细。
    /// 返回订单 id。支付由 payment 模块承接（mock 即时入账 / v3 微信支付）。
    pub fn createOrder(self: *ShopService, tenant_id: i64, account_id: i64, openid: []const u8, address_id: i64, items: []const OrderItemInput, coupon_code: []const u8, client_trade_no: []const u8, pay_type: []const u8, pickup_store_id: i64) ShopError!i64 {
        // 幂等：同 client_trade_no 已存在 → 返回原单（不重复扣库存）。
        if (client_trade_no.len > 0) {
            if (self.store.getByClientTradeNo(tenant_id, client_trade_no) catch return error.Unexpected) |existing| {
                defer existing.free(self.allocator);
                return existing.id;
            }
        }
        if (items.len == 0) return error.InvalidInput;
        // 地址快照
        const addr_opt = self.store.getAddress(address_id) catch return error.Unexpected;
        const addr = addr_opt orelse return error.InvalidInput;
        defer addr.free(self.allocator);
        const address_json = std.json.Stringify.valueAlloc(self.allocator, .{
            .name = addr.name,
            .mobile = addr.mobile,
            .region = addr.region,
            .detail = addr.detail,
        }, .{}) catch return error.Unexpected;
        defer self.allocator.free(address_json);

        // 逐项校验 + 原子扣库存 + 汇总金额
        var total: i64 = 0;
        const order_no = self.genOrderNo() catch return error.Unexpected;
        defer self.allocator.free(order_no);
        var pickup_code_owned: ?[]const u8 = null;
        defer if (pickup_code_owned) |c| self.allocator.free(c);

        // 事务：扣库存 + 建单 + 明细 原子提交（SQLite/Postgres 均支持）；失败整体回滚。
        var tx = zent.codegen.beginTx(schema.infos, self.store.client) catch return error.Unexpected;
        defer tx.deinit();
        for (items) |it| {
            const sp = tx.client.shop_product_sku.predicates;
            const sku_opt = self.store.getSku(it.sku_id) catch return error.Unexpected;
            const sku = sku_opt orelse return error.NotFound;
            defer sku.free(self.allocator);
            const guard = std.fmt.allocPrint(self.allocator, "stock >= {d}", .{it.quantity}) catch return error.Unexpected;
            defer self.allocator.free(guard);
            const affected = crud.increment(tx.client.shop_product_sku, "stock", -it.quantity, &.{
                sp.idEQ(.{ .int = it.sku_id }),
                zent.sql.Predicate{ .raw = guard },
            }) catch {
                tx.rollback() catch {};
                return error.OutOfStock;
            };
            if (affected == 0) {
                tx.rollback() catch {};
                return error.OutOfStock;
            }
            total += sku.price * it.quantity;
            const pp = tx.client.shop_product.predicates;
            _ = crud.increment(tx.client.shop_product, "sales", it.quantity, &.{pp.idEQ(.{ .int = it.product_id })}) catch {};
        }

        // 优惠券减免：code 可选，校验归属/未用/门槛后减免。
        var discount: i64 = 0;
        if (coupon_code.len > 0) {
            if (self.coupon_store) |cs| {
                const u_opt = cs.getByCode(coupon_code) catch return error.Unexpected;
                const u = u_opt orelse return error.InvalidInput;
                defer u.free(self.allocator);
                if (!std.mem.eql(u8, u.openid, openid)) return error.InvalidInput;
                if (!std.mem.eql(u8, u.status, "unused")) return error.InvalidInput;
                const c_opt = cs.getCoupon(u.coupon_id) catch return error.Unexpected;
                const c = c_opt orelse return error.InvalidInput;
                defer c.free(self.allocator);
                if (c.min_amount > 0 and total < c.min_amount) return error.InvalidInput;
                discount = @min(c.amount, total);
                cs.setStatus(u.id, "used", self.now()) catch return error.Unexpected;
            }
        }
        const pay_amount = total - discount;

        // 自提：pickup_store_id>0 → 生成核销码（6 位数字）。
        const is_pickup = pickup_store_id > 0;
        const pickup_type = if (is_pickup) "self" else "delivery";
        const pickup_code = if (is_pickup) blk: {
            pickup_code_owned = self.genPickupCode() catch "";
            break :blk pickup_code_owned.?;
        } else "";

        const now_secs = self.now();
        const order_id = blk: {
            var row = crud.create(tx.client.shop_order, .{
                .tenant_id = tenant_id,
                .account_id = account_id,
                .order_no = order_no,
                .client_trade_no = client_trade_no,
                .openid = openid,
                .total_amount = total,
                .pay_amount = pay_amount,
                .status = 0,
                .address_json = address_json,
                .express_company = "",
                .express_no = "",
                .paid_at = 0,
                .pickup_type = pickup_type,
                .pickup_code = pickup_code,
                .store_id = if (is_pickup) pickup_store_id else 0,
                .groupon_team_id = 0,
                .created_at = now_secs,
                .updated_at = now_secs,
            }) catch {
                tx.rollback() catch {};
                return error.Unexpected;
            };
            defer zent.codegen.deinitEntity(persist.infos, persist.ShopOrderInfo, &row, self.allocator);
            break :blk row.id;
        };

        for (items) |it| {
            const sku_opt = self.store.getSku(it.sku_id) catch return error.Unexpected;
            const sku = sku_opt orelse return error.NotFound;
            defer sku.free(self.allocator);
            const p_opt = self.store.getProduct(it.product_id) catch return error.Unexpected;
            const p = p_opt orelse return error.NotFound;
            defer p.free(self.allocator);
            var op_row = crud.create(tx.client.shop_order_product, .{
                .tenant_id = tenant_id,
                .account_id = account_id,
                .order_id = order_id,
                .product_id = it.product_id,
                .sku_id = it.sku_id,
                .name = p.name,
                .image = p.image,
                .spec_json = sku.spec_json,
                .price = sku.price,
                .quantity = it.quantity,
                .created_at = now_secs,
                .updated_at = now_secs,
            }) catch {
                tx.rollback() catch {};
                return error.Unexpected;
            };
            defer zent.codegen.deinitEntity(schema.infos, persist.ShopOrderProductInfo, &op_row, self.allocator);
        }

        // 事务提交（原子）。
        tx.commit() catch return error.Unexpected;

        // 余额支付：pay_type=balance → 扣买家钱包（openid → fan_id），成功即标记支付。
        if (std.mem.eql(u8, pay_type, "balance")) {
            if (self.payment_svc) |ps| {
                if (self.fan_store) |fs| {
                    const fan_opt = fs.getByOpenid(tenant_id, account_id, openid) catch return error.Unexpected;
                    const fan = fan_opt orelse return error.NotFound;
                    defer fan.free(self.allocator);
                    const pay_mod = @import("../payment/service.zig");
                    const psvc: *pay_mod.PaymentService = @ptrCast(@alignCast(ps));
                    const ok = psvc.payWithBalance(tenant_id, account_id, fan.id, pay_amount) catch false;
                    if (!ok) {
                        _ = self.store.updateOrderStatus(order_id, 4, self.now()) catch {};
                        self.store.restoreOrderStock(order_id) catch {}; // 事务已提交，显式回滚
                        return error.InsufficientBalance;
                    }
                    self.markPaid(tenant_id, account_id, order_id) catch {};
                }
            }
        }
        return order_id;
    }

    pub fn getOrder(self: *ShopService, id: i64) ShopError!?ShopOrderRow {
        return self.store.getOrder(id) catch error.Unexpected;
    }

    pub fn listOrders(self: *ShopService, page: usize, page_size: usize, tenant_id: i64, account_id: i64, openid: []const u8, status: i64) ShopError!OrderListResult {
        return self.store.listOrders(page, page_size, tenant_id, account_id, openid, status) catch error.Unexpected;
    }

    pub fn listOrderProducts(self: *ShopService, order_id: i64) ShopError![]ShopOrderProductRow {
        return self.store.listOrderProducts(order_id) catch error.Unexpected;
    }

    pub fn getOrderProduct(self: *ShopService, id: i64) ShopError!?ShopOrderProductRow {
        return self.store.getOrderProduct(id) catch error.Unexpected;
    }

    /// 支付成功回调（payment 模块调用）：status 0→1。
    /// 事件驱动：有 bus → publish OrderPaidEvent（消费者处理分销/积分/通知）；
    /// 无 bus → 同步回退（单测/最小部署兼容）。
    pub fn markPaid(self: *ShopService, tenant_id: i64, account_id: i64, order_id: i64) ShopError!void {
        _ = self.store.updateOrderStatus(order_id, 1, self.now()) catch return error.Unexpected;
        if (self.order_paid_bus) |bus| {
            bus.publish(.{ .tenant_id = tenant_id, .account_id = account_id, .order_id = order_id });
            return;
        }
        // 同步回退：分销 + 积分。
        if (self.dist_svc) |ds| {
            const o_opt = self.store.getOrder(order_id) catch return;
            const o = o_opt orelse return;
            defer o.free(self.allocator);
            const dist_mod = @import("../distribution/service.zig");
            const dsvc: *dist_mod.DistributionService = @ptrCast(@alignCast(ds));
            _ = dsvc.distribute(tenant_id, account_id, o.openid, o.pay_amount) catch {};
        }
        // 会员积分累计：1 元 = 1 积分。
        if (self.member_svc) |ms| {
            const o_opt2 = self.store.getOrder(order_id) catch return;
            const o2 = o_opt2 orelse return;
            defer o2.free(self.allocator);
            const mc_mod = @import("../member_card/service.zig");
            const msvc: *mc_mod.MemberCardService = @ptrCast(@alignCast(ms));
            _ = msvc.adjust(tenant_id, account_id, o2.openid, @divTrunc(o2.pay_amount, 100)) catch {};
        }
    }

    /// 取消订单（仅待支付可取消）；取消后回滚库存与销量。
    pub fn cancelOrder(self: *ShopService, order_id: i64) ShopError!void {
        const o_opt = self.store.getOrder(order_id) catch return error.Unexpected;
        const o = o_opt orelse return error.NotFound;
        defer o.free(self.allocator);
        if (o.status != 0) return error.OrderStateConflict;
        _ = self.store.updateOrderStatus(order_id, 4, self.now()) catch return error.Unexpected;
        self.store.restoreOrderStock(order_id) catch {};
    }

    /// 确认收货（已发货 → 已完成）。
    pub fn confirmOrder(self: *ShopService, order_id: i64) ShopError!void {
        const o_opt = self.store.getOrder(order_id) catch return error.Unexpected;
        const o = o_opt orelse return error.NotFound;
        defer o.free(self.allocator);
        if (o.status != 2) return error.OrderStateConflict;
        _ = self.store.updateOrderStatus(order_id, 3, self.now()) catch return error.Unexpected;
    }

    /// 管理端发货。
    pub fn shipOrder(self: *ShopService, order_id: i64, company: []const u8, no: []const u8) ShopError!void {
        const o_opt = self.store.getOrder(order_id) catch return error.Unexpected;
        const o = o_opt orelse return error.NotFound;
        defer o.free(self.allocator);
        if (o.status != 1) return error.OrderStateConflict;
        _ = self.store.updateOrderExpress(order_id, company, no, self.now()) catch return error.Unexpected;
        _ = self.store.updateOrderStatus(order_id, 2, self.now()) catch return error.Unexpected;
    }

    // ── 退款 ──────────────────────────────────────────────

    /// 申请退款（仅已支付/已发货可申请；一单一退）。
    pub fn applyRefund(self: *ShopService, tenant_id: i64, account_id: i64, order_id: i64, openid: []const u8, reason: []const u8) ShopError!i64 {
        const o_opt = self.store.getOrder(order_id) catch return error.Unexpected;
        const o = o_opt orelse return error.NotFound;
        defer o.free(self.allocator);
        if (o.status == 0 or o.status == 4) return error.OrderStateConflict;
        if (self.store.getRefundByOrder(tenant_id, order_id) catch null) |existing| {
            existing.free(self.allocator);
            return error.Duplicate;
        }
        return self.store.createRefund(tenant_id, account_id, order_id, openid, reason, o.pay_amount, self.now()) catch error.Unexpected;
    }

    pub fn listRefunds(self: *ShopService, page: usize, page_size: usize, tenant_id: i64, account_id: i64, status: i64) ShopError!RefundListResult {
        return self.store.listRefunds(page, page_size, tenant_id, account_id, status) catch error.Unexpected;
    }

    /// 退款审核：同意 → 订单置为已取消（4）+ 回滚库存与销量。
    pub fn auditRefund(self: *ShopService, order_id: i64, refund_id: i64, approve: bool) ShopError!void {
        _ = self.store.auditRefund(refund_id, if (approve) 1 else 2, self.now()) catch return error.Unexpected;
        if (approve) {
            _ = self.store.updateOrderStatus(order_id, 4, self.now()) catch {};
            self.store.restoreOrderStock(order_id) catch {};
        }
    }

    // ── 评价 ──────────────────────────────────────────────

    pub fn createComment(self: *ShopService, tenant_id: i64, account_id: i64, c: anytype) ShopError!i64 {
        if (c.star < 1 or c.star > 5) return error.InvalidInput;
        // 实名校验：评价人必须是该订单买家，且订单已完成（3）才可评。
        const op_opt = self.store.getOrderProduct(c.order_product_id) catch return error.Unexpected;
        const op = op_opt orelse return error.NotFound;
        defer op.free(self.allocator);
        const o_opt = self.store.getOrder(op.order_id) catch return error.Unexpected;
        const o = o_opt orelse return error.NotFound;
        defer o.free(self.allocator);
        if (!std.mem.eql(u8, o.openid, c.openid)) return error.InvalidInput;
        if (o.status != 3) return error.OrderStateConflict;
        return self.store.createComment(tenant_id, account_id, c, self.now()) catch error.Unexpected;
    }

    pub fn listComments(self: *ShopService, product_id: i64) ShopError![]ShopCommentRow {
        return self.store.listCommentsByProduct(product_id) catch error.Unexpected;
    }

    // ── 收藏 ──────────────────────────────────────────────

    pub fn favorite(self: *ShopService, tenant_id: i64, account_id: i64, openid: []const u8, product_id: i64) ShopError!void {
        const p_opt = self.store.getProduct(product_id) catch return error.Unexpected;
        const p = p_opt orelse return error.NotFound;
        p.free(self.allocator);
        self.store.favorite(tenant_id, account_id, openid, product_id, self.now()) catch return error.Unexpected;
    }

    pub fn isFavorite(self: *ShopService, tenant_id: i64, openid: []const u8, product_id: i64) ShopError!bool {
        return self.store.isFavorite(tenant_id, openid, product_id) catch error.Unexpected;
    }

    pub fn unfavorite(self: *ShopService, id: i64) ShopError!void {
        _ = self.store.unfavorite(id) catch return error.Unexpected;
    }

    pub fn listFavorites(self: *ShopService, tenant_id: i64, openid: []const u8) ShopError![]ShopFavoriteRow {
        return self.store.listFavorites(tenant_id, openid) catch error.Unexpected;
    }

    // ── 订单统计（管理端） ───────────────────────────────

    pub const OrderStats = struct {
        pending_pay: i64,
        pending_ship: i64,
        completed: i64,
        total_sales: i64,
    };

    pub fn orderStats(self: *ShopService, tenant_id: i64, account_id: i64) ShopError!OrderStats {
        return .{
            .pending_pay = self.store.countOrdersByStatus(tenant_id, account_id, 0) catch return error.Unexpected,
            .pending_ship = self.store.countOrdersByStatus(tenant_id, account_id, 1) catch return error.Unexpected,
            .completed = self.store.countOrdersByStatus(tenant_id, account_id, 3) catch return error.Unexpected,
            .total_sales = self.store.sumPaidAmount(tenant_id, account_id) catch return error.Unexpected,
        };
    }

    // ── 储值卡 ───────────────────────────────────────────

    pub fn createBalancePlan(self: *ShopService, tenant_id: i64, account_id: i64, name: []const u8, amount: i64, bonus: i64) ShopError!i64 {
        if (std.mem.trim(u8, name, " \t").len == 0 or amount <= 0 or bonus < 0) return error.InvalidInput;
        return self.store.createBalancePlan(tenant_id, account_id, name, amount, bonus, self.now()) catch error.Unexpected;
    }

    pub fn listBalancePlans(self: *ShopService, tenant_id: i64, account_id: i64) ShopError![]ShopBalancePlanRow {
        return self.store.listBalancePlans(tenant_id, account_id) catch error.Unexpected;
    }

    pub fn deleteBalancePlan(self: *ShopService, id: i64) ShopError!void {
        _ = self.store.deleteBalancePlan(id) catch return error.Unexpected;
    }

    /// 充值：mock 即时入账（amount + bonus 进钱包）；真实走 payment v3。
    pub fn rechargePlan(self: *ShopService, tenant_id: i64, account_id: i64, openid: []const u8, plan_id: i64) ShopError!void {
        const plan_opt = self.store.getBalancePlan(plan_id) catch return error.Unexpected;
        const plan = plan_opt orelse return error.NotFound;
        defer plan.free(self.allocator);
        if (self.payment_svc) |ps| {
            if (self.fan_store) |fs| {
                const fan_opt = fs.getByOpenid(tenant_id, account_id, openid) catch return error.Unexpected;
                const fan = fan_opt orelse return error.NotFound;
                defer fan.free(self.allocator);
                const pay_mod = @import("../payment/service.zig");
                const psvc: *pay_mod.PaymentService = @ptrCast(@alignCast(ps));
                const now_secs = self.now();
                _ = psvc.store.creditWallet(tenant_id, account_id, fan.id, plan.amount + plan.bonus, now_secs) catch return error.Unexpected;
            }
        }
    }

    // ── 订单超时自动取消（生产运维） ─────────────────────

    /// 自动取消超时未支付订单并回滚库存。返回取消数量。
    pub fn autoCancelExpired(self: *ShopService, tenant_id: i64, account_id: i64, timeout_secs: i64) ShopError!usize {
        const before = self.now() - timeout_secs;
        const expired = self.store.listExpiredPending(tenant_id, account_id, before) catch return error.Unexpected;
        defer {
            for (expired) |o| o.free(self.allocator);
            if (expired.len > 0) self.allocator.free(expired);
        }
        var count: usize = 0;
        for (expired) |o| {
            _ = self.store.updateOrderStatus(o.id, 4, self.now()) catch continue;
            self.store.restoreOrderStock(o.id) catch {};
            count += 1;
        }
        return count;
    }

    // ── AI 智能助手（订单上下文感知） ───────────────────

    /// 智能客服：关键词规则解析订单上下文（不依赖 LLM）；返回引导文本。
    pub fn assistant(self: *ShopService, allocator: std.mem.Allocator, tenant_id: i64, account_id: i64, openid: []const u8, question: []const u8) ShopError![]const u8 {
        var buf = std.ArrayList(u8).empty;
        errdefer buf.deinit(allocator);
        const q = std.mem.trim(u8, question, " \t\n");

        // 订单状态
        if (std.mem.indexOf(u8, q, "订单") != null or std.mem.indexOf(u8, q, "order") != null) {
            var orders = self.store.listOrders(1, 3, tenant_id, account_id, openid, -1) catch return error.Unexpected;
            defer orders.free(self.allocator);
            if (orders.items.len == 0) {
                buf.appendSlice(allocator, "您还没有订单，快去商城逛逛吧～") catch return error.Unexpected;
            } else {
                buf.appendSlice(allocator, "最近订单：\n") catch return error.Unexpected;
                for (orders.items) |o| {
                    buf.appendSlice(allocator, o.order_no) catch return error.Unexpected;
                    buf.appendSlice(allocator, " · ") catch return error.Unexpected;
                    buf.appendSlice(allocator, switch (o.status) {
                        0 => "待支付",
                        1 => "已支付",
                        2 => "已发货",
                        3 => "已完成",
                        else => "已取消",
                    }) catch return error.Unexpected;
                    buf.appendSlice(allocator, " · ") catch return error.Unexpected;
                    const pay = o.pay_amount;
                    const fen = @mod(pay, 100);
                    const amt = if (fen < 10)
                        (std.fmt.allocPrint(allocator, "{d}.0{d} 元", .{ @divTrunc(pay, 100), fen }) catch "?")
                    else
                        (std.fmt.allocPrint(allocator, "{d}.{d} 元", .{ @divTrunc(pay, 100), fen }) catch "?");
                    defer allocator.free(amt);
                    buf.appendSlice(allocator, amt) catch return error.Unexpected;
                    buf.appendSlice(allocator, "\n") catch return error.Unexpected;
                }
            }
            return buf.toOwnedSlice(allocator) catch return error.Unexpected;
        }

        // 物流
        if (std.mem.indexOf(u8, q, "物流") != null or std.mem.indexOf(u8, q, "快递") != null) {
            var orders = self.store.listOrders(1, 1, tenant_id, account_id, openid, 2) catch return error.Unexpected;
            defer orders.free(self.allocator);
            if (orders.items.len == 0) {
                buf.appendSlice(allocator, "您没有已发货的订单") catch return error.Unexpected;
            } else {
                const o = &orders.items[0];
                buf.appendSlice(allocator, "最新物流：") catch return error.Unexpected;
                buf.appendSlice(allocator, o.express_company) catch return error.Unexpected;
                buf.appendSlice(allocator, " 单号 ") catch return error.Unexpected;
                buf.appendSlice(allocator, o.express_no) catch return error.Unexpected;
            }
            return buf.toOwnedSlice(allocator) catch return error.Unexpected;
        }

        // 待支付
        if (std.mem.indexOf(u8, q, "支付") != null or std.mem.indexOf(u8, q, "付款") != null) {
            const pending = self.store.countOrdersByStatus(tenant_id, account_id, 0) catch 0;
            const paid = self.store.countOrdersByStatus(tenant_id, account_id, 1) catch 0;
            const stat = std.fmt.allocPrint(allocator, "待支付 {d} 单，已支付 {d} 单", .{ pending, paid }) catch return error.Unexpected;
            defer allocator.free(stat);
            return self.allocator.dupe(u8, stat) catch error.Unexpected;
        }

        // 收藏
        if (std.mem.indexOf(u8, q, "收藏") != null) {
            const favs = self.store.listFavorites(tenant_id, openid) catch &.{};
            defer {
                for (favs) |f| f.free(self.allocator);
                if (favs.len > 0) self.allocator.free(favs);
            }
            const c = std.fmt.allocPrint(allocator, "您收藏了 {d} 件商品", .{favs.len}) catch "?";
            defer allocator.free(c);
            return self.allocator.dupe(u8, c) catch error.Unexpected;
        }

        // 默认引导
        return self.allocator.dupe(u8, "我可以帮您查询订单、物流、支付状态和收藏。试试问我「我的订单」「物流到哪了」") catch error.Unexpected;
    }

    // ── Webhook ───────────────────────────────────────────

    pub fn createWebhook(self: *ShopService, tenant_id: i64, account_id: i64, url: []const u8, events: []const u8) ShopError!i64 {
        if (std.mem.trim(u8, url, " \t").len == 0 or std.mem.indexOf(u8, url, "http") == null) return error.InvalidInput;
        return self.store.createWebhook(tenant_id, account_id, url, events, self.now()) catch error.Unexpected;
    }

    pub fn listWebhooks(self: *ShopService, tenant_id: i64, account_id: i64) ShopError![]ShopWebhookRow {
        return self.store.listWebhooks(tenant_id, account_id) catch error.Unexpected;
    }

    pub fn deleteWebhook(self: *ShopService, id: i64) ShopError!void {
        _ = self.store.deleteWebhook(id) catch return error.Unexpected;
    }

    /// 推送订单事件到配置的 webhook URL（事件驱动开放出口）。
    pub fn dispatchWebhooks(self: *ShopService, event: []const u8, tenant_id: i64, account_id: i64, order_id: i64) void {
        const hooks = self.store.listWebhooks(tenant_id, account_id) catch return;
        defer {
            for (hooks) |h| h.free(self.allocator);
            if (hooks.len > 0) self.allocator.free(hooks);
        }
        if (self.webhook_transport) |wt| {
            for (hooks) |h| {
                if (std.mem.indexOf(u8, h.events, event) == null) continue;
                const payload = std.fmt.allocPrint(self.allocator, "{{\"event\":\"{s}\",\"order_id\":{d},\"account_id\":{d}}}", .{ event, order_id, account_id }) catch continue;
                defer self.allocator.free(payload);
                const Transport = @import("../../http/webhook_transport.zig");
                const t: *Transport.WebhookTransport = @ptrCast(@alignCast(wt));
                t.post(h.url, payload) catch {};
            }
        }
    }

    // ── 文章 ─────────────────────────────────────────────

    pub fn createArticle(self: *ShopService, tenant_id: i64, account_id: i64, title: []const u8, content: []const u8) ShopError!i64 {
        if (std.mem.trim(u8, title, " \t").len == 0) return error.InvalidInput;
        return self.store.createArticle(tenant_id, account_id, title, content, self.now()) catch error.Unexpected;
    }

    pub fn listArticles(self: *ShopService, page: usize, page_size: usize, tenant_id: i64, account_id: i64, on_sale: bool) ShopError!ArticleListResult {
        return self.store.listArticles(page, page_size, tenant_id, account_id, on_sale) catch error.Unexpected;
    }

    pub fn getArticle(self: *ShopService, id: i64) ShopError!?ShopArticleRow {
        return self.store.getArticle(id) catch error.Unexpected;
    }

    pub fn deleteArticle(self: *ShopService, id: i64) ShopError!void {
        _ = self.store.deleteArticle(id) catch return error.Unexpected;
    }

    // ── 邀请有礼 ─────────────────────────────────────────

    pub fn createInviteGift(self: *ShopService, tenant_id: i64, account_id: i64, target_count: i64, reward_type: []const u8, reward_value: i64) ShopError!i64 {
        if (target_count <= 0 or reward_value <= 0) return error.InvalidInput;
        if (!std.mem.eql(u8, reward_type, "points") and !std.mem.eql(u8, reward_type, "coupon")) return error.InvalidInput;
        return self.store.createInviteGift(tenant_id, account_id, target_count, reward_type, reward_value, self.now()) catch error.Unexpected;
    }

    pub fn listInviteGifts(self: *ShopService, tenant_id: i64, account_id: i64) ShopError![]ShopInviteGiftRow {
        return self.store.listInviteGifts(tenant_id, account_id) catch error.Unexpected;
    }

    pub fn deleteInviteGift(self: *ShopService, id: i64) ShopError!void {
        _ = self.store.deleteInviteGift(id) catch return error.Unexpected;
    }

    /// 绑定邀请关系：新粉丝带邀请人 openid → 记录（幂等）；邀请人达标 → 发奖励。
    pub fn bindInvite(self: *ShopService, tenant_id: i64, account_id: i64, inviter_openid: []const u8, invitee_openid: []const u8) ShopError!void {
        if (std.mem.eql(u8, inviter_openid, invitee_openid)) return error.InvalidInput;
        if (!(self.store.bindInvite(tenant_id, account_id, inviter_openid, invitee_openid, self.now()) catch return error.Unexpected)) return; // 已绑定
        // 达标判定：任一配置满足即发奖（按 target_count 匹配）。
        const gifts = self.store.listInviteGifts(tenant_id, account_id) catch return;
        defer {
            for (gifts) |g| g.free(self.allocator);
            if (gifts.len > 0) self.allocator.free(gifts);
        }
        const invited = self.store.countInvites(tenant_id, inviter_openid) catch return;
        for (gifts) |g| {
            if (g.target_count == invited) {
                self.grantInviteReward(tenant_id, account_id, inviter_openid, g) catch {};
            }
        }
    }

    /// 发放奖励：points → 会员积分；coupon → 领券。
    fn grantInviteReward(self: *ShopService, tenant_id: i64, account_id: i64, openid: []const u8, g: ShopInviteGiftRow) !void {
        if (std.mem.eql(u8, g.reward_type, "points")) {
            if (self.member_svc) |ms| {
                const mc_mod = @import("../member_card/service.zig");
                const msvc: *mc_mod.MemberCardService = @ptrCast(@alignCast(ms));
                _ = msvc.adjust(tenant_id, account_id, openid, g.reward_value) catch {};
            }
        } else if (std.mem.eql(u8, g.reward_type, "coupon")) {
            if (self.coupon_svc) |cs| {
                const c_mod = @import("../coupon/service.zig");
                const csvc: *c_mod.CouponService = @ptrCast(@alignCast(cs));
                _ = csvc.claimCoupon(self.allocator, tenant_id, account_id, openid, g.reward_value) catch {};
            }
        }
    }

    // ── 拼团 ─────────────────────────────────────────────

    pub fn createGroupon(self: *ShopService, tenant_id: i64, account_id: i64, product_id: i64, group_price: i64, group_size: i64, start_at: i64, end_at: i64) ShopError!i64 {
        if (group_price <= 0 or group_size < 2) return error.InvalidInput;
        const p_opt = self.store.getProduct(product_id) catch return error.Unexpected;
        const p = p_opt orelse return error.NotFound;
        p.free(self.allocator);
        return self.store.createGroupon(tenant_id, account_id, product_id, group_price, group_size, start_at, end_at, self.now()) catch error.Unexpected;
    }

    pub fn listGroupons(self: *ShopService, tenant_id: i64, account_id: i64) ShopError![]ShopGrouponRow {
        return self.store.listGroupons(tenant_id, account_id) catch error.Unexpected;
    }

    /// 团价下单（内部）：校验商品 → 扣 SKU 库存 → 团价订单 + 明细。
    fn grouponOrder(self: *ShopService, tenant_id: i64, account_id: i64, openid: []const u8, address_id: i64, activity: ShopGrouponRow, sku_id: i64, team_id: i64) ShopError!i64 {
        const addr_opt = self.store.getAddress(address_id) catch return error.Unexpected;
        const addr = addr_opt orelse return error.InvalidInput;
        defer addr.free(self.allocator);
        const address_json = std.json.Stringify.valueAlloc(self.allocator, .{
            .name = addr.name, .mobile = addr.mobile, .region = addr.region, .detail = addr.detail,
        }, .{}) catch return error.Unexpected;
        defer self.allocator.free(address_json);

        const sku_opt = self.store.getSku(sku_id) catch return error.Unexpected;
        const sku = sku_opt orelse return error.NotFound;
        defer sku.free(self.allocator);
        if (!(self.store.consumeSkuStock(self.allocator, sku_id, 1) catch return error.Unexpected)) return error.OutOfStock;

        const order_no = self.genOrderNo() catch return error.Unexpected;
        defer self.allocator.free(order_no);
        const now_secs = self.now();
        const order_id = self.store.createOrder(tenant_id, account_id, order_no, "", openid, activity.group_price, activity.group_price, address_json, "delivery", "", 0, team_id, now_secs) catch return error.Unexpected;

        const p_opt = self.store.getProduct(activity.product_id) catch return error.Unexpected;
        const p = p_opt orelse return error.NotFound;
        defer p.free(self.allocator);
        _ = self.store.createOrderProduct(tenant_id, account_id, order_id, .{
            .product_id = activity.product_id,
            .sku_id = sku_id,
            .name = p.name,
            .image = p.image,
            .spec_json = sku.spec_json,
            .price = activity.group_price,
            .quantity = 1,
        }, now_secs) catch return error.Unexpected;
        self.store.addProductSales(activity.product_id, 1) catch {};
        return order_id;
    }

    /// 开团：leader 以团价下单 + 建团（current=1）。
    pub fn openGroupon(self: *ShopService, tenant_id: i64, account_id: i64, openid: []const u8, address_id: i64, activity_id: i64, sku_id: i64) ShopError!i64 {
        const a_opt = self.store.getGroupon(activity_id) catch return error.Unexpected;
        const a = a_opt orelse return error.NotFound;
        if (a.status != 1) return error.InvalidInput;
        const team_id = self.store.createTeam(tenant_id, account_id, activity_id, openid, self.now()) catch return error.Unexpected;
        _ = self.grouponOrder(tenant_id, account_id, openid, address_id, a, sku_id, team_id) catch |err| {
            return err;
        };
        return team_id;
    }

    /// 参团：团价下单 + current+1；成团 → 团内订单标记支付（mock）。
    pub fn joinGroupon(self: *ShopService, tenant_id: i64, account_id: i64, openid: []const u8, address_id: i64, team_id: i64, sku_id: i64) ShopError!i64 {
        const t_opt = self.store.getTeam(team_id) catch return error.Unexpected;
        const t = t_opt orelse return error.NotFound;
        defer t.free(self.allocator);
        if (t.status != 0) return error.InvalidInput; // 已结束
        const a_opt = self.store.getGroupon(t.activity_id) catch return error.Unexpected;
        const a = a_opt orelse return error.NotFound;
        const order_id = self.grouponOrder(tenant_id, account_id, openid, address_id, a, sku_id, team_id) catch |err| {
            return err;
        };
        if (self.store.joinTeam(self.allocator, team_id, a.group_size) catch false) {
            // 成团：团内全部订单 mock 支付 → 触发分销/积分。
            const orders = self.store.listOrdersByTeam(team_id) catch &.{};
            defer {
                for (orders) |o| o.free(self.allocator);
                if (orders.len > 0) self.allocator.free(orders);
            }
            for (orders) |o| {
                self.markPaid(tenant_id, account_id, o.id) catch {};
            }
        }
        return order_id;
    }

    // ── 门店自提 ──────────────────────────────────────────

    pub fn createOutlet(self: *ShopService, tenant_id: i64, account_id: i64, name: []const u8, address: []const u8, mobile: []const u8) ShopError!i64 {
        if (std.mem.trim(u8, name, " \t").len == 0) return error.InvalidInput;
        return self.store.createOutlet(tenant_id, account_id, name, address, mobile, self.now()) catch error.Unexpected;
    }

    pub fn listOutlets(self: *ShopService, tenant_id: i64, account_id: i64) ShopError![]persist.ShopOutletRow {
        return self.store.listOutlets(tenant_id, account_id) catch error.Unexpected;
    }

    pub fn deleteOutlet(self: *ShopService, id: i64) ShopError!void {
        _ = self.store.deleteOutlet(id) catch return error.Unexpected;
    }

    /// 自提核销：校验自提码 + 已支付（1）→ 状态置已完成（3）。
    pub fn pickupOrder(self: *ShopService, order_id: i64, code: []const u8) ShopError!void {
        const o_opt = self.store.getOrder(order_id) catch return error.Unexpected;
        const o = o_opt orelse return error.NotFound;
        defer o.free(self.allocator);
        if (o.status != 1) return error.OrderStateConflict;
        if (!std.mem.eql(u8, o.pickup_type, "self")) return error.OrderStateConflict;
        if (o.pickup_code.len == 0 or !std.mem.eql(u8, o.pickup_code, code)) return error.InvalidInput;
        _ = self.store.updateOrderStatus(order_id, 3, self.now()) catch return error.Unexpected;
    }
};

