export interface FanItem {
  id: number;
  account_id: number;
  openid: string;
  unionid: string;
  nickname: string;
  avatar: string;
  subscribed: boolean;
  subscribe_time: number;
  created_at: number;
}

export interface FanListResult {
  list: FanItem[];
  total: number;
  page: number;
  pageSize: number;
}
