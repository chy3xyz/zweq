//! 交易域服务：购物车 / 地址 / 下单（预算变体）/ 订单状态机 / 退款 / 评论 / 收藏 / 统计 / 超时关单（拆分自原 ShopService 单体，方法正文逐字搬运）。
const std = @import("std");
const zigmodu = @import("zigmodu");
const zent = @import("zent");
const persist = @import("../persistence.zig");
const schema = @import("../../../schema.zig");
const crud = zent.crud_helpers;
const coupon_service = @import("../../coupon/service.zig");
const member_persist = @import("../../member/persistence.zig");
const task_service = @import("../../task/service.zig");
const db_mod = @import("../../../db.zig");
const host = @import("../service.zig");

// 宿主符号沿用原名（方法正文逐字搬运、零改动）。
const ShopService = host.ShopService;
const ShopError = host.ShopError;
const ProductInput = host.ProductInput;
const SkuInput = host.SkuInput;
const OrderItemInput = host.OrderItemInput;
const AddressInput = host.AddressInput;
const OrderSummary = host.OrderSummary;
const OrderStats = host.OrderStats;
const FanOrderOverview = host.FanOrderOverview;
const ShopCategoryRow = host.ShopCategoryRow;
const ShopProductRow = host.ShopProductRow;
const ShopSkuRow = host.ShopSkuRow;
const CategoryListResult = host.CategoryListResult;
const ProductListResult = host.ProductListResult;
const ShopCartRow = host.ShopCartRow;
const ShopAddressRow = host.ShopAddressRow;
const ShopOrderRow = host.ShopOrderRow;
const ShopOrderProductRow = host.ShopOrderProductRow;
const OrderListResult = host.OrderListResult;
const ShopRefundRow = host.ShopRefundRow;
const ShopCommentRow = host.ShopCommentRow;
const RefundListResult = host.RefundListResult;
const ShopFavoriteRow = host.ShopFavoriteRow;
const ShopOutletRow = host.ShopOutletRow;
const ShopBalancePlanRow = host.ShopBalancePlanRow;
const ShopGrouponRow = host.ShopGrouponRow;
const ShopGrouponTeamRow = host.ShopGrouponTeamRow;
const ShopInviteGiftRow = host.ShopInviteGiftRow;
const ShopInviteRecordRow = host.ShopInviteRecordRow;
const ShopArticleRow = host.ShopArticleRow;
const ArticleListResult = host.ArticleListResult;
const ShopWebhookRow = host.ShopWebhookRow;

pub fn addCart(self: *ShopService, tenant_id: i64, account_id: i64, openid: []const u8, product_id: i64, sku_id: i64, quantity: i64) ShopError!i64 {
    if (quantity <= 0) return error.InvalidInput;
    const sku_opt = self.store.catalog.getSku(sku_id) catch return error.Unexpected;
    const sku = sku_opt orelse return error.NotFound;
    sku.free(self.allocator);
    return self.store.trade.upsertCart(tenant_id, account_id, openid, product_id, sku_id, quantity, self.now()) catch error.Unexpected;
}

pub fn listCarts(self: *ShopService, tenant_id: i64, openid: []const u8) ShopError![]ShopCartRow {
    return self.store.trade.listCarts(tenant_id, openid) catch error.Unexpected;
}

pub fn updateCart(self: *ShopService, tenant_id: i64, openid: []const u8, id: i64, quantity: i64) ShopError!void {
    if (quantity <= 0) return error.InvalidInput;
    if (!(self.store.trade.updateCartQuantity(tenant_id, openid, id, quantity) catch return error.Unexpected)) return error.NotFound;
}

pub fn deleteCart(self: *ShopService, tenant_id: i64, openid: []const u8, id: i64) ShopError!void {
    if (!(self.store.trade.deleteCart(tenant_id, openid, id) catch return error.Unexpected)) return error.NotFound;
}

// ── 地址 ─────────────────────────────────────────────

pub fn createAddress(self: *ShopService, tenant_id: i64, account_id: i64, a: AddressInput) ShopError!i64 {
    if (std.mem.trim(u8, a.name, " \t").len == 0 or std.mem.trim(u8, a.mobile, " \t").len == 0) return error.InvalidInput;
    return self.store.trade.createAddress(tenant_id, account_id, a, self.now()) catch error.Unexpected;
}

pub fn listAddresses(self: *ShopService, tenant_id: i64, openid: []const u8) ShopError![]ShopAddressRow {
    return self.store.trade.listAddresses(tenant_id, openid) catch error.Unexpected;
}

pub fn deleteAddress(self: *ShopService, tenant_id: i64, openid: []const u8, id: i64) ShopError!void {
    if (!(self.store.trade.deleteAddress(tenant_id, openid, id) catch return error.Unexpected)) return error.NotFound;
}

