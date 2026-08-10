export type OrderStatus = 'pending' | 'paid' | 'closed';

export interface OrderItem {
  id: number;
  order_no: string;
  fan_id: number;
  amount: number;
  channel: string;
  status: OrderStatus;
  paid_at: number;
  created_at: number;
}

export interface OrderListResult {
  list: OrderItem[];
  total: number;
  page: number;
  pageSize: number;
}

export interface WalletItem {
  account_id: number;
  fan_id: number;
  balance: number;
}

export interface WithdrawItem {
  id: number;
  fan_id: number;
  amount: number;
  status: string;
  created_at: number;
}

export interface WithdrawListResult {
  list: WithdrawItem[];
  total: number;
  page: number;
  pageSize: number;
}

export interface RechargeRequest {
  account_id: number;
  fan_id: number;
  amount: number;
}

export interface WithdrawRequest {
  account_id: number;
  fan_id: number;
  amount: number;
}
