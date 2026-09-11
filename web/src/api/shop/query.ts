import { deleteEnvelope, getEnvelope, postEnvelope, putEnvelope } from '#ui/api/client';
import { APP_CONFIG } from '#ui/config';

import { shopCategoriesQuery, shopOrdersQuery, shopProductsQuery, SHOP_PATH } from './path';
import type {
  CreateShopProductRequest,
  ShopArticleItem,
  ShopBalancePlanItem,
  ShopCategoryItem,
  ShopGrouponItem,
  ShopInviteGiftItem,
  ShopOrderDetail,
  ShopOrderItem,
  ShopOrderListResult,
  ShopOrderProductItem,
  ShopOutletItem,
  ShopProductDetail,
  ShopProductItem,
  ShopProductListResult,
  ShopRefundItem,
  ShopRefundListResult,
  ShopSkuItem,
} from './types';

export async function listShopCategories(accountId: number): Promise<ShopCategoryItem[]> {
  return getEnvelope<ShopCategoryItem[]>(
    shopCategoriesQuery(accountId),
  );
}

export async function createShopCategory(
  accountId: number,
  name: string,
): Promise<{ id: number }> {
  return postEnvelope<{ id: number }>(
    SHOP_PATH.categories,
    { account_id: accountId, name },
  );
}

export async function deleteShopCategory(id: number): Promise<void> {
  await deleteEnvelope<null>(
    `${SHOP_PATH.categories}/${id}`,
  );
}

export async function listShopProducts(
  accountId: number,
  page: number,
  pageSize: number,
  keyword = '',
  categoryId = 0,
  status = -1,
): Promise<ShopProductListResult> {
  return getEnvelope<ShopProductListResult>(
    shopProductsQuery(accountId, page, pageSize, keyword, categoryId, status),
  );
}

export async function createShopProduct(body: CreateShopProductRequest): Promise<{ id: number }> {
  return postEnvelope<{ id: number }>(
    SHOP_PATH.products,
    body,
  );
}

export async function updateShopProduct(id: number, body: CreateShopProductRequest): Promise<void> {
  await putEnvelope<null>(
    SHOP_PATH.product(id),
    body,
  );
}

export async function deleteShopProduct(id: number): Promise<void> {
  await deleteEnvelope<null>(
    SHOP_PATH.product(id),
  );
}

export async function getShopProduct(id: number): Promise<ShopProductDetail> {
  return getEnvelope<ShopProductDetail>(
    SHOP_PATH.product(id),
  );
}

export async function listShopOrders(
  accountId: number,
  page: number,
  pageSize: number,
  status = -1,
  openid = '',
  pickupType = '',
): Promise<ShopOrderListResult> {
  return getEnvelope<ShopOrderListResult>(
    shopOrdersQuery(accountId, page, pageSize, status, openid, pickupType),
  );
}

export async function getShopOrderDetail(id: number): Promise<ShopOrderDetail> {
  return getEnvelope<ShopOrderDetail>(
    SHOP_PATH.order(id),
  );
}

export async function shipShopOrder(id: number, company: string, no: string): Promise<void> {
  await postEnvelope<null>(
    `${APP_CONFIG.apiPrefix}/shop/admin/orders/${id}/ship`,
    { company, no },
  );
}

export async function pickupShopOrder(id: number, code: string): Promise<void> {
  await postEnvelope<null>(
    `${APP_CONFIG.apiPrefix}/shop/admin/orders/${id}/pickup`,
    { code },
  );
}

export async function listShopRefunds(
  accountId: number,
  page: number,
  pageSize: number,
  status = -1,
): Promise<ShopRefundListResult> {
  const params = new URLSearchParams({
    account_id: String(accountId),
    page: String(page),
    page_size: String(pageSize),
    status: String(status),
  });
  return getEnvelope<ShopRefundListResult>(
    `${APP_CONFIG.apiPrefix}/shop/admin/refunds?${params.toString()}`,
  );
}

export async function auditShopRefund(id: number, orderId: number, approve: boolean): Promise<void> {
  await postEnvelope<null>(
    `${APP_CONFIG.apiPrefix}/shop/admin/refunds/${id}/audit`,
    { order_id: orderId, approve },
  );
}

