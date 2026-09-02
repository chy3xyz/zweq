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
  status: number;
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
  /** 活动标题快照；活动已删除时为空串（前端兜底显示 activity_id）。 */
  activity_title?: string;
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
  status?: number;
}

/** 整体更新：字段同 `CreateSeckillRequest` 去 account_id（account 作用域不变）。 */
export interface UpdateSeckillRequest {
  title: string;
  price: number;
  original_price?: number;
  stock: number;
  per_user?: number;
  start_at?: number;
  end_at?: number;
  status?: number;
}
