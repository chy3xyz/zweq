export interface CouponItem {
  id: number;
  account_id: number;
  title: string;
  amount: number;
  min_amount: number;
  total: number;
  per_user: number;
  start_at: number;
  end_at: number;
  created_at: number;
}

export interface CouponListResult {
  list: CouponItem[];
  total: number;
  page: number;
  pageSize: number;
}

export interface CouponUserItem {
  id: number;
  account_id: number;
  openid: string;
  coupon_id: number;
  code: string;
  status: 'unused' | 'used' | 'expired';
  used_at: number;
  created_at: number;
}

export interface CouponUserListResult {
  list: CouponUserItem[];
  total: number;
  page: number;
  pageSize: number;
}

export interface CreateCouponRequest {
  account_id: number;
  title: string;
  amount: number;
  min_amount?: number;
  total?: number;
  per_user?: number;
  start_at?: number;
  end_at?: number;
}
