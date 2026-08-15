export interface VoteItem {
  id: number;
  account_id: number;
  title: string;
  options_json: string;
  end_at: number;
  created_at: number;
}

export interface VoteListResult {
  list: VoteItem[];
  total: number;
  page: number;
  pageSize: number;
}

export interface CreateVoteRequest {
  account_id: number;
  title: string;
  options: string[];
  end_at?: number;
}
