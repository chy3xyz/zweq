export interface ShopCategoryItem {
  id: number;
  account_id: number;
  name: string;
  parent_id: number;
  sort: number;
}

export interface ShopProductItem {
  id: number;
  account_id: number;
  category_id: number;
  name: string;
  image: string;
  content: string;
  price: number;
  original_price: number;
  stock: number;
  sales: number;
  status: number;
  created_at: number;
}

export interface ShopProductListResult {
  list: ShopProductItem[];
  total: number;
  page: number;
  pageSize: number;
}

export interface ShopSkuItem {
  id: number;
  product_id: number;
  spec_json: string;
  image: string;
  price: number;
  stock: number;
}

export interface ShopProductDetail {
  product: ShopProductItem;
  skus: ShopSkuItem[];
}

export interface CreateShopProductRequest {
  account_id: number;
  category_id: number;
  name: string;
  image?: string;
  content?: string;
  price: number;
  original_price?: number;
  stock: number;
  status?: number;
  skus?: { spec_json: string; image: string; price: number; stock: number }[];
}

export interface ShopOrderItem {
  id: number;
  account_id: number;
  order_no: string;
  openid: string;
  total_amount: number;
  pay_amount: number;
  status: number;
  express_company: string;
  express_no: string;
  paid_at: number;
  created_at: number;
}

export interface ShopOrderListResult {
  list: ShopOrderItem[];
  total: number;
  page: number;
  pageSize: number;
}

export interface ShopRefundItem {
  id: number;
  account_id: number;
  order_id: number;
  openid: string;
  reason: string;
  amount: number;
  status: number;
  created_at: number;
}

export interface ShopRefundListResult {
  list: ShopRefundItem[];
  total: number;
  page: number;
  pageSize: number;
}

export interface ShopBalancePlanItem {
  id: number;
  account_id: number;
  name: string;
  amount: number;
  bonus: number;
  status: number;
}

export interface ShopOutletItem {
  id: number;
  account_id: number;
  name: string;
  address: string;
  mobile: string;
  status: number;
}

export interface ShopGrouponItem {
  id: number;
  account_id: number;
  product_id: number;
  group_price: number;
  group_size: number;
  status: number;
}

export interface ShopInviteGiftItem {
  id: number;
  account_id: number;
  target_count: number;
  reward_type: string;
  reward_value: number;
}

export interface ShopArticleItem {
  id: number;
  account_id: number;
  title: string;
  content: string;
  status: number;
  created_at: number;
}
