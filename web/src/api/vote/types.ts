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

/** 整体更新：字段同 `CreateVoteRequest` 去 account_id（account 作用域不变）。 */
export interface UpdateVoteRequest {
  title: string;
  options: string[];
  end_at?: number;
}
