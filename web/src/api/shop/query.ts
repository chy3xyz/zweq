import { http } from '#ui/api/client';
import { APP_CONFIG } from '#ui/config';
import { unwrapEnvelope } from '#ui/api/envelope';

import { shopCategoriesQuery, shopProductsQuery, SHOP_PATH } from './path';
import type {
  CreateShopProductRequest,
  ShopArticleItem,
  ShopBalancePlanItem,
  ShopCategoryItem,
  ShopGrouponItem,
  ShopInviteGiftItem,
  ShopOrderItem,
  ShopOrderListResult,
  ShopOutletItem,
  ShopProductDetail,
  ShopProductItem,
  ShopProductListResult,
  ShopRefundItem,
  ShopRefundListResult,
  ShopSkuItem,
} from './types';

export async function listShopCategories(accountId: number): Promise<ShopCategoryItem[]> {
  const { data } = await http.get<{ code: number; msg: string; data: ShopCategoryItem[] }>(
    shopCategoriesQuery(accountId),
  );
  return unwrapEnvelope(data);
}

export async function createShopCategory(
  accountId: number,
  name: string,
): Promise<{ id: number }> {
  const { data } = await http.post<{ code: number; msg: string; data: { id: number } }>(
    SHOP_PATH.categories,
    { account_id: accountId, name },
  );
  return unwrapEnvelope(data);
}

export async function deleteShopCategory(id: number): Promise<void> {
  const { data } = await http.delete<{ code: number; msg: string; data: null }>(
    `${SHOP_PATH.categories}/${id}`,
  );
  unwrapEnvelope(data);
}

export async function listShopProducts(
  accountId: number,
  page: number,
  pageSize: number,
  keyword = '',
): Promise<ShopProductListResult> {
  const { data } = await http.get<{ code: number; msg: string; data: ShopProductListResult }>(
    shopProductsQuery(accountId, page, pageSize, keyword),
  );
  return unwrapEnvelope(data);
}

export async function createShopProduct(body: CreateShopProductRequest): Promise<{ id: number }> {
  const { data } = await http.post<{ code: number; msg: string; data: { id: number } }>(
    SHOP_PATH.products,
    body,
  );
  return unwrapEnvelope(data);
}

export async function updateShopProduct(id: number, body: CreateShopProductRequest): Promise<void> {
  const { data } = await http.put<{ code: number; msg: string; data: null }>(
    SHOP_PATH.product(id),
    body,
  );
  unwrapEnvelope(data);
}

export async function deleteShopProduct(id: number): Promise<void> {
  const { data } = await http.delete<{ code: number; msg: string; data: null }>(
    SHOP_PATH.product(id),
  );
  unwrapEnvelope(data);
}

export async function getShopProduct(id: number): Promise<ShopProductDetail> {
  const { data } = await http.get<{ code: number; msg: string; data: ShopProductDetail }>(
    SHOP_PATH.product(id),
  );
  return unwrapEnvelope(data);
}

export async function listShopOrders(
  accountId: number,
  page: number,
  pageSize: number,
  status = -1,
): Promise<ShopOrderListResult> {
  const params = new URLSearchParams({
    account_id: String(accountId),
    page: String(page),
    page_size: String(pageSize),
    status: String(status),
  });
  const { data } = await http.get<{ code: number; msg: string; data: ShopOrderListResult }>(
    `${SHOP_PATH.adminProducts.replace('/products', '/admin/orders')}?${params.toString()}`,
  );
  return unwrapEnvelope(data);
}

export async function shipShopOrder(id: number, company: string, no: string): Promise<void> {
  const { data } = await http.post<{ code: number; msg: string; data: null }>(
    `${APP_CONFIG.apiPrefix}/shop/admin/orders/${id}/ship`,
    { company, no },
  );
  unwrapEnvelope(data);
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
  const { data } = await http.get<{ code: number; msg: string; data: ShopRefundListResult }>(
    `${APP_CONFIG.apiPrefix}/shop/admin/refunds?${params.toString()}`,
  );
  return unwrapEnvelope(data);
}

export async function auditShopRefund(id: number, orderId: number, approve: boolean): Promise<void> {
  const { data } = await http.post<{ code: number; msg: string; data: null }>(
    `${APP_CONFIG.apiPrefix}/shop/admin/refunds/${id}/audit`,
    { order_id: orderId, approve },
  );
  unwrapEnvelope(data);
}

export async function listShopBalancePlans(accountId: number): Promise<ShopBalancePlanItem[]> {
  const params = new URLSearchParams({ account_id: String(accountId) });
  const { data } = await http.get<{ code: number; msg: string; data: ShopBalancePlanItem[] }>(
    `${APP_CONFIG.apiPrefix}/shop/balance-plans?${params.toString()}`,
  );
  return unwrapEnvelope(data);
}