pub fn setAddressDefault(self: *ShopService, tenant_id: i64, openid: []const u8, id: i64) ShopError!void {
    self.store.trade.setDefaultAddress(tenant_id, openid, id, self.now()) catch |err| switch (err) {
        error.AddressNotFound => return error.NotFound,
        error.InvalidInput => return error.InvalidInput,
        else => return error.Unexpected,
    };
}

pub fn updateAddress(self: *ShopService, tenant_id: i64, openid: []const u8, id: i64, a: anytype) ShopError!void {
    if (std.mem.trim(u8, a.name, " \t").len == 0 or std.mem.trim(u8, a.mobile, " \t").len == 0) return error.InvalidInput;
    self.store.trade.updateAddress(tenant_id, openid, id, a, self.now()) catch |err| switch (err) {
        error.AddressNotFound => return error.NotFound,
        error.InvalidInput => return error.InvalidInput,
        else => return error.Unexpected,
    };
}

// ── 下单引擎 ─────────────────────────────────────────

/// 自提核销码：6 位数字（PK 前缀展示用）。
pub fn genPickupCode(self: *ShopService) ![]const u8 {
    var buf: [4]u8 = undefined;
    var file = try std.Io.Dir.cwd().openFile(self.io, "/dev/urandom", .{});
    defer file.close(self.io);
    const read = try file.readPositionalAll(self.io, &buf, 0);
    if (read != buf.len) return error.Unexpected;
    const n = std.mem.readInt(u32, &buf, .little) % 1000000;
    return std.fmt.allocPrint(self.allocator, "{d:0>6}", .{n});
}

/// 唯一订单号：SO + 秒级时间戳 + 8 字节随机 hex（防撞号）。
pub fn genOrderNo(self: *ShopService) ![]const u8 {
    var buf: [8]u8 = undefined;
    var file = try std.Io.Dir.cwd().openFile(self.io, "/dev/urandom", .{});
    defer file.close(self.io);
    const read = try file.readPositionalAll(self.io, &buf, 0);
    if (read != buf.len) return error.Unexpected;
    return std.fmt.allocPrint(self.allocator, "SO{d}{x:0>16}", .{ self.now(), std.mem.readInt(u64, &buf, .little) });
}

/// 下单：校验商品/SKU/库存 → 原子扣库存 → 生成订单号 → 写订单+明细。
/// 返回订单 id。支付由 payment 模块承接（mock 即时入账 / v3 微信支付）。
/// 无请求预算的调用点（测试/内部）走这里；HTTP 入口用 createOrderBudget。
pub fn createOrder(self: *ShopService, tenant_id: i64, account_id: i64, openid: []const u8, address_id: i64, items: []const OrderItemInput, coupon_code: []const u8, client_trade_no: []const u8, pay_type: []const u8, pickup_store_id: i64, remark: []const u8) ShopError!i64 {
    return self.createOrderBudget(tenant_id, account_id, openid, address_id, items, coupon_code, client_trade_no, pay_type, pickup_store_id, remark, null);
}

