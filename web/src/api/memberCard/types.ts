export interface MemberCardLevelItem {
  id: number;
  account_id: number;
  name: string;
  level: number;
  discount: number;
  points_ratio: number;
  threshold: number;
  created_at: number;
}

export interface MemberLevelListResult {
  list: MemberCardLevelItem[];
  total: number;
  page: number;
  pageSize: number;
}

export interface MemberAccountItem {
  id: number;
  account_id: number;
  openid: string;
  level_id: number;
  points: number;
  total_points: number;
  created_at: number;
}

export interface MemberAccountListResult {
  list: MemberAccountItem[];
  total: number;
  page: number;
  pageSize: number;
}

export interface MemberView {
  openid: string;
  level_name: string;
  level: number;
  discount: number;
  points: number;
  total_points: number;
  created_at: number;
}

export interface CreateLevelRequest {
  account_id: number;
  name: string;
  level?: number;
  discount?: number;
  points_ratio?: number;
  threshold?: number;
}