export async function listShopBalancePlans(accountId: number): Promise<ShopBalancePlanItem[]> {
  const params = new URLSearchParams({ account_id: String(accountId) });
  return getEnvelope<ShopBalancePlanItem[]>(
    `${APP_CONFIG.apiPrefix}/shop/balance-plans?${params.toString()}`,
  );
}

export async function createShopBalancePlan(
  accountId: number,
  name: string,
  amount: number,
  bonus: number,
): Promise<{ id: number }> {
  return postEnvelope<{ id: number }>(
    `${APP_CONFIG.apiPrefix}/shop/admin/balance-plans`,
    { account_id: accountId, name, amount, bonus },
  );
}

export async function deleteShopBalancePlan(id: number): Promise<void> {
  await deleteEnvelope<null>(
    `${APP_CONFIG.apiPrefix}/shop/admin/balance-plans/${id}`,
  );
}

export async function listShopOutlets(accountId: number): Promise<ShopOutletItem[]> {
  const params = new URLSearchParams({ account_id: String(accountId) });
  return getEnvelope<ShopOutletItem[]>(
    `${APP_CONFIG.apiPrefix}/shop/outlets?${params.toString()}`,
  );
}

export async function createShopOutlet(
  accountId: number,
  name: string,
  address: string,
  mobile: string,
): Promise<{ id: number }> {
  return postEnvelope<{ id: number }>(
    `${APP_CONFIG.apiPrefix}/shop/admin/outlets`,
    { account_id: accountId, name, address, mobile },
  );
}

export async function deleteShopOutlet(id: number): Promise<void> {
  await deleteEnvelope<null>(
    `${APP_CONFIG.apiPrefix}/shop/admin/outlets/${id}`,
  );
}

export async function createShopGroupon(
  accountId: number,
  productId: number,
  groupPrice: number,
  groupSize: number,
): Promise<{ id: number }> {
  return postEnvelope<{ id: number }>(
    `${APP_CONFIG.apiPrefix}/shop/admin/groupons`,
    { account_id: accountId, product_id: productId, group_price: groupPrice, group_size: groupSize },
  );
}

export async function createInviteGift(
  accountId: number,
  targetCount: number,
  rewardType: string,
  rewardValue: number,
): Promise<{ id: number }> {
  return postEnvelope<{ id: number }>(
    `${APP_CONFIG.apiPrefix}/shop/admin/invite-gifts`,
    { account_id: accountId, target_count: targetCount, reward_type: rewardType, reward_value: rewardValue },
  );
}

export async function deleteInviteGift(id: number): Promise<void> {
  await deleteEnvelope<null>(
    `${APP_CONFIG.apiPrefix}/shop/admin/invite-gifts/${id}`,
  );
}

export async function createArticle(
  accountId: number,
  title: string,
  content: string,
): Promise<{ id: number }> {
  return postEnvelope<{ id: number }>(
    `${APP_CONFIG.apiPrefix}/shop/admin/articles`,
    { account_id: accountId, title, content },
  );
}

export async function deleteArticle(id: number): Promise<void> {
  await deleteEnvelope<null>(
    `${APP_CONFIG.apiPrefix}/shop/admin/articles/${id}`,
  );
}

export async function listInviteGifts(accountId: number): Promise<ShopInviteGiftItem[]> {
  const params = new URLSearchParams({ account_id: String(accountId) });
  return getEnvelope<ShopInviteGiftItem[]>(
    `${APP_CONFIG.apiPrefix}/shop/invites/gifts?${params.toString()}`,
  );
}

export async function listShopArticles(
  accountId: number,
  page = 1,
  pageSize = 50,
): Promise<{ list: ShopArticleItem[]; total: number }> {
  const params = new URLSearchParams({
    account_id: String(accountId),
    page: String(page),
    page_size: String(pageSize),
  });
  return getEnvelope<{ list: ShopArticleItem[]; total: number }>(
    `${APP_CONFIG.apiPrefix}/shop/admin/articles?${params.toString()}`,
  );
}

export type {
  CreateShopProductRequest,
  ShopCategoryItem,
  ShopProductDetail,
  ShopProductItem,
  ShopOrderDetail,
  ShopOrderItem,
  ShopOrderListResult,
  ShopOrderProductItem,
  ShopProductListResult,
  ShopSkuItem,
};
