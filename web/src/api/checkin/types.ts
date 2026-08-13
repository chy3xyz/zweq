export interface CheckinRecord {
  id: number;
  openid: string;
  account_id: number;
  points: number;
  created_at: number;
}

export interface CheckinRecordListResult {
  list: CheckinRecord[];
  total: number;
  page: number;
  pageSize: number;
}
