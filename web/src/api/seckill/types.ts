export interface SeckillActivityItem {
  id: number;
  account_id: number;
  title: string;
  price: number;
  original_price: number;
  stock: number;
  sold: number;
  per_user: number;
  start_at: number;
  end_at: number;
  created_at: number;
}

export interface SeckillListResult {
  list: SeckillActivityItem[];
  total: number;
  page: number;
  pageSize: number;
}

export interface SeckillOrderItem {
  id: number;
  account_id: number;
  openid: string;
  activity_id: number;
  quantity: number;
  created_at: number;
}

export interface CreateSeckillRequest {
  account_id: number;
  title: string;
  price: number;
  original_price?: number;
  stock: number;
  per_user?: number;
  start_at?: number;
  end_at?: number;
}