/// createOrder 的请求预算版：budget_ms 为 zigmodu ctx.deadline_ms（CLOCK_MONOTONIC
/// 毫秒绝对 deadline，null = 无界）。事务获取（池等待）按预算上限阻塞、超预算
/// 报 RequestTimeout；预算耗尽时前置拒绝，不再启动事务。
pub fn createOrderBudget(self: *ShopService, tenant_id: i64, account_id: i64, openid: []const u8, address_id: i64, items: []const OrderItemInput, coupon_code: []const u8, client_trade_no: []const u8, pay_type: []const u8, pickup_store_id: i64, remark: []const u8, budget_ms: ?i64) ShopError!i64 {
    // 幂等：同 client_trade_no 已存在 → 返回原单（不重复扣库存）。
    if (client_trade_no.len > 0) {
        if (self.store.trade.getByClientTradeNo(tenant_id, client_trade_no) catch return error.Unexpected) |existing| {
            defer existing.free(self.allocator);
            return existing.id;
        }
    }
    if (items.len == 0) return error.InvalidInput;
    // 地址快照（带 tenant 归属：防跨租户把他人收货地址 PII 写进订单）。
    const addr_opt = self.store.trade.getAddress(tenant_id, address_id) catch return error.Unexpected;
    const addr = addr_opt orelse return error.InvalidInput;
    defer addr.free(self.allocator);
    const address_json = std.json.Stringify.valueAlloc(self.allocator, .{
        .name = addr.name,
        .mobile = addr.mobile,
        .region = addr.region,
        .detail = addr.detail,
        .remark = remark,
    }, .{}) catch return error.Unexpected;
    defer self.allocator.free(address_json);

    // 逐项校验 + 原子扣库存 + 汇总金额
    var total: i64 = 0;
    const order_no = self.genOrderNo() catch return error.Unexpected;
    defer self.allocator.free(order_no);
    var pickup_code_owned: ?[]const u8 = null;
    defer if (pickup_code_owned) |c| self.allocator.free(c);

    // 事务：扣库存 + 建单 + 明细 原子提交（SQLite/Postgres 均支持）；失败整体回滚。
    // beginTxCtx 携带请求预算：池等待按剩余预算上限阻塞（zent borrowCtx），
    // 超预算 → PoolWaitTimeout → RequestTimeout；预算已耗尽则前置拒绝，
    // 不启动事务（事务内语句的 deadline 化见 request_budget 中间件说明，
    // 属逐步推进项）。
    if (db_mod.budgetSpent(budget_ms)) return error.RequestTimeout;
    var exec_ctx = db_mod.execContext(budget_ms);
    var tx = zent.codegen.beginTxCtx(schema.infos, self.store.client, if (exec_ctx.deadline_ns != null) &exec_ctx else null) catch |err| switch (err) {
        error.PoolWaitTimeout, error.QueryTimeout => return error.RequestTimeout,
        else => return error.Unexpected,
    };
    // 提交后须立即归还池连接（连接在 deinit 时才 release），否则提交后的
    // 余额支付/订单明细查询在 max_connections=1（:memory:）下必然耗尽。
    // 错误路径先显式回滚再释放（池层 rollback 幂等），避免依赖 deinit 兜底。
    // 本函数内所有 rollback()/deinit 失败只吞错：各失败分支均已 return 具体错误
    // 给调用方，回滚失败无可挽回，且下面 defer 兜底会再回滚一次。
    var tx_closed = false;
    defer if (!tx_closed) {
        tx.rollback() catch {};
        tx.deinit();
    };
    for (items) |it| {
        // 事务内读写必须走 tx.client：连接池下事务独占借用的连接，
        // 再从池里借会 PoolExhausted；即便借得到，也读不到本事务未提交的写。
        if (it.sku_id == 0) {
            // 无 SKU 商品：回退商品主数据（价格/库存）下单。tenant 归属校验：
            // 拿不到别租户商品，防跨租户拿价下单。
            const product_opt = self.store.catalog.getProductOn(tx.client, tenant_id, it.product_id) catch return error.Unexpected;
            const product = product_opt orelse return error.NotFound;
            defer product.free(self.allocator);
            const pp = tx.client.shop_product.predicates;
            // 库存守卫参数化（zent.sql.RawArgs）：数量走绑定参数而非拼进 SQL 文本。
            const affected = crud.increment(tx.client.shop_product, "stock", -it.quantity, &.{
                pp.idEQ(.{ .int = it.product_id }),
                zent.sql.RawArgs("stock >= ?", &.{.{ .int = it.quantity }}),
            }) catch {
                tx.rollback() catch {};
                return error.OutOfStock;
            };
            if (affected == 0) {
                tx.rollback() catch {};
                return error.OutOfStock;
            }
            const product_price = std.fmt.parseInt(i64, product.price, 10) catch return error.Unexpected;
            total += product_price * it.quantity;
            _ = crud.increment(tx.client.shop_product, "sales", it.quantity, &.{pp.idEQ(.{ .int = it.product_id })}) catch |err| std.log.err("[shop] 下单累计商品销量失败 product_id={d} quantity={d} err={s}", .{ it.product_id, it.quantity, @errorName(err) });
        } else {
            const sp = tx.client.shop_product_sku.predicates;
            const sku_opt = self.store.catalog.getSkuOn(tx.client, tenant_id, it.sku_id) catch return error.Unexpected;
            const sku = sku_opt orelse return error.NotFound;
            defer sku.free(self.allocator);
            // 库存守卫参数化（zent.sql.RawArgs），同商品分支。
            const affected = crud.increment(tx.client.shop_product_sku, "stock", -it.quantity, &.{
                sp.idEQ(.{ .int = it.sku_id }),
                zent.sql.RawArgs("stock >= ?", &.{.{ .int = it.quantity }}),
            }) catch {
                tx.rollback() catch {};
                return error.OutOfStock;
            };
            if (affected == 0) {
                tx.rollback() catch {};
                return error.OutOfStock;
            }
            const sku_price = std.fmt.parseInt(i64, sku.price, 10) catch return error.Unexpected;
            total += sku_price * it.quantity;
            const pp = tx.client.shop_product.predicates;
            _ = crud.increment(tx.client.shop_product, "sales", it.quantity, &.{pp.idEQ(.{ .int = it.product_id })}) catch |err| std.log.err("[shop] 下单累计商品销量失败 product_id={d} quantity={d} err={s}", .{ it.product_id, it.quantity, @errorName(err) });
        }
    }

    // 优惠券减免：code 可选，经 coupon 模块 service 的事务内窄方法校验
    // 归属/未用/门槛并核销（CouponService.redeemOnOrder——核销标记必须随
    // 订单事务提交/回滚，属文档化的 persistence 直读例外）。
    var discount: i64 = 0;
    if (coupon_code.len > 0) {
        if (self.coupon_svc) |cs| {
            const csvc: *coupon_service.CouponService = @ptrCast(@alignCast(cs));
            discount = csvc.redeemOnOrder(tx.client, coupon_code, openid, total) catch |err| switch (err) {
                error.InvalidInput => return error.InvalidInput,
                else => return error.Unexpected,
            };
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
        const total_amount_str = std.fmt.allocPrint(self.allocator, "{d}", .{total}) catch {
            tx.rollback() catch {};
            return error.Unexpected;
        };
        defer self.allocator.free(total_amount_str);
        const pay_amount_str = std.fmt.allocPrint(self.allocator, "{d}", .{pay_amount}) catch {
            tx.rollback() catch {};
            return error.Unexpected;
        };
        defer self.allocator.free(pay_amount_str);
        var row = crud.create(tx.client.shop_order, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .order_no = order_no,
            .client_trade_no = client_trade_no,
            .openid = openid,
            .total_amount = total_amount_str,
            .pay_amount = pay_amount_str,
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
        defer tx.client.shop_order.deinitRow(&row);
        break :blk row.id;
    };

    for (items) |it| {
        const sku_opt = self.store.catalog.getSkuOn(tx.client, tenant_id, it.sku_id) catch return error.Unexpected;
        const sku = sku_opt orelse return error.NotFound;
        defer sku.free(self.allocator);
        const p_opt = self.store.catalog.getProductOn(tx.client, tenant_id, it.product_id) catch return error.Unexpected;
        const p = p_opt orelse return error.NotFound;
        defer p.free(self.allocator);
        const sku_price = std.fmt.parseInt(i64, sku.price, 10) catch return error.Unexpected;
        const sku_price_str = std.fmt.allocPrint(self.allocator, "{d}", .{sku_price}) catch {
            tx.rollback() catch {};
            return error.Unexpected;
        };
        defer self.allocator.free(sku_price_str);
        var op_row = crud.create(tx.client.shop_order_product, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .order_id = order_id,
            .product_id = it.product_id,
            .sku_id = it.sku_id,
            .name = p.name,
            .image = p.image,
            .spec_json = sku.spec_json,
            .price = sku_price_str,
            .quantity = it.quantity,
            .created_at = now_secs,
            .updated_at = now_secs,
        }) catch {
            tx.rollback() catch {};
            return error.Unexpected;
        };
        defer tx.client.shop_order_product.deinitRow(&op_row);
    }

    // 事务提交（原子）。提交后马上归还池连接，后续查询才借得到。
    tx.commit() catch return error.Unexpected;
    tx.deinit();
    tx_closed = true;

    // 余额支付：pay_type=balance → 扣买家钱包（openid → fan_id），成功即标记支付。
    if (std.mem.eql(u8, pay_type, "balance")) {
        if (self.payment_svc) |ps| {
            if (self.fan_store) |fs| {
                const fan_opt = fs.getByOpenid(tenant_id, account_id, openid) catch return error.Unexpected;
                const fan = fan_opt orelse return error.NotFound;
                defer fan.free(self.allocator);
                const pay_mod = @import("../../payment/service.zig");
                const psvc: *pay_mod.PaymentService = @ptrCast(@alignCast(ps));
                const ok = psvc.payWithBalance(tenant_id, account_id, fan.id, pay_amount) catch false;
                if (!ok) {
                    // 条件取消：仅本次请求把 0→4 命中时才回滚库存，
                    // 与用户手动取消并发时不会双倍返还。
                    if (self.store.trade.cancelOrderOn(tenant_id, openid, order_id, self.now()) catch false) {
                        // 事务已提交，显式回滚：订单已取消（本函数即将返回 InsufficientBalance），
                        // 库存返还失败无可挽回，留痕供人工对账。
                        self.store.trade.restoreOrderStock(order_id) catch |err| std.log.err("[shop] 余额支付失败回滚订单库存失败 order_id={d} err={s}", .{ order_id, @errorName(err) });
                    }
                    return error.InsufficientBalance;
                }
                // 钱包已扣款；标记支付失败会让订单停在待支付（钱已走、单未结），留痕。
                self.markPaid(tenant_id, account_id, order_id) catch |err| std.log.err("[shop] 余额支付成功后标记订单已支付失败 order_id={d} err={s}", .{ order_id, @errorName(err) });
            }
        }
    }
    return order_id;
}

pub fn getOrder(self: *ShopService, id: i64) ShopError!?ShopOrderRow {
    return self.store.trade.getOrder(id) catch error.Unexpected;
}

pub fn listOrders(self: *ShopService, page: usize, page_size: usize, tenant_id: i64, account_id: i64, openid: []const u8, status: i64, pickup_type: []const u8) ShopError!OrderListResult {
    return self.listOrdersBudget(page, page_size, tenant_id, account_id, openid, status, pickup_type, null);
}

/// listOrders 的请求预算版（budget_ms = ctx.deadline_ms，null = 无界）：
/// 查询超预算 → zent QueryTimeout/PoolWaitTimeout → RequestTimeout。
/// HTTP 入口（管理端订单列表/C 端我的订单）用本变体；智能客服等内部
/// 旁路读保持无界（原方法）。
pub fn listOrdersBudget(self: *ShopService, page: usize, page_size: usize, tenant_id: i64, account_id: i64, openid: []const u8, status: i64, pickup_type: []const u8, budget_ms: ?i64) ShopError!OrderListResult {
    return self.store.trade.listOrdersBudget(page, page_size, tenant_id, account_id, openid, status, pickup_type, budget_ms) catch |err| switch (err) {
        error.PoolWaitTimeout, error.QueryTimeout => error.RequestTimeout,
        else => error.Unexpected,
    };
}

pub fn listOrderProducts(self: *ShopService, order_id: i64) ShopError![]ShopOrderProductRow {
    return self.store.trade.listOrderProducts(order_id) catch error.Unexpected;
}

pub fn getOrderProduct(self: *ShopService, id: i64) ShopError!?ShopOrderProductRow {
    return self.store.trade.getOrderProduct(id) catch error.Unexpected;
}

/// 支付成功回调（payment 模块调用）：状态 0→1 原子条件更新，只命中一次。
/// 事件驱动：有 bus → publish OrderPaidEvent（消费者处理分销/积分/通知）；
/// 无 bus → 同步回退（单测/最小部署兼容）。
/// 幂等：重复/并发回调 affected=0 时读回当前状态——已是 1 → 直接返回
/// （不重复分佣/积分）；其他状态 → 异常回调，返回错误。
pub fn markPaid(self: *ShopService, tenant_id: i64, account_id: i64, order_id: i64) ShopError!void {
    if (!(self.store.trade.markPaidOn(tenant_id, order_id, self.now()) catch return error.Unexpected)) {
        const o_opt = self.store.trade.getOrder(order_id) catch return error.Unexpected;
        const o = o_opt orelse return error.NotFound;
        defer o.free(self.allocator);
        if (o.status == 1) return; // 已支付：幂等返回，奖励只发一次
        return error.OrderStateConflict; // 已取消/已完成等：非法回调
    }
    if (self.order_paid_bus) |bus| {
        bus.publish(.{ .tenant_id = tenant_id, .account_id = account_id, .order_id = order_id });
        return;
    }
    // 同步回退：分销 + 积分。
    if (self.dist_svc) |ds| {
        const o_opt = self.store.trade.getOrder(order_id) catch return;
        const o = o_opt orelse return;
        defer o.free(self.allocator);
        const pay_amount = std.fmt.parseInt(i64, o.pay_amount, 10) catch return;
        const dist_mod = @import("../../distribution/service.zig");
        const dsvc: *dist_mod.DistributionService = @ptrCast(@alignCast(ds));
        // 买家已支付成功，分佣失败只影响上级佣金，不阻断订单；留痕供对账。
        _ = dsvc.distribute(tenant_id, account_id, o.openid, pay_amount) catch |err| std.log.err("[shop] 支付成功同步分佣失败 openid={s} amount={d} err={s}", .{ o.openid, pay_amount, @errorName(err) });
    }
    // 会员积分累计：1 元 = 1 积分。
    if (self.member_svc) |ms| {
        const o_opt2 = self.store.trade.getOrder(order_id) catch return;
        const o2 = o_opt2 orelse return;
        defer o2.free(self.allocator);
        const pay_amount2 = std.fmt.parseInt(i64, o2.pay_amount, 10) catch return;
        const mc_mod = @import("../../member_card/service.zig");
        const msvc: *mc_mod.MemberCardService = @ptrCast(@alignCast(ms));
        // 同上：积分漏记不阻断支付流程，留痕供对账。
        _ = msvc.adjust(tenant_id, account_id, o2.openid, @divTrunc(pay_amount2, 100)) catch |err| std.log.err("[shop] 支付成功累计会员积分失败 openid={s} err={s}", .{ o2.openid, @errorName(err) });
    }
}

/// 取消订单（仅待支付可取消，可取消状态集 = {0}，与原语义一致）。
/// 原子条件更新 WHERE(id + openid + tenant_id + status=0)：并发/重复取消
/// 只有一个调用方 affected=1，库存回滚恰好执行一次（防双回滚）。
/// affected=0 时读回当前状态区分：已是取消态(4) → 幂等成功；
/// 不存在/归属不符 → NotFound（IDOR 按不存在处理）；其他状态 → 冲突。
pub fn cancelOrder(self: *ShopService, tenant_id: i64, openid: []const u8, order_id: i64) ShopError!void {
    if (self.store.trade.cancelOrderOn(tenant_id, openid, order_id, self.now()) catch return error.Unexpected) {
        // 订单已取消且本函数返回成功；库存返还失败只影响后续可售库存，留痕对账。
        self.store.trade.restoreOrderStock(order_id) catch |err| std.log.err("[shop] 取消订单回滚库存失败 order_id={d} err={s}", .{ order_id, @errorName(err) });
        return;
    }
    const o_opt = self.store.trade.getOrder(order_id) catch return error.Unexpected;
    const o = o_opt orelse return error.NotFound;
    defer o.free(self.allocator);
    if (o.status == 4) return; // 已是取消态：幂等成功（不再回滚库存）
    if (!std.mem.eql(u8, o.openid, openid)) return error.NotFound; // 他人订单：不泄露存在性
    if (o.status == 0) return error.NotFound; // openid 匹配但未命中：租户不符，按不存在处理
    return error.OrderStateConflict;
}

/// 确认收货（已发货 → 已完成）。
pub fn confirmOrder(self: *ShopService, order_id: i64) ShopError!void {
    const o_opt = self.store.trade.getOrder(order_id) catch return error.Unexpected;
    const o = o_opt orelse return error.NotFound;
    defer o.free(self.allocator);
    if (o.status != 2) return error.OrderStateConflict;
    _ = self.store.trade.updateOrderStatus(order_id, 3, self.now()) catch return error.Unexpected;
}

/// 管理端发货。
pub fn shipOrder(self: *ShopService, order_id: i64, company: []const u8, no: []const u8) ShopError!void {
    const o_opt = self.store.trade.getOrder(order_id) catch return error.Unexpected;
    const o = o_opt orelse return error.NotFound;
    defer o.free(self.allocator);
    if (o.status != 1) return error.OrderStateConflict;
    _ = self.store.trade.updateOrderExpress(order_id, company, no, self.now()) catch return error.Unexpected;
    _ = self.store.trade.updateOrderStatus(order_id, 2, self.now()) catch return error.Unexpected;
}

// ── 退款 ──────────────────────────────────────────────

/// 申请退款（仅已支付/已发货可申请；一单一退）。
pub fn applyRefund(self: *ShopService, tenant_id: i64, account_id: i64, order_id: i64, openid: []const u8, reason: []const u8) ShopError!i64 {
    const o_opt = self.store.trade.getOrder(order_id) catch return error.Unexpected;
    const o = o_opt orelse return error.NotFound;
    defer o.free(self.allocator);
    if (o.status == 0 or o.status == 4) return error.OrderStateConflict;
    if (self.store.trade.getRefundByOrder(tenant_id, order_id) catch null) |existing| {
        existing.free(self.allocator);
        return error.Duplicate;
    }
    const pay_amount = std.fmt.parseInt(i64, o.pay_amount, 10) catch return error.Unexpected;
    return self.store.trade.createRefund(tenant_id, account_id, order_id, openid, reason, pay_amount, self.now()) catch error.Unexpected;
}

pub fn listRefunds(self: *ShopService, page: usize, page_size: usize, tenant_id: i64, account_id: i64, status: i64) ShopError!RefundListResult {
    return self.store.trade.listRefunds(page, page_size, tenant_id, account_id, status) catch error.Unexpected;
}

pub fn listRefundsByOpenid(self: *ShopService, page: usize, page_size: usize, tenant_id: i64, account_id: i64, openid: []const u8) ShopError!RefundListResult {
    return self.store.trade.listRefundsByOpenid(page, page_size, tenant_id, account_id, openid) catch error.Unexpected;
}
pub fn orderSummaries(self: *ShopService, order_ids: []const i64) ShopError![]OrderSummary {
    var out = std.ArrayList(OrderSummary).empty;
    errdefer {
        for (out.items) |s| s.free(self.allocator);
        out.deinit(self.allocator);
    }
    // 一条 IN 查询拉全部明细，内存里按 order_id 分组（原逐单查询在公开
    // 接口上是 N+1：30 个 id = 30 条 SQL）。
    const all = self.store.trade.listOrderProductsByIds(order_ids) catch return error.Unexpected;
    defer {
        for (all) |op| op.free(self.allocator);
        if (all.len > 0) self.allocator.free(all);
    }
    for (order_ids) |oid| {
        var first: ?ShopOrderProductRow = null;
        var count: i64 = 0;
        for (all) |op| {
            if (op.order_id != oid) continue;
            if (first == null) first = op;
            count += 1;
        }
        const cover_image = if (first) |op|
            (self.allocator.dupe(u8, op.image) catch return error.Unexpected)
        else
            (self.allocator.dupe(u8, "") catch return error.Unexpected);
        errdefer self.allocator.free(cover_image);
        const summary = if (count > 1)
            std.fmt.allocPrint(self.allocator, "{s} 等{d}件", .{ first.?.name, count }) catch return error.Unexpected
        else if (count == 1)
            (self.allocator.dupe(u8, first.?.name) catch return error.Unexpected)
        else
            (self.allocator.dupe(u8, "") catch return error.Unexpected);
        out.append(self.allocator, .{
            .order_id = oid,
            .cover_image = cover_image,
            .item_count = count,
            .summary = summary,
        }) catch return error.Unexpected;
    }
    return out.toOwnedSlice(self.allocator) catch error.Unexpected;
}

pub fn getRefundByOrder(self: *ShopService, tenant_id: i64, order_id: i64) ShopError!?ShopRefundRow {
    const row_opt = self.store.trade.getRefundByOrder(tenant_id, order_id) catch return error.Unexpected;
    return row_opt;
}

/// 退款审核：同意 → 订单置为已取消（4）+ 回滚库存与销量。
/// refund 状态翻转（pending→终态，条件更新）与 订单状态/库存回滚 包在
/// 同一事务（beginTxFromDriver + *On 变体走 tx.client），三写要么全提交
/// 要么全回滚；重复审核 affected=0 → 幂等返回，绝不重复回滚库存。
/// HTTP 入口用 auditRefundBudget（带请求预算）。
pub fn auditRefund(self: *ShopService, order_id: i64, refund_id: i64, approve: bool) ShopError!void {
    return self.auditRefundBudget(order_id, refund_id, approve, null);
}

/// auditRefund 的请求预算版（budget_ms = ctx.deadline_ms，null = 无界）：
/// 事务获取按剩余预算阻塞、超预算/已耗尽 → RequestTimeout。
pub fn auditRefundBudget(self: *ShopService, order_id: i64, refund_id: i64, approve: bool, budget_ms: ?i64) ShopError!void {
    const target: i64 = if (approve) 1 else 2;
    const now_secs = self.now();
    if (db_mod.budgetSpent(budget_ms)) return error.RequestTimeout;
    var exec_ctx = db_mod.execContext(budget_ms);
    // shop 模块私有 graph 的事务：TxClient(persist.infos)，故 *On 变体
    // 均为 `client: anytype`（root Client / TxClient 均可传入）。
    var tx = zent.codegen.beginTxFromDriverCtx(persist.infos, self.store.client.driver, self.allocator, if (exec_ctx.deadline_ns != null) &exec_ctx else null) catch |err| switch (err) {
        error.PoolWaitTimeout, error.QueryTimeout => return error.RequestTimeout,
        else => return error.Unexpected,
    };
    var tx_closed = false;
    // 未提交路径由 defer 兜底回滚；回滚/释放失败只吞错：各失败分支均已 return 错误，
    // 幂等返回分支本就无需持久化，回滚失败无可挽回。
    defer if (!tx_closed) {
        tx.rollback() catch {};
        tx.deinit();
    };
    // 条件更新：仅 pending(0)→终态 命中一次。
    const flipped = self.store.trade.auditRefundOn(tx.client, refund_id, target, now_secs) catch return error.Unexpected;
    if (!flipped) {
        // 区分：退款单不存在 → NotFound；已终态 → 幂等返回（不重复回滚）。
        const r_opt = self.store.trade.getRefundByIdOn(tx.client, refund_id) catch return error.Unexpected;
        const r = r_opt orelse return error.NotFound;
        defer r.free(self.allocator);
        if (r.status != 0) return; // 已被审核过（重复提交/双击）：幂等返回
        return error.Unexpected; // 兜底：既不命中又非终态（正常不可达）
    }
    if (approve) {
        // 订单状态 + 库存回滚与 refund 翻转同事务提交。
        _ = self.store.trade.updateOrderStatusOn(tx.client, order_id, 4, now_secs) catch return error.Unexpected;
        // 事务随后仍会提交（退款审批已生效）；库存/销量回滚失败无可挽回，留痕对账。
        self.store.trade.restoreOrderStockOn(tx.client, order_id) catch |err| std.log.err("[shop] 退款审核通过后回滚订单库存失败 order_id={d} err={s}", .{ order_id, @errorName(err) });
    }
    tx.commit() catch return error.Unexpected;
    tx.deinit();
    tx_closed = true;
}

// ── 评价 ──────────────────────────────────────────────

pub fn createComment(self: *ShopService, tenant_id: i64, account_id: i64, c: anytype) ShopError!i64 {
    if (c.star < 1 or c.star > 5) return error.InvalidInput;
    // 实名校验：评价人必须是该订单买家，且订单已完成（3）才可评。
    const op_opt = self.store.trade.getOrderProduct(c.order_product_id) catch return error.Unexpected;
    const op = op_opt orelse return error.NotFound;
    defer op.free(self.allocator);
    const o_opt = self.store.trade.getOrder(op.order_id) catch return error.Unexpected;
    const o = o_opt orelse return error.NotFound;
    defer o.free(self.allocator);
    if (!std.mem.eql(u8, o.openid, c.openid)) return error.InvalidInput;
    if (o.status != 3) return error.OrderStateConflict;
    if (self.store.trade.getCommentByOrderProduct(c.order_product_id) catch return error.Unexpected) |existing| {
        existing.free(self.allocator);
        return error.Duplicate;
    }
    return self.store.trade.createComment(tenant_id, account_id, c, self.now()) catch error.Unexpected;
}

pub fn listCommentedOrderProductIds(self: *ShopService, order_id: i64) ShopError![]i64 {
    const ops = self.store.trade.listOrderProducts(order_id) catch return error.Unexpected;
    defer {
        for (ops) |op| op.free(self.allocator);
        if (ops.len > 0) self.allocator.free(ops);
    }
    var ids = std.ArrayList(i64).empty;
    errdefer ids.deinit(self.allocator);
    for (ops) |op| {
        if (self.store.trade.getCommentByOrderProduct(op.id) catch return error.Unexpected) |existing| {
            existing.free(self.allocator);
            ids.append(self.allocator, op.id) catch return error.Unexpected;
        }
    }
    return ids.toOwnedSlice(self.allocator) catch error.Unexpected;
}

pub fn listComments(self: *ShopService, product_id: i64) ShopError![]ShopCommentRow {
    return self.store.trade.listCommentsByProduct(product_id) catch error.Unexpected;
}

// ── 收藏 ──────────────────────────────────────────────

pub fn favorite(self: *ShopService, tenant_id: i64, account_id: i64, openid: []const u8, product_id: i64) ShopError!void {
    const p_opt = self.store.catalog.getProduct(product_id) catch return error.Unexpected;
    const p = p_opt orelse return error.NotFound;
    p.free(self.allocator);
    self.store.trade.favorite(tenant_id, account_id, openid, product_id, self.now()) catch return error.Unexpected;
}

pub fn isFavorite(self: *ShopService, tenant_id: i64, openid: []const u8, product_id: i64) ShopError!bool {
    return self.store.trade.isFavorite(tenant_id, openid, product_id) catch error.Unexpected;
}

pub fn unfavorite(self: *ShopService, id: i64) ShopError!void {
    _ = self.store.trade.unfavorite(id) catch return error.Unexpected;
}

pub fn listFavorites(self: *ShopService, tenant_id: i64, openid: []const u8) ShopError![]ShopFavoriteRow {
    return self.store.trade.listFavorites(tenant_id, openid) catch error.Unexpected;
}

// ── 订单统计（管理端） ───────────────────────────────
pub fn fanOrderOverview(self: *ShopService, tenant_id: i64, account_id: i64, openid: []const u8, order_timeout_secs: i64) ShopError!FanOrderOverview {
    return .{
        .pending_pay = self.store.trade.countOrdersByStatusOpenid(tenant_id, account_id, openid, 0) catch return error.Unexpected,
        .pending_ship = self.store.trade.countOrdersByStatusOpenid(tenant_id, account_id, openid, 1) catch return error.Unexpected,
        .shipped = self.store.trade.countOrdersByStatusOpenid(tenant_id, account_id, openid, 2) catch return error.Unexpected,
        .completed = self.store.trade.countOrdersByStatusOpenid(tenant_id, account_id, openid, 3) catch return error.Unexpected,
        .order_timeout_secs = order_timeout_secs,
    };
}

pub fn orderStats(self: *ShopService, tenant_id: i64, account_id: i64) ShopError!OrderStats {
    return .{
        .pending_pay = self.store.trade.countOrdersByStatus(tenant_id, account_id, 0) catch return error.Unexpected,
        .pending_ship = self.store.trade.countOrdersByStatus(tenant_id, account_id, 1) catch return error.Unexpected,
        .completed = self.store.trade.countOrdersByStatus(tenant_id, account_id, 3) catch return error.Unexpected,
        .total_sales = self.store.trade.sumPaidAmount(tenant_id, account_id) catch return error.Unexpected,
    };
}

// ── 储值卡 ───────────────────────────────────────────
pub fn autoCancelExpired(self: *ShopService, tenant_id: i64, account_id: i64, timeout_secs: i64) ShopError!usize {
    const before = self.now() - timeout_secs;
    const expired = self.store.trade.listExpiredPending(tenant_id, account_id, before) catch return error.Unexpected;
    defer {
        for (expired) |o| o.free(self.allocator);
        if (expired.len > 0) self.allocator.free(expired);
    }
    var count: usize = 0;
    for (expired) |o| {
        // 条件取消：与用户手动取消/另一轮扫单并发时只有一个命中，
        // 库存回滚恰好一次（防双倍返还）。
        if (self.store.trade.cancelOrderOn(tenant_id, o.openid, o.id, self.now()) catch continue) {
            // 订单已取消（本函数返回成功）；库存返还失败会让可售库存偏低，留痕对账。
            self.store.trade.restoreOrderStock(o.id) catch |err| std.log.err("[shop] 超时取消订单回滚库存失败 order_id={d} err={s}", .{ o.id, @errorName(err) });
            count += 1;
        }
    }
    return count;
}

// ── AI 智能助手（订单上下文感知） ───────────────────
