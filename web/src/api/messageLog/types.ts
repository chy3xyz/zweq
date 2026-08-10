export interface LogItem {
  id: number;
  account_id: number;
  msg_id: string;
  openid: string;
  msg_type: string;
  event: string;
  content: string;
  reply_type: string;
  reply_content: string;
  created_at: number;
}

export interface LogListResult {
  list: LogItem[];
  total: number;
  page: number;
  pageSize: number;
}