export async function createShopBalancePlan(
  accountId: number,
  name: string,
  amount: number,
  bonus: number,
): Promise<{ id: number }> {
  const { data } = await http.post<{ code: number; msg: string; data: { id: number } }>(
    `${APP_CONFIG.apiPrefix}/shop/admin/balance-plans`,
    { account_id: accountId, name, amount, bonus },
  );
  return unwrapEnvelope(data);
}

export async function deleteShopBalancePlan(id: number): Promise<void> {
  const { data } = await http.delete<{ code: number; msg: string; data: null }>(
    `${APP_CONFIG.apiPrefix}/shop/admin/balance-plans/${id}`,
  );
  unwrapEnvelope(data);
}

export async function listShopOutlets(accountId: number): Promise<ShopOutletItem[]> {
  const params = new URLSearchParams({ account_id: String(accountId) });
  const { data } = await http.get<{ code: number; msg: string; data: ShopOutletItem[] }>(
    `${APP_CONFIG.apiPrefix}/shop/outlets?${params.toString()}`,
  );
  return unwrapEnvelope(data);
}

export async function createShopOutlet(
  accountId: number,
  name: string,
  address: string,
  mobile: string,
): Promise<{ id: number }> {
  const { data } = await http.post<{ code: number; msg: string; data: { id: number } }>(
    `${APP_CONFIG.apiPrefix}/shop/admin/outlets`,
    { account_id: accountId, name, address, mobile },
  );
  return unwrapEnvelope(data);
}

export async function deleteShopOutlet(id: number): Promise<void> {
  const { data } = await http.delete<{ code: number; msg: string; data: null }>(
    `${APP_CONFIG.apiPrefix}/shop/admin/outlets/${id}`,
  );
  unwrapEnvelope(data);
}

export async function createShopGroupon(
  accountId: number,
  productId: number,
  groupPrice: number,
  groupSize: number,
): Promise<{ id: number }> {
  const { data } = await http.post<{ code: number; msg: string; data: { id: number } }>(
    `${APP_CONFIG.apiPrefix}/shop/admin/groupons`,
    { account_id: accountId, product_id: productId, group_price: groupPrice, group_size: groupSize },
  );
  return unwrapEnvelope(data);
}

export async function createInviteGift(
  accountId: number,
  targetCount: number,
  rewardType: string,
  rewardValue: number,
): Promise<{ id: number }> {
  const { data } = await http.post<{ code: number; msg: string; data: { id: number } }>(
    `${APP_CONFIG.apiPrefix}/shop/admin/invite-gifts`,
    { account_id: accountId, target_count: targetCount, reward_type: rewardType, reward_value: rewardValue },
  );
  return unwrapEnvelope(data);
}

export async function deleteInviteGift(id: number): Promise<void> {
  const { data } = await http.delete<{ code: number; msg: string; data: null }>(
    `${APP_CONFIG.apiPrefix}/shop/admin/invite-gifts/${id}`,
  );
  unwrapEnvelope(data);
}

export async function createArticle(
  accountId: number,
  title: string,
  content: string,
): Promise<{ id: number }> {
  const { data } = await http.post<{ code: number; msg: string; data: { id: number } }>(
    `${APP_CONFIG.apiPrefix}/shop/admin/articles`,
    { account_id: accountId, title, content },
  );
  return unwrapEnvelope(data);
}

export async function deleteArticle(id: number): Promise<void> {
  const { data } = await http.delete<{ code: number; msg: string; data: null }>(
    `${APP_CONFIG.apiPrefix}/shop/admin/articles/${id}`,
  );
  unwrapEnvelope(data);
}

export async function listInviteGifts(accountId: number): Promise<ShopInviteGiftItem[]> {
  const params = new URLSearchParams({ account_id: String(accountId) });
  const { data } = await http.get<{ code: number; msg: string; data: ShopInviteGiftItem[] }>(
    `${APP_CONFIG.apiPrefix}/shop/invites/gifts?${params.toString()}`,
  );
  return unwrapEnvelope(data);
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
  const { data } = await http.get<{ code: number; msg: string; data: { list: ShopArticleItem[]; total: number } }>(
    `${APP_CONFIG.apiPrefix}/shop/admin/articles?${params.toString()}`,
  );
  return unwrapEnvelope(data);
}

export type {
  CreateShopProductRequest,
  ShopCategoryItem,
  ShopProductDetail,
  ShopProductItem,
  ShopOrderItem,
  ShopOrderListResult,
  ShopProductListResult,
  ShopSkuItem,
};
