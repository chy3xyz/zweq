export interface DistributorItem {
  id: number;
  account_id: number;
  openid: string;
  parent_openid: string;
  commission_balance: number;
  total_commission: number;
  status: number;
  created_at: number;
}

export interface DistributorListResult {
  list: DistributorItem[];
  total: number;
  page: number;
  pageSize: number;
}

export interface CommissionItem {
  id: number;
  account_id: number;
  openid: string;
  source_openid: string;
  level: number;
  amount: number;
  status: number;
  created_at: number;
}

export interface CommissionListResult {
  list: CommissionItem[];
  total: number;
  page: number;
  pageSize: number;
}

export interface JoinDistributorRequest {
  openid: string;
  parent_openid?: string;
}

export interface DistributeRequest {
  buyer_openid: string;
  order_amount: number;
}

export interface DistributorWithdrawRequest {
  openid: string;
  amount: number;
}
