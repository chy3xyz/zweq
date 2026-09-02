-- Seed test data for unix (C端) rendering
-- Run with: sqlite3 zweq.db < scripts/seed-unix-test-data.sql
-- Assumes default tenant_id=1, account_id=1

-- Clear existing test fan data to avoid duplicates
DELETE FROM fan WHERE openid LIKE 'dev_%';
DELETE FROM coupon_user WHERE openid LIKE 'dev_%';
DELETE FROM shop_order WHERE openid LIKE 'dev_%';
DELETE FROM wallet WHERE fan_id IN (SELECT id FROM fan WHERE openid LIKE 'dev_%');
DELETE FROM member_account WHERE openid LIKE 'dev_%';
DELETE FROM distributor WHERE openid LIKE 'dev_%';
DELETE FROM points_order WHERE openid LIKE 'dev_%';

-- 1. Test fan
INSERT INTO fan (tenant_id, account_id, openid, unionid, nickname, avatar, subscribed, subscribe_time, points)
VALUES (1, 1, 'dev_test_user_001', '', '测试用户', 'https://api.dicebear.com/7.x/avataaars/svg?seed=test001', 1, strftime('%s','now'), 1280);

-- 2. Member card levels
DELETE FROM member_card_level WHERE account_id = 1;
INSERT INTO member_card_level (tenant_id, account_id, name, level, discount, points_ratio, threshold, status) VALUES
(1, 1, '普通会员', 1, 1000, 100, 0, 1),
(1, 1, '银卡会员', 2, 950, 120, 1000, 1),
(1, 1, '金卡会员', 3, 900, 150, 5000, 1),
(1, 1, '黑卡会员', 4, 850, 200, 20000, 1);

-- 3. Member account for test fan (silver level)
INSERT INTO member_account (tenant_id, account_id, openid, level_id, points, total_points, created_at, updated_at)
VALUES (1, 1, 'dev_test_user_001', (SELECT id FROM member_card_level WHERE account_id=1 AND level=2), 1280, 5000, strftime('%s','now'), strftime('%s','now'));

-- 4. Distributor for test fan
INSERT INTO distributor (tenant_id, account_id, openid, parent_openid, commission_balance, total_commission, status)
VALUES (1, 1, 'dev_test_user_001', '', 5680, 12500, 1);

-- 5. Coupons
DELETE FROM coupon WHERE account_id = 1;
INSERT INTO coupon (tenant_id, account_id, title, amount, min_amount, total, per_user, start_at, end_at, status) VALUES
(1, 1, '新用户立减券', 500, 1000, 100, 1, strftime('%s','now','-1 day'), strftime('%s','now','+30 days'), 1),
(1, 1, '满100减20', 2000, 10000, 50, 2, strftime('%s','now','-1 day'), strftime('%s','now','+30 days'), 1),
(1, 1, '会员专享8折券', 8000, 5000, 30, 1, strftime('%s','now','-1 day'), strftime('%s','now','+30 days'), 1);

-- 6. Coupon assigned to test fan
INSERT INTO coupon_user (tenant_id, account_id, openid, coupon_id, code, status, used_at, created_at, updated_at)
SELECT 1, 1, 'dev_test_user_001', id, printf('CP%06d', id), 'unused', 0, strftime('%s','now'), strftime('%s','now') FROM coupon WHERE account_id = 1 LIMIT 2;

-- 7. Points products
DELETE FROM points_product WHERE account_id = 1;
INSERT INTO points_product (tenant_id, account_id, name, points, stock, status, image, detail) VALUES
(1, 1, '100元话费充值卡', 10000, 20, 1, 'https://picsum.photos/seed/points1/400/400', '<p>面值100元话费充值卡，支持三大运营商。</p>'),
(1, 1, '定制马克杯', 2500, 50, 1, 'https://picsum.photos/seed/points2/400/400', '<p>品牌定制马克杯，耐高温。</p>'),
(1, 1, '蓝牙耳机', 8000, 10, 1, 'https://picsum.photos/seed/points3/400/400', '<p>真无线蓝牙耳机，续航24小时。</p>'),
(1, 1, '充电宝', 6000, 15, 1, 'https://picsum.photos/seed/points4/400/400', '<p>20000mAh 大容量充电宝。</p>');

-- 8. Shop categories
DELETE FROM shop_category WHERE account_id = 1;
INSERT INTO shop_category (tenant_id, account_id, name, parent_id, sort) VALUES
(1, 1, '热门推荐', 0, 1),
(1, 1, '数码家电', 0, 2),
(1, 1, '食品饮料', 0, 3),
(1, 1, '日用百货', 0, 4);

-- 9. Shop products
DELETE FROM shop_product WHERE account_id = 1;
INSERT INTO shop_product (tenant_id, account_id, category_id, name, image, content, price, original_price, stock, sales, status) VALUES
(1, 1, (SELECT id FROM shop_category WHERE account_id=1 AND name='热门推荐'), '无线降噪耳机', 'https://picsum.photos/seed/prod1/400/400', '<p>高品质无线降噪耳机</p>', 29900, 39900, 100, 23, 1),
(1, 1, (SELECT id FROM shop_category WHERE account_id=1 AND name='数码家电'), '智能手表', 'https://picsum.photos/seed/prod2/400/400', '<p>运动健康智能手表</p>', 129900, 159900, 50, 8, 1),
(1, 1, (SELECT id FROM shop_category WHERE account_id=1 AND name='食品饮料'), '精品咖啡豆 500g', 'https://picsum.photos/seed/prod3/400/400', '<p>埃塞俄比亚耶加雪菲</p>', 8900, 12900, 200, 56, 1),
(1, 1, (SELECT id FROM shop_category WHERE account_id=1 AND name='日用百货'), '纯棉毛巾套装', 'https://picsum.photos/seed/prod4/400/400', '<p>3条装纯棉毛巾</p>', 4500, 6900, 300, 112, 1);

-- 10. 为全部 account_id=1 商品建默认 SKU（下单依赖 sku_id，无 sku 会报"商品不存在"）
INSERT INTO shop_product_sku (tenant_id, account_id, product_id, spec_json, image, price, stock, created_at, updated_at)
SELECT tenant_id, account_id, id, '[]', image, price, stock, strftime('%s','now'), strftime('%s','now') FROM shop_product WHERE account_id=1;

-- 10. Shop orders for test fan
-- status: 0=待支付 1=已支付 2=已发货 3=已完成 4=已取消
INSERT INTO shop_order (tenant_id, account_id, order_no, openid, total_amount, pay_amount, status, paid_at, pickup_type, created_at, updated_at)
VALUES
(1, 1, 'ORD202609020001', 'dev_test_user_001', 29900, 29900, 3, strftime('%s','now','-2 days'), 'delivery', strftime('%s','now','-2 days'), strftime('%s','now')),
(1, 1, 'ORD202609020002', 'dev_test_user_001', 8900, 8900, 2, strftime('%s','now','-1 day'), 'delivery', strftime('%s','now','-1 day'), strftime('%s','now')),
(1, 1, 'ORD202609020003', 'dev_test_user_001', 4500, 4500, 1, strftime('%s','now'), 'delivery', strftime('%s','now'), strftime('%s','now'));

-- 11. Wallet for test fan
INSERT INTO wallet (tenant_id, account_id, fan_id, balance, created_at, updated_at)
VALUES (1, 1, (SELECT id FROM fan WHERE openid='dev_test_user_001'), 15680, strftime('%s','now'), strftime('%s','now'));
