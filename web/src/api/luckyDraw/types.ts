export interface DrawRecord {
  id: number;
  account_id: number;
  openid: string;
  prize_name: string;
  points: number;
  created_at: number;
}

export interface DrawRecordListResult {
  list: DrawRecord[];
  total: number;
  page: number;
  pageSize: number;
}

export interface ManualDrawRequest {
  account_id: number;
  openid: string;
  config?: string;
}

export interface ManualDrawResult {
  prize_name: string;
  points: number;
}
