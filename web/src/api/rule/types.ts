export type RuleStatus = 'active' | 'disabled';
export type MatchType = 'full' | 'contain';
export type ReplyType = 'text' | 'news';

export interface RuleItem {
  id: number;
  account_id: number;
  name: string;
  status: RuleStatus;
  created_at: number;
  updated_at: number;
}

export interface RuleListResult {
  list: RuleItem[];
  total: number;
  page: number;
  pageSize: number;
}

export interface KeywordItem {
  id: number;
  rule_id: number;
  keyword: string;
  match_type: MatchType;
}

export interface ReplyItem {
  id: number;
  rule_id: number;
  reply_type: ReplyType;
  content: string;
  news_title: string;
  news_description: string;
  news_pic_url: string;
  news_url: string;
}

export interface CreateRuleRequest {
  account_id: number;
  name: string;
}

export interface UpdateRuleRequest {
  name?: string;
  status?: RuleStatus;
}

export interface AddKeywordRequest {
  keyword: string;
  match_type: MatchType;
}

export interface AddReplyRequest {
  reply_type: ReplyType;
  content?: string;
  news_title?: string;
  news_description?: string;
  news_pic_url?: string;
  news_url?: string;
}
