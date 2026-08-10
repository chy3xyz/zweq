export type MaterialKind = 'image' | 'voice' | 'video';

export interface NewsItem {
  id: number;
  account_id: number;
  title: string;
  author: string;
  digest: string;
  content: string;
  thumb_media_id: string;
  thumb_url: string;
  url: string;
  created_at: number;
  updated_at: number;
}

export interface NewsListResult {
  list: NewsItem[];
  total: number;
  page: number;
  pageSize: number;
}

export interface MaterialFileItem {
  id: number;
  account_id: number;
  kind: MaterialKind;
  media_id: string;
  url: string;
  created_at: number;
}

export interface MaterialFileListResult {
  list: MaterialFileItem[];
  total: number;
  page: number;
  pageSize: number;
}

export interface CreateNewsRequest {
  account_id: number;
  title: string;
  author?: string;
  digest?: string;
  content?: string;
  thumb_media_id?: string;
  thumb_url?: string;
  url?: string;
}

export interface UpdateNewsRequest {
  title?: string;
  author?: string;
  digest?: string;
  content?: string;
  thumb_media_id?: string;
  thumb_url?: string;
  url?: string;
}

export interface CreateFileRequest {
  account_id: number;
  kind: MaterialKind;
  media_id: string;
  url?: string;
}
